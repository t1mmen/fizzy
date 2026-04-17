# Grounding — Fizzy + Beads (Codex lens)

**Date**: 2026-04-17 (America/Vancouver)

Scope per Claude/Timm: (A) Fizzy data + API layer truth (what JSON exists vs HTML), (B) Beads internals (CLI surface + on-disk Dolt layout + schemas), then 5–7 initial alignment observations.

---

## A) Fizzy grounding (Rails app)

### A1) Multi-tenancy (URL path prefix “mounting”)

- **Middleware**: `config/initializers/tenanting/account_slug.rb`
  - Extracts a leading `/{digits}` prefix from `PATH_INFO` and moves it to `SCRIPT_NAME` so Rails routes behave as if mounted at that prefix.
  - Stashes tenant id into Rack env as `env["fizzy.external_account_id"]`.
  - Resolves `Account` via `external_account_id` and wraps request in `Current.with_account(account)` (or `Current.without_account` when missing).

Excerpt (core behavior):
```rb
# config/initializers/tenanting/account_slug.rb
if request.path_info =~ PATH_INFO_MATCH
  request.engine_script_name = request.script_name = $1
  request.path_info = $'.empty? ? "/" : $'
  env["fizzy.external_account_id"] = AccountSlug.decode($2)
end
```

Implication for “native beads tracker” fork: tenant context is *path-derived*, not subdomain-derived. Any beads UI/API layer inside Fizzy likely needs to preserve `SCRIPT_NAME` behavior so links and background jobs remain correctly tenanted.

---

### A2) Authentication/authorization nuances for JSON requests

- **Auth entrypoint**: `app/controllers/concerns/authentication.rb`
  - Cookie session resume always attempted (`Session.find_signed(cookies.signed[:session_token])`).
  - **Bearer token auth only allowed for JSON requests**:
    - `bearer_token_authenticatable_request?` is `request.format.json?`.
    - Identity resolved via `Identity.find_by_permissable_access_token(token, method: request.method)`.
- **CSRF**: `app/controllers/concerns/request_forgery_protection.rb`
  - `allowed_api_request?` returns true when `sec_fetch_site_value.nil? && request.format.json?`.
  - That makes JSON API calls possible without header CSRF token (intended for non-browser clients).

Token model:
- `app/models/identity/access_token.rb`
  - `has_secure_token`
  - `permission` enum: `read|write`
  - `allows?(method)` allows `GET|HEAD` always, write permission required otherwise.

---

### A3) Core data model (high-level)

**Account**
- Model: `app/models/account.rb`
- Fields: `db/schema.rb` (`accounts`)
  - `external_account_id` (bigint unique), `name`, `cards_count` (bigint counter).
- Relations: has many `users`, `boards`, `cards`, `webhooks`, `columns`, `tags`, `entropies`, `exports`, `imports`.

**Identity + User (membership)**
- `app/models/identity.rb`, `app/models/user.rb`
  - Identity is global (email-based), user is per-account membership with role.
- Schema: `db/schema.rb` tables `identities`, `users`, `identity_access_tokens`.

**Board / Column**
- `app/models/board.rb`, `app/models/column.rb`
- Schema: `db/schema.rb` tables `boards`, `columns`.
  - Board: `all_access` boolean.
  - Column: `position` (int), `color`, `name`.

**Access (board membership / recently accessed)**
- `app/models/access.rb`
- Schema: `db/schema.rb` table `accesses`
  - Uniqueness: `board_id + user_id` unique.
  - `involvement`: `access_only|watching`.

**Card**
- `app/models/card.rb`
- Schema: `db/schema.rb` table `cards`
  - Key fields: `number` (per-account unique), `status` (`drafted|published`), `last_active_at` (required), `due_on`, `column_id` nullable.
- Attachments/text:
  - `has_one_attached :image`
  - `has_rich_text :description`
- Lifecycle state is **composed** (not a single enum) via related rows:
  - Closed state: `closures` table via `Closure` model.
  - Not-now/postponed state: `card_not_nows` table via `Card::NotNow` model.
  - Entropy/autopostpone config: `entropies` polymorphic config (Account + Board).

**Closure (Done)**
- `app/models/card/closeable.rb` + `app/models/closure.rb`
- Schema: `db/schema.rb` table `closures`
  - Unique closure row per card (`card_id` unique).

