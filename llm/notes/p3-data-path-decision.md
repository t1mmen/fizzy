# P3 — Data-Path Decision: Fizzy ↔ Beads/Dolt

**Status**: drafting (P3 round in flight)
**Bead**: `fizzy-lbz`
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
**Brief**: see `llm/notes/p3-brief.md`

This decision doc closes Q-S-001 (read), Q-S-001a (write), and Q-S-002a (FK migration). All later rounds (P4–P10, S1–S10) build on this.

---

## §A — Decision

**Hybrid: read via Dolt SQL through Rails ActiveRecord (Trilogy adapter, separate `:beads` connection in Rails 8 multi-DB config); write via shelled-out `bd` CLI.**

In one sentence: **SQL for reads, CLI for writes** — the BeadBoard / Beadbox community pattern, validated empirically by both P2 proofs.

**Why this and not "all CLI" or "all SQL":**

- **All CLI** is too slow for read-heavy UI and forces JSON-output-parsing for every list (bd CLI calls are order-of-magnitude slower than direct SQL per the `community-bead-uis-research.md` storage-table column "Latency"; an actual local benchmark is one of the §H validation items). Acceptable for terminal UIs (Mardi Gras 5s polls); not acceptable for a Hotwire-driven kanban.
- **All SQL** writes bypass Beads' commit hooks, event log, and `interactions` audit trail. Mutation through `bd` ensures the audit story stays intact and any future bd integration (Linear / Jira sync, federation) keeps working. Per `dolt-rails-adapter-research.md`, Dolt also has per-connection branch state which makes naïve concurrent SQL writes risky; routing all writes through a serialized CLI shell-out avoids this.
- **Hybrid** absorbs the best of both at the cost of one boundary in code (the adapter layer in §D).

This decision is opinionated but reversible: if the Spec phase surfaces a UI pattern that strictly requires SQL writes (e.g. real-time bulk-update kanban drag-drop with sub-100ms feedback), we re-open the question with concrete evidence.

---

## §B — Evidence cited (no new empirical claims here)

### B.1 Both paths verified working in P2

From `llm/notes/p2-local-dev-grounding.md` §6:

- **CLI path** (§6.1, `bin/p2-rails-bd-probe.rb`): Rails-runner shells out to `bd context --json` + `bd export --no-memories`, parses the result, returns 4 issues with full title/id. Verbatim output captured in §6.1 of P2 doc.
- **SQL path** (§6.2, `bin/p2-rails-dolt-probe.rb`): ActiveRecord with `adapter: trilogy`, `host: 127.0.0.1`, `port: <from .beads/dolt-server.port>`, `database: fizzy`, `pool: 1`. Returns `issues.count=4` and a sample of 5 most-recently-updated rows. Verbatim output in §6.2.

### B.2 Adapter compatibility (no custom adapter needed)

From `llm/notes/dolt-rails-adapter-research.md` (committed `71e1d1819`):