**Not Now (postponed)**
- `app/models/card/postponable.rb` + `app/models/card/not_now.rb`
- Schema: `db/schema.rb` table `card_not_nows`
  - Unique not_now row per card (`card_id` unique).

**Entropy (auto-postpone)**
- `app/models/entropy.rb`, `app/models/board/entropic.rb`, `app/models/account/entropic.rb`, `app/models/card/entropic.rb`
- Config shape: `entropies` table `(container_type, container_id)` unique.
- Behavior:
  - Account gets default entropy row on create (`Account::Entropic`).
  - Board delegates to its entropy or falls back to account entropy (`Board::Entropic#entropy`).
  - `Card::Entropic.due_to_be_postponed` joins board entropy + account entropy and compares `last_active_at` with `COALESCE(...)`.

**Event + particulars**
- `app/models/event.rb`, `app/models/event/particulars.rb`
- Schema: `events` table includes `action` string and `particulars` JSON.
- `Event::Particulars#api_particulars` is action-dependent:
  - For `card_assigned|card_unassigned`: `{ "assignee_ids" => [...] }`
  - For `card_board_changed`: `{ "old_board" => "...", "new_board" => "..." }`
  - For `card_title_changed`, `card_triaged`: structured nested fields.

**Webhook (outbound)**
- `app/models/webhook.rb`, `app/models/webhook/delivery.rb`, views under `app/views/webhooks/`
- Schema: `webhooks`, `webhook_deliveries`
  - Webhook has `signing_secret` and `subscribed_actions` (serialized JSON array).
  - Delivery stores `request` and `response` JSON blobs, plus state machine: `pending|in_progress|completed|errored`.
- Outbound payload is rendered via Rails renderer:
  - JSON default: renders `app/views/webhooks/event.json.jbuilder`.
  - Slack: custom JSON containing plaintext + “Open in Fizzy” link.
  - Campfire/Basecamp: HTML or form encoded.

**Search (16-shard MySQL full-text)**
- `app/models/search/record/trilogy.rb`
  - `SHARD_COUNT = 16`
  - shard via `Zlib.crc32(account_id.to_s) % 16`
  - uses boolean fulltext query: `+account#{account_id} +(#{stemmed_terms})`

---

### A4) Card state transitions (closure / not_now / entropy)

**Close / reopen**
- `app/models/card/closeable.rb`
  - `close`: destroys `not_now`, creates `closure`, tracks event `:closed`.
  - `reopen`: destroys closure, tracks event `:reopened`.

**Postpone / resume**
- `app/models/card/postponable.rb`
  - `postpone`: sends back to triage (skip_event), reopens, destroys activity spike, creates `not_now`, tracks `:postponed` (or `:auto_postponed`).
  - `resume`: destroys `not_now`, reopens, destroys activity spike.

**Entropy calculation**
- `app/models/card/entropy.rb` is a computed helper:
  - `auto_clean_at = last_active_at + auto_postpone_period`
  - reminder is 25% of period.

---

### A5) Import/Export (Account::DataTransfer + large ZIP streaming)

**Export**
- `app/models/export.rb`, `app/models/account/export.rb`
  - `Account::Export#populate_zip` iterates `Account::DataTransfer::Manifest` record sets.
- ZIP streaming / large files:
  - `app/models/zip_file.rb`
    - S3 path uses multipart `upload_stream` with `part_size: 100.megabytes`.
    - Disk path uses tempfile.

**Import**
- `app/models/account/import.rb`, `app/controllers/account/imports_controller.rb`
  - Import “spins up” a new account via `Signup` then creates `Account::Import` with attached zip file.
  - `check` validates record ID integrity + conflict detection; `process` inserts via `insert_all!` batches.

**Manifest record set order** (import/export ordering)
- `app/models/account/data_transfer/manifest.rb`
  - includes core models and storage records: `ActiveStorage::Blob`, `ActionText::RichText`, etc.
  - `RecordSet#check_record` prevents importing records whose referenced belongs_to already exists (conflict/association check).

---

### A6) “Does a real HTTP/JSON API exist?”

**Observed reality**
- `config/routes.rb` has **no `/api` namespace** and no versioned JSON API.
- Many controllers respond to JSON **as a first-class internal interface** (Hotwire + native mobile clients), not as an explicit external API contract.

**JSON surface area is implemented via Jbuilder templates**, not ad-hoc JSON in controllers, for most domain resources:
- Example files:
  - `app/views/cards/_card.json.jbuilder`
  - `app/views/boards/_board.json.jbuilder`
  - `app/views/webhooks/event.json.jbuilder`
  - plus index/show templates for users, notifications, searches, etc.

**Card JSON schema (key fields)** — `app/views/cards/_card.json.jbuilder`
```rb
json.(card, :id, :number, :title, :status)
json.description card.description.to_plain_text
json.description_html card.description.to_s
json.image_url card.image.presence && url_for(card.image)
json.has_attachments card.has_attachments?
json.tags card.tags.pluck(:title).sort
json.closed card.closed?
json.postponed card.postponed?
json.golden card.golden?
json.last_active_at card.last_active_at.utc
json.created_at card.created_at.utc
json.url card_url(card)
```

**Board JSON schema (key fields)** — `app/views/boards/_board.json.jbuilder`
```rb
json.(board, :id, :name, :all_access)
json.auto_postpone_period_in_days board.auto_postpone_period_in_days
json.url board_url(board)
json.creator board.creator, partial: "users/user", as: :user
```

**Authentication makes JSON special**
- `Authentication#bearer_token_authenticatable_request?` is JSON-only.
- `RequestForgeryProtection#allowed_api_request?` is JSON-only with a missing `Sec-Fetch-Site`.

So: there *is* a usable HTTP+JSON surface, but it is “Rails controllers + Jbuilder + bearer token allowed when JSON”, not a clean external API module.

---

### A7) Rich text + attachments

- `has_rich_text` on `Card#description` and `Comment#body`.
- Attachments helper module: `app/models/concerns/attachments.rb`
  - Collects `rich_text_record.embeds`, remote images/videos attachables, and defines ActionText embed variants (processed eagerly to avoid read replica writes).

---

## B) Beads grounding (CLI + on-disk Dolt)

### B1) CLI surface (selected, verbatim excerpts)

Binary:
```bash
$ which bd
/opt/homebrew/bin/bd
```

`bd --help` (excerpt of relevant areas):
- Dependencies:
  - `bd dep` (dependency management)
  - `bd gate` (async wait conditions)
  - `bd merge-slot` (serialized conflict-resolution)
  - `bd swarm` (structured epic coordination)
- Workflow templating:
  - `bd formula` (formulas)
  - `bd mol` (molecules/protos/wisps)
- Integrations:
  - `bd jira`, `bd linear`, `bd github`, `bd ado`, `bd gitlab`, `bd notion`
- Federation:
  - `bd federation`
- Hooks + memories:
  - `bd hooks`, `bd remember`, `bd memories`, `bd recall`, `bd forget`

Dependency types (`bd dep add --help`):
```text
--type string Dependency type
(blocks|tracks|related|parent-child|discovered-from|until|caused-by|validates|relates-to|supersedes)
```

Gate types (`bd gate --help`):
```text
human   - Requires manual bd close (Phase 1)
timer   - Expires after timeout (Phase 2)
gh:run  - Waits for GitHub workflow (Phase 3)
gh:pr   - Waits for PR merge (Phase 3)
bead    - Waits for cross-rig bead to close (Phase 4)
```

Formula search paths (`bd formula --help`):
```text
1. .beads/formulas/ (project)
2. ~/.beads/formulas/ (user)
3. $GT_ROOT/.beads/formulas/ (orchestrator, if GT_ROOT set)
```

Integrations (example: `bd linear --help`):
- supports pull/push/bidirectional sync and explicit mapping config keys:
  - `linear.priority_map.*`, `linear.state_map.*`, `linear.label_type_map.*`, `linear.relation_map.*`, `linear.id_mode`, etc.

---

### B2) On-disk layout in this repo

Top-level beads directory:
```bash
$ ls -la .beads
... config.yaml
... metadata.json
... embeddeddolt/
... dolt/
... hooks/
... backup/
```

Key config:
- `.beads/config.yaml` — project-level defaults; comments indicate integration settings live in DB.
- `.beads/metadata.json` (repo-local metadata file) currently says:
  - `"database": "dolt"`, `"dolt_mode": "embedded"`, `"dolt_database": "fizzy"`.

Git hooks:
- `.beads/hooks/*` are thin shims that call lefthook, then run `bd hooks run <hook> ...` inside a beads-managed marker block.

---

### B3) Two Dolt databases exist (server vs embedded) — *mismatch is real*

`bd context --json` currently reports **server mode**:
```json
{
  "backend": "dolt",
  "dolt_mode": "server",
  "server_host": "127.0.0.1",
  "server_port": 53365,
  "database": "fizzy"
}
```