- Dolt implements MySQL HandshakeV10 protocol, tested with Ruby clients. (TLDR section.)
- `dolthub/dolt_rails` sample app exists (Rails 7.1.3 + mysql2). (Target #2.)
- Trilogy and mysql2 both work; Trilogy is preferred for Rails 8+. (Target #3.)
- Schema introspection ~90% works. Some `information_schema` gaps (view columns, cardinality) but not blocking for our schema. (Target #6.)

### B.3 The pooling caveat

From `dolt-rails-adapter-research.md` Critical Constraint section:

- Dolt's per-connection branch state (`@@mydb_head_ref` session variable) breaks naïve Rails connection pooling. Pooled connections "remember" their branch — the wrong branch can read/write under concurrent requests if branches are in use.
- **In V1 we use a single branch** (`master`), so the bug-class is dormant. We pin connections in the adapter (§D) so any future branch use doesn't surprise us.

### B.4 Pattern proven by community

From `llm/notes/community-bead-uis-research.md` Synthesis:

- **Hybrid SQL-read + CLI-write** is the dominant pattern across BeadBoard (web), Beadbox (Tauri), and Beads UI (web). All three production-grade implementations chose this split for the same trade-off reasons we're documenting here.
- File-watching + SSE for invalidation is the long-term recommendation, but **not required for V1** (we can poll or rely on Hotwire's standard refresh patterns). Listed as Q-S-NEW in §G.

---

## §C — Trade-off analysis (8 axes)

| Axis | All CLI | All SQL | **Hybrid (chosen)** |
|---|---|---|---|
| **1. Read latency** | order-of-magnitude slower (process fork + JSON parse per call) | order-of-magnitude faster (connection-pooled SQL) | **SQL-class read latency**; writes pay the CLI fork cost but are rarer. Concrete numbers via local bench (§H). |
| **2. Write-side hooks** | Full (bd events, audit, interactions log) | None — must hand-craft event emission | **Full** (writes go through CLI) |
| **3. Error handling / retries** | Standard process exit-code + stderr; easy to wrap | AR exception handling; richer error types | Per-side: SQL errors via AR; CLI errors via Open3-wrapper |
| **4. Transactionality** | None across multiple bd invocations (each is its own commit) | Full via AR transaction blocks | **Reads transactional via AR**; writes are serialized one-bd-call-at-a-time. For multi-write atomicity, the canonical option is `bd batch` (see `bd --help`; supports grouped mutations as one Dolt commit). Falling back to raw SQL writes is **explicitly out of scope** here — that would re-open the no-SQL-writes posture and require a fresh decision (Q-S-NEW if we ever consider it). |
| **5. Read-after-write consistency** | Strong: bd writes commit, next bd read sees it | Strong: same connection sees its own writes | **Expected strong** — bd write commits to Dolt; subsequent SQL read on a fresh connection should see the new state. Caveat: if same-request reads-then-writes-then-reads happens, the in-flight SQL connection may not have observed the bd commit yet (Q-S-034 in §G). Validation: micro-test in §H.1 *should* confirm; if it fails empirically, that escalates Q-S-034 from "test in P3" to a spec/impl problem (per-write SQL refresh hook or equivalent), but does not invalidate the P3 lock. |
| **6. Concurrent-writer safety** | Bd CLI itself is the serialization point | Risky: per-connection branch state + SQL transaction merge semantics | **Safe**: writes serialized via CLI; reads are concurrent-safe per Dolt's MVCC |
| **7. Operational cost** | High: one process fork per query (read + write) | Lowest: connection pool, no forks | Mixed: pool-managed reads (no fork), shell-out per write (fork cost) |
| **8. Failure mode** | If `bd` binary missing: total failure | If Dolt server down: total failure | Partial degradation possible — reads fail if Dolt down, writes fail if `bd` binary missing or Dolt down. Health check both at boot. |

**Score**: Hybrid wins 5 of 8 axes outright; Hybrid is "second-best, acceptable" on the remaining 3 (transactionality, operational cost, failure mode complexity). All-CLI wins one (read-after-write strictly within a single shell invocation). All-SQL wins one (operational cost).

The 5 wins outweigh the 3 trade-offs given V1's UX targets (Hotwire kanban with sub-200ms read latency).

---

## §D — Adapter shape sketch (Ruby module/class layout, signatures only)

The adapter lives in `app/models/beads/` (new namespace) and `lib/fizzy/beads/` (new namespace for command-client + non-AR code). No code in this round; this sketch informs S* rounds.

```ruby
# config/database.yml additions (simplified — full config via env-driven Rails 8 pattern)
development:
  primary:
    adapter: sqlite3
    database: storage/development.sqlite3
  beads:
    adapter: trilogy
    host: 127.0.0.1
    port: <%= File.read(Rails.root.join(".beads", "dolt-server.port")).strip rescue 3306 %>
    username: root
    database: fizzy
    pool: 5
    # Note: branch pinning handled in BeadsRecord (see §D.4)

# app/models/beads_record.rb (SQL READ base — never write through this)
class BeadsRecord < ActiveRecord::Base
  self.abstract_class = true
  # Single :beads connection in Rails 8 multi-DB config. Although we declare
  # both reading and writing roles below for AR's pool plumbing, every
  # subclass MUST be readonly (see Beads::Issue#readonly?). All mutations
  # route through Fizzy::Beads::CommandClient — never through AR.
  connects_to database: { writing: :beads, reading: :beads }

  # Branch pinning (defensive — V1 uses master only)
  def self.connection
    super.tap do |conn|
      # NO-OP today; future: ensure connection is on the right branch
      # via DOLT_CHECKOUT() if branches are introduced (Q-S-033).
    end
  end
end

# app/models/beads/issue.rb (one model per beads table we read)
module Beads
  class Issue < BeadsRecord
    self.table_name = "issues"
    self.primary_key = "id"

    has_many :dependencies_out, class_name: "Beads::Dependency", foreign_key: "issue_id"
    has_many :dependencies_in,  class_name: "Beads::Dependency", foreign_key: "depends_on_id"
    has_many :comments,         class_name: "Beads::Comment",    foreign_key: "issue_id"
    has_many :labels,           class_name: "Beads::Label",      foreign_key: "issue_id"

    # Read-only by convention:
    def readonly?; true; end
  end

  class Dependency < BeadsRecord
    self.table_name = "dependencies"
    self.primary_keys = [:issue_id, :depends_on_id]   # composite PK
    belongs_to :issue,         class_name: "Beads::Issue", foreign_key: "issue_id"
    belongs_to :depends_on,    class_name: "Beads::Issue", foreign_key: "depends_on_id"
    def readonly?; true; end
  end

  class Comment < BeadsRecord
    self.table_name = "comments"
    belongs_to :issue, class_name: "Beads::Issue"
    def readonly?; true; end
  end

  class Label < BeadsRecord
    self.table_name = "labels"
    belongs_to :issue, class_name: "Beads::Issue"
    def readonly?; true; end
  end

  # Add models for issue_snapshots, events, etc. as Spec rounds need them.
end

# lib/fizzy/beads/command_client.rb (CLI write boundary)
module Fizzy
  module Beads
    class CommandClient
      def initialize(actor:, env: ENV.to_h, bd_bin: "bd")
        @actor  = actor       # the Identity email or "fizzy-system"
        @env    = env.merge("BD_ACTOR" => actor)
        @bd_bin = bd_bin
      end

      # Reads — we still expose CLI reads for cases where SQL is wrong tool
      # (e.g., bd ready, bd query DSL, bd memories).
      def context;        invoke!(["context", "--json"]).then { |o| JSON.parse(o) }; end
      def memories(query); invoke!(["memories", query]); end

      # Writes — every mutation goes through here.
      def create_issue(attrs);                  invoke!(build_create_args(attrs)); end
      def update_issue(id, attrs);              invoke!(build_update_args(id, attrs)); end
      def close_issue(id, reason: nil);         invoke!(build_close_args(id, reason)); end
      def reopen_issue(id);                     invoke!(["reopen", id]); end
      def add_dependency(issue, depends_on, type:); invoke!(["dep", "add", issue, depends_on, "--type", type]); end
      def add_label(id, label);                 invoke!(["update", id, "--add-label", label]); end
      def add_comment(id, text);                invoke!(["comment", id, text]); end

      private

      def invoke!(argv)
        stdout, stderr, status = Open3.capture3(@env, @bd_bin, *argv)
        raise CommandError.new(argv, status, stderr) unless status.success?
        stdout
      end

      def build_create_args(attrs); ...; end
      def build_update_args(id, attrs); ...; end
      def build_close_args(id, reason); ...; end
    end

    class CommandError < StandardError
      def initialize(argv, status, stderr)
        super("bd #{argv.join(' ')} failed (#{status.exitstatus}): #{stderr}")
      end
    end
  end
end

# app/models/beads/issue_repository.rb (orchestration boundary used by controllers)
module Beads
  class IssueRepository
    def self.list(scope: :all, filter: nil, limit: 50);     # Beads::Issue.where(...).limit(...)
    end
    def self.find(id);                                       # Beads::Issue.find(id)
    end
    def self.create(attrs, actor:);                          # CommandClient(actor:).create_issue(attrs)
    end
    def self.update(id, attrs, actor:);                      # CommandClient(actor:).update_issue(id, attrs)
    end
    def self.close(id, reason: nil, actor:);                 # CommandClient(actor:).close_issue(id, reason: reason)
    end
    # … plus add_dep / add_label / comment, etc.
  end
end
```

**Key boundaries:**

- `Beads::*` ActiveRecord models = read-only views over Dolt. `readonly?` enforced at model level.
- `Fizzy::Beads::CommandClient` = the only place that calls `bd`. Tested with stub-able `bd_bin:`.
- `Beads::IssueRepository` = controller-facing orchestration. Controllers see only this; never touch raw AR or CommandClient directly.
- Auth: `BD_ACTOR` flows from controller → IssueRepository → CommandClient via the `actor:` keyword. P5 (auth-bridging) finalizes how `actor` is resolved per request.

**What's deliberately NOT in this sketch:**

- Caching (S* rounds may add a Solid Cache layer over reads).
- Background syncing (file-watcher + SSE for live UI updates — Q-S-NEW in §G).
- Branch switching (V1 master-only).
- Bulk operations (S* may add `bd batch`-style support).

---

## §E — Migration implications (Q-S-002a)

**Goal**: every Fizzy table that currently has `card_id uuid` will eventually need `card_id varchar(255)` (Beads issue id format `fizzy-<suffix>`). This is the FK type change Q-S-002a flagged.

**Fizzy tables affected** (from `db/schema.rb` enumeration in P1 §A — non-exhaustive, S* round will produce the complete list):

| Table | Current FK column | Target |
|---|---|---|
| `closures` | `card_id uuid` | `card_id varchar(255)` |
| `card_not_nows` | `card_id uuid` | `card_id varchar(255)` |
| `card_goldnesses` | `card_id uuid` | `card_id varchar(255)` |
| `card_activity_spikes` | `card_id uuid` | `card_id varchar(255)` |
| `assignments` | `card_id uuid` | `card_id varchar(255)` |
| `taggings` | `card_id uuid` | `card_id varchar(255)` |
| `comments` | `card_id uuid` | `card_id varchar(255)` |
| `steps` | `card_id uuid` | `card_id varchar(255)` |
| `reactions` | `reactable_id uuid` (polymorphic) | mixed string/uuid — needs decision |
| `mentions` | `source_id uuid` (polymorphic) | mixed string/uuid — needs decision |
| `pins` | `card_id uuid` | `card_id varchar(255)` |
| `watches` | `card_id uuid` | `card_id varchar(255)` |
| `notifications` | `card_id uuid` | `card_id varchar(255)` |
| `events` | `eventable_id uuid` (polymorphic) | mixed string/uuid — needs decision |
| `action_text_rich_texts` | `record_id uuid` (polymorphic) | mixed string/uuid — needs decision |
| `active_storage_attachments` | `record_id uuid` (polymorphic) | mixed string/uuid — needs decision |

**Polymorphic columns** are the hard case: a single `record_id` column today carries UUIDs for all referenced types. To accommodate Beads string ids, we either:

- **(M-a) Widen to `varchar(255)` for all** — works because UUIDs fit in 36 chars. Cleanest schema. Beads ids (`fizzy-<suffix>`) are also <36 chars.
- **(M-b) Add parallel `_beads_id` columns** — dual-write during cutover, then remove old UUID columns. Less risky for staged rollout but more code.
- **(M-c) Restrict polymorphic types** — bar Card from polymorphic targets and add a dedicated `card_id` (varchar) instead. Reduces scope of change but adds bespoke logic.

**Recommendation**: (M-a) widen to `varchar(255)` everywhere. The Spec round (S-card-fk-migration) produces the actual migration sequence. V1 cuts over big-bang because dual-write adds operational complexity for a single-tenant install with no production traffic.

### E.1 Existing-data handling (correction — there is no UUID→Beads-id mapping)

**Beads issue ids are NOT derivable from Fizzy UUIDs.** `fizzy-<suffix>` is generated independently by `bd` from the `issue_counter` table; it has no relationship to upstream Fizzy `cards.id` UUIDs.

For V1 (hard fork, single-tenant, no production traffic yet — per CEO Q3 ii + Q5a), we treat existing upstream Fizzy data as **disposable**. A fresh install starts with an empty `cards`/`comments`/etc. and an empty Beads DB; the user creates new issues via the new UI. **No UUID-to-beads-id backfill required because there's nothing to backfill.**

If a user wants to migrate from upstream Fizzy → fork, that is a separate import path (Q-S-007, deferred to v2+). Three candidate strategies for that future import:

- **(I-a) Disposable**: import only documents the upstream data was abandoned. Simplest.
- **(I-b) Mapping table**: a one-time `card_id_map (old_uuid, beads_id)` table records the mapping; importer creates a fresh Beads issue per upstream Card and writes the row. Sidecar tables (closures/assignments/etc.) are then rewritten via the map.
- **(I-c) Drop sidecar tables for migrated data**: importer rewrites Card data into Beads issues but doesn't preserve sidecar artifacts (closures-by-user, assignment audit). Loses some history.

V2 picks one when import is needed. V1 ignores.

**One-time schema migration script** (Spec round S-card-fk-migration owns the actual SQL):

```sql
-- Sketch only; S* round produces real migration
ALTER TABLE closures        MODIFY COLUMN card_id      varchar(255) NOT NULL;
ALTER TABLE assignments     MODIFY COLUMN card_id      varchar(255) NOT NULL;
-- ... per table ...

-- For polymorphic record_id columns:
ALTER TABLE events                    MODIFY COLUMN eventable_id varchar(255) NOT NULL;
ALTER TABLE action_text_rich_texts    MODIFY COLUMN record_id     varchar(255) NOT NULL;
ALTER TABLE active_storage_attachments MODIFY COLUMN record_id    varchar(255) NOT NULL;

-- No backfill: V1 fresh installs only. Existing data is disposable per E.1.
```

---

## §F — Resolved Q-S items

The following Q-S items in `llm/notes/p1-foundational-gap-inventory.md` §E are now ANSWERED by this doc:

- **Q-S-001 — How does Fizzy read Beads issues at runtime?** → ANSWERED. Read via Dolt SQL (Trilogy adapter, Rails 8 multi-DB `:beads` connection, `Beads::*` AR models with `readonly?`). See §A, §C, §D.
- **Q-S-001a — How does Fizzy *write* to Beads?** → ANSWERED. All writes via shelled-out `bd` CLI through `Fizzy::Beads::CommandClient`. Preserves bd events / audit / hooks. See §A, §C, §D.
- **Q-S-002a — Schema migration cost: changing UUID FKs to string?** → ANSWERED with caveat. Recommendation (M-a) widen to `varchar(255)` for all card-referencing FKs. Polymorphic columns get the same treatment. Spec round S-card-fk-migration owns the per-table migration sequence + execution. See §E.

A separate edit will be made to `llm/notes/p1-foundational-gap-inventory.md` §E to mark these ANSWERED with a backlink to this doc.

---

## §G — Open questions for downstream rounds

New questions surfaced during P3 drafting (numbered continuing from Q-S-032 + Q-S-006a):

> **Q-S-033 — How does the SQL connection pool handle Dolt branch state when V2 introduces branches?**
> All Beads::* AR queries. Today V1 uses master only; V2 might use branches per environment / per tenant if multi-tenancy ever returns. The mitigation pattern (separate pool per branch, per `dolt-rails-adapter-research.md`) needs a concrete plan when branches enter.
> Defer to v2.

> **Q-S-034 — Does the read-after-write same-request case need a SQL refresh hint?**
> Edge case: controller writes via CommandClient, then reads via Beads::IssueRepository.find within the same request. The SQL connection in the pool may not have observed the bd write yet (Dolt commit propagation lag). Test in P3 validation; if real, add a per-write "refresh" hook.

> **Q-S-035 — Should we add a file watcher (`.beads/last-touched`) + SSE for live UI updates?**
> Per `community-bead-uis-research.md`, this is the standard pattern in BeadBoard / Beads UI / Beadbox. V1 may live with Hotwire's polling/refresh; V2 absorbs.

> **Q-S-036 — How does `bd` CLI shell-out cost scale under load?**
> One process fork per write may be fine for single-user but punishes burst writes. Benchmark under realistic load during Implementation. If unacceptable, options: (a) batch writes via `bd batch` (if/when bd supports), (b) long-lived `bd` daemon process (would require bd changes), (c) limited carve-out for SQL writes with handcrafted event emission (last resort).

> **Q-S-037 — Do we need Beads schema versioning checks in the adapter?**
> If a future bd release changes a column we read, our `Beads::*` models break silently. Add a boot-time schema check that compares expected vs actual `dolt schema show <table>` output, log warning on mismatch.

---

## §H — Validation checklist (pre-lock)

Before sending `[CLAUDE→CODEX P3: agreed]`, all peers should be able to confirm:

- [ ] §A decision text is unambiguous and readable in 30 seconds.
- [ ] §B cites only artifacts that are currently in the repo (`p2-local-dev-grounding.md`, `dolt-rails-adapter-research.md`, `community-bead-uis-research.md`).
- [ ] §C trade-off table lists 8 axes with all three columns populated.
- [ ] §D adapter sketch is signature-only (no implementation), references S* rounds for actual code.
- [ ] §E identifies every Fizzy table that needs FK type change. Polymorphic case is explicit.
- [ ] §E.1 correctly states there is NO UUID→Beads-id backfill (Beads ids are independently generated).
- [ ] §F marks Q-S-001/001a/002a ANSWERED.
- [ ] §G surfaces 5+ new open questions with clear ownership.
- [ ] No "we'll figure it out later" language.

### H.1 Empirical validation TODO (optional — strengthens decision)

Codex suggested + Claude agrees: write a micro-test (extension of P2's probe scripts) that, in one Rails process / one request: (1) shells out to `bd` to create or update an issue, (2) immediately reads the same issue via `Beads::Issue.find` through the SQL connection. If the SQL read sees the bd write within the same request: §C Axis 5 is empirically "Strong" (matches our claim). If it doesn't: we have to add a per-write SQL refresh hook (Q-S-034 elevates from "test in P3" to "must solve in spec phase").

This validation is non-blocking for P3 lock (the decision stands either way; only the workaround changes). But it informs S-card-fk-migration and S-adapter-implementation. Implementation-round work; can run during P4-P10 in parallel.

---

## Convergence signal (P3)

When all three agents agree P3 is complete, each sends:

`[FROM→TO P3: agreed]`

After all signals are in `llm/LOG.md`, this file is locked, the bead `fizzy-lbz` is closed, and we open P4 (UI projection deep-dive) with a handoff entry.