And `bd dolt status` says a server is running:
```text
Dolt server: running
  PID:  19114
  Port: 53365
  Data: /Users/timmstokke/work/fizzy/.beads/dolt
```

However, the **embedded repo** contains issues while the **server repo** appears empty:

- Server repo: `/Users/timmstokke/work/fizzy/.beads/dolt/fizzy`
```bash
$ dolt sql -q "select count(*) as n from issues"
+---+
| n |
+---+
| 0 |
+---+
```

- Embedded repo: `/Users/timmstokke/work/fizzy/.beads/embeddeddolt/fizzy`
```bash
$ dolt sql -q "select count(*) as n from issues"
+---+
| n |
+---+
| 2 |
+---+
```

Embedded issues (sample):
```text
+-----------+----------------------------+--------+----------+------------+----------------+----------------+---------------------+---------------------+
| id        | title                      | status | priority | issue_type | assignee       | owner          | created_at          | updated_at          |
+-----------+----------------------------+--------+----------+------------+----------------+----------------+---------------------+---------------------+
| fizzy-0zx | Sample comprehensive issue | open   | 1        | task       | timm@stokke.me | timm@stokke.me | 2026-04-17 18:16:54 | 2026-04-17 18:16:54 |
| fizzy-jul | Get started                | open   | 2        | task       | NULL           | timm@stokke.me | 2026-04-17 17:45:30 | 2026-04-17 17:45:30 |
+-----------+----------------------------+--------+----------+------------+----------------+----------------+---------------------+---------------------+
```

Also observed: some `bd` commands intermittently error with an embedded lock message referencing `.beads/embeddeddolt` (suggesting parts of the CLI still try to use embedded mode in this repo, despite `bd context` reporting server mode).

This mismatch is **critical** to resolve early if Fizzy is going to “embed beads natively”:
- we need one canonical DB location/mode, otherwise UI will “see” a different issue universe than CLI.

---

### B4) Beads field schemas (from Dolt schema)

Issues table schema (excerpt) — `dolt schema show issues`:
```sql
CREATE TABLE `issues` (
  `id` varchar(255) NOT NULL,
  `title` varchar(500) NOT NULL,
  `description` text NOT NULL,
  `design` text NOT NULL,
  `acceptance_criteria` text NOT NULL,
  `notes` text NOT NULL,
  `status` varchar(32) NOT NULL DEFAULT 'open',
  `priority` int NOT NULL DEFAULT '2',
  `issue_type` varchar(32) NOT NULL DEFAULT 'task',
  `assignee` varchar(255),
  ...
  `is_template` tinyint(1) DEFAULT '0',
  `mol_type` varchar(32) DEFAULT '',
  `work_type` varchar(32) DEFAULT 'mutex',
  `metadata` json DEFAULT (json_object()),
  ...
  `await_type` varchar(32) DEFAULT '',
  `await_id` varchar(255) DEFAULT '',
  `timeout_ns` bigint DEFAULT '0',
  `waiters` text DEFAULT '',
  `due_at` datetime,
  `defer_until` datetime,
  PRIMARY KEY (`id`)
);
```

Dependencies schema — `dolt schema show dependencies`:
```sql
CREATE TABLE `dependencies` (
  `issue_id` varchar(255) NOT NULL,
  `depends_on_id` varchar(255) NOT NULL,
  `type` varchar(32) NOT NULL DEFAULT 'blocks',
  `metadata` json DEFAULT (json_object()),
  `thread_id` varchar(255) DEFAULT '',
  PRIMARY KEY (`issue_id`,`depends_on_id`),
  CONSTRAINT `fk_dep_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
);
```

Federation peers schema — `dolt schema show federation_peers`:
```sql
CREATE TABLE `federation_peers` (
  `name` varchar(255) NOT NULL,
  `remote_url` varchar(1024) NOT NULL,
  `username` varchar(255),
  `password_encrypted` blob,
  `sovereignty` varchar(8) DEFAULT '',
  `last_sync` datetime,
  PRIMARY KEY (`name`)
);
```

---

### B5) Sample issue dump via export (captured earlier)

One issue line (JSONL) captured from `bd export --no-memories`:
```json
{"id":"fizzy-0zx","title":"Sample comprehensive issue","description":"This is a detailed description to test the data model","design":"Using MVC pattern","acceptance_criteria":"All tests pass","status":"open","priority":1,"issue_type":"task","assignee":"timm@stokke.me","owner":"timm@stokke.me","estimated_minutes":480,"created_at":"2026-04-17T18:16:54Z","created_by":"Timm Stokke","updated_at":"2026-04-17T18:16:54Z","labels":["data-model","test"],"dependency_count":0,"dependent_count":0,"comment_count":0}
```

---

## Initial alignment observations (5–7)

1) **Event log alignment is strong; “dependency graph” alignment is weak.** Fizzy already centralizes all meaningful mutations into `events` (with `action` + JSON `particulars`) and uses that to drive notifications + webhooks (`app/models/event.rb`). Beads also has first-class “events” and versioned snapshots, but its *core differentiator* is dependency types and graph operations (`dependencies` table + `bd dep`). Fizzy has no dependency primitive today; it has workflow columns, closure, and “Not Now” but no “blocks/tracks/validates” edge types.

2) **Fizzy’s “Card state machine” is compositional; Beads’ state is primarily a single `status` plus structured metadata.** Fizzy computes “postponed” and “closed” from presence of `Card::NotNow` / `Closure` rows and tracks related events. Beads uses `issues.status` (`open|in_progress|blocked|deferred|closed`) and then layers additional workflow features via `await_type/await_id` (gates), labels, and metadata JSON. A fork that wants “native beads” inside Fizzy probably should avoid trying to map beads edges onto Fizzy columns; instead treat beads status+edges as primary and render a kanban view as a projection.

3) **Auth boundaries differ materially.** Fizzy is a multi-tenant SaaS with passwordless auth and per-identity access tokens for JSON (`Identity::AccessToken`). Beads is repo-local CLI tooling with integrations, and it assumes access to the repo/Dolt DB. If Fizzy becomes a beads tracker, we’ll need an explicit mapping for “who is allowed to mutate beads issues” that respects Fizzy `Current.account` and `Current.user` roles.

4) **Export/import philosophies are very different but complementary.** Fizzy’s `Account::DataTransfer` exports a deterministic zip of record sets with conflict checks and association integrity validation (good for SaaS migration and huge data). Beads’ Dolt history + JSONL export/import is good for distributed workflows and offline-first, but it doesn’t naturally encode ActionText/ActiveStorage-rich data. If the goal is “beads-native tracking”, we likely keep Beads’ Dolt semantics for issues, and keep Fizzy’s zip exports for tenant data migration separately.

5) **Both systems have “hooks” and automation, but at different layers.** Fizzy webhooks are outbound HTTP triggered by domain events and controlled per-board. Beads hooks are git lifecycle hooks (`.beads/hooks/*` calling `bd hooks run ...`), enabling workflow automation tied to commits/branches. In a merged world, we need to decide whether Fizzy domain actions should emit git hooks analogs (probably not), or whether beads events should become Fizzy events (more likely).

6) **Search implementations won’t transfer cleanly.** Fizzy search is sharded MySQL fulltext over denormalized search records (`search_records_0..15`). Beads search is likely over issue text with query commands, plus external integrations. For a fork, it’s probably cheaper to implement beads issue search using Fizzy’s existing MySQL fulltext patterns *if* beads issues live in the Fizzy DB; if beads issues stay in Dolt, we need a bridging indexer.

7) **Current repo state shows a potentially blocking operational mismatch: dual Dolt DBs.** In this repo, `.beads/dolt/fizzy` (server) and `.beads/embeddeddolt/fizzy` (embedded) both exist; the embedded DB has issues but the server DB is empty. Before designing any fork, we need to make the “source of truth” singular; otherwise we will build UI on top of the wrong store.

---

## “Truth table” summary: what’s real today

- Fizzy has **no versioned public API namespace**. It does have substantial JSON endpoints (Jbuilder) used by Hotwire + native clients, and JSON requests unlock bearer-token auth and a CSRF bypass path (intended for non-browser clients).
- Fizzy has rich multi-tenancy and domain models that already map well to “issue tracker primitives” (cards, comments, tags, assignees, events) but **no dependency DAG primitive**.
- Beads has **first-class dependency modeling** and a lot of workflow primitives (gates, molecules, formulas, swarms), stored in Dolt with schemas visible via `dolt schema show`.
- In this repo’s `.beads`, **two Dolt repos exist** and currently diverge in contents; that’s a concrete grounding fact, not a theory.

