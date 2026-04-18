# S6 — Rich Text + Comments Spec (Beads plaintext SoT; Fizzy ActionText + MySQL mirror)

**Status**: v1 ready for peer review
**Bead**: `fizzy-edq` (epic)
**Drafter**: `fizzy-codex`
**Reviewers**: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/s6-brief.md`

This spec defines how Fizzy’s rich-text surfaces (Card description + Comment body) are driven by the Beads immutable schema:

- Beads is source-of-truth for **issue description** and **comment text** (plaintext).
- Fizzy persists **derived caches** for UI rendering and indexing:
  - `action_text_rich_texts` rows for Card.description + Comment.body (derived HTML).
  - `comments` rows as a MySQL mirror of Beads comments (Beads is canonical).
  - `mentions` rows derived from Beads comment text (for notifications/watch behavior), computed on the mirror/poller side.

This round also decides the deferred S1 question: `comments.id` is widened to `varchar(255)` so Fizzy can use Beads `comments.id` directly.

---

## §A — Card description canonical storage + derived render cache

### A.1 Ground truth: Beads schema is canonical

Beads stores issue description as plaintext:

```
bd sql "DESCRIBE issues"
...
description | text | NO | ... 
```

The fork treats Beads `issues.description` as the only canonical description. Fizzy’s ActionText HTML is a *derived cache* that exists solely to keep the UI and existing rendering code intact.

### A.2 Derived cache: ActionText rich text (HTML) as a view layer

Fizzy Card uses ActionText:
- `app/models/card.rb` — `has_rich_text :description`
- Stored in MySQL table `action_text_rich_texts(record_type="Card", record_id=<card.id>, name="description")`

In the fork:
- `cards.id` is the Beads issue id (varchar) per S1.
- `action_text_rich_texts.record_id` is widened uuid→varchar by S1 bead `fizzy-jzw`.

**Decision**: keep ActionText for rendering, but treat it as derived, rebuildable cache from Beads plaintext.

### A.3 Conversion strategy (plaintext → derived ActionText HTML)

Because Beads description is plaintext, formatting in V1 is intentionally minimal:
- Preserve newlines and paragraphs.
- Escape HTML.
- No attachments/embeds (attachments are S7; Beads has no canonical attachment model).

Implementation bead: add a helper like `Fizzy::Beads::PlaintextToActionTextHtml.call(plaintext)` that produces a safe ActionText-compatible HTML fragment.

### A.4 Update sources (who writes the cache)

There are two ways the cache can be populated:

1) **S9 poller write-through** (canonical): when Beads issue changes, poller updates the Card mirror and ActionText description cache.

2) **Controller immediate projection** (UX improvement): on a successful `bd update --description`, the controller updates the cache immediately (same conversion helper), and the poller later reconciles idempotently.

S6 allows either in I-S6; the invariant is: cache is derived from Beads, never the other way around.

## §B — Comments mirror schema + `comments.id` decision

### B.1 Ground truth: Beads comments schema (append-only)

Beads comments table (immutable schema) is append-only and has no update/delete columns:

```
bd sql "DESCRIBE comments"
Field      | Type         | Null | Key | Default           | Extra
id         | char(36)     | NO   | PRI | (uuid())          | DEFAULT_GENERATED
issue_id   | varchar(255) | NO   | MUL | <nil>             |
author     | varchar(255) | NO   |     | <nil>             |
text       | text         | NO   |     | <nil>             |
created_at | datetime     | NO   | MUL | CURRENT_TIMESTAMP | DEFAULT_GENERATED
```

Empirical CLI surface:
- `bd comments add <issue-id> "text" --author <email> --json` returns the created comment including `id`.

Therefore, Fizzy comment semantics in V1 are:
- **Create**: supported (append comment).
- **Edit/Delete**: not supported (see §C.4 + §E.4).

### B.2 Fizzy MySQL mirror: `comments` + ActionText body cache

Fizzy comment model uses ActionText:
- `app/models/comment.rb` — `has_rich_text :body`
- MySQL `comments` table stores metadata only: `card_id`, `creator_id`, timestamps. Body is stored in `action_text_rich_texts`.

### B.3 `comments.id` decision (deferred from S1): widen-to-varchar and use Beads id

S1 widened `comments.card_id` (beads issue id) via bead `fizzy-0b8`.

**S6 decision** (Gemini prior ratified): widen `comments.id` to `varchar(255)` and store Beads `comments.id` directly.

Why:
- Avoid a mapping table (`beads_comment_id` ↔ `fizzy_comment_uuid`) for every mirror/upsert.
- Makes Search indexing keyed by `searchable_id` straightforward (S1 widens search_records.*.searchable_id already).
- Makes mention/reaction polymorphic association widening consistent with S1 (mentions.source_id, reactions.reactable_id, notifications.source_id are already planned to widen).

### B.4 Related schema dependencies (cross-spec)

This spec assumes the following S1 migrations exist (and wires deps accordingly):
- `fizzy-0b8` — widen `comments.card_id` uuid→varchar(255)
- `fizzy-jzw` — widen `action_text_rich_texts.record_id` uuid→varchar(255)
- `fizzy-33r` — widen `mentions.source_id` uuid→varchar(255)
- `fizzy-hrf` — widen `reactions.reactable_id` uuid→varchar(255)
- `fizzy-2ae` — widen `notifications.source_id` uuid→varchar(255)
- `fizzy-n9l` (or equivalent) — widen all `search_records_* .searchable_id` uuid→varchar(255)

### B.5 Mirror invariants

- Beads is canonical for comment content and created_at.
- MySQL `comments` is a mirror cache. It must be rebuildable from Beads at any time.
- MySQL writes for mirrored comments must be **idempotent** (upsert by comment id).

## §C — CommandClient comment methods + argv (and unsupported operations)

### C.1 CLI argv table (canonical)

Beads supports **adding** comments only:

| Operation | bd argv | Notes |
|---|---|---|
| Add comment (small) | `bd comments add <issue_id> "text" --author <email> --json` | JSON output includes comment id/created_at |
| Add comment (file) | `bd comments add <issue_id> --file <path> --author <email> --json` | preferred (no quoting/escaping pitfalls) |
| Add comment (stdin) | `bd comment <issue_id> --stdin` | shorthand; lacks `--author` flag in help; prefer `bd comments add` |

Global flag placement:
- `--actor <email>` is a global flag and must appear before `comments add` (per S3).

### C.2 CommandClient surface additions (S6)

S3 locks the `CommandClient` core; S6 adds comment/description methods:

- `add_comment(issue_id, plaintext)` → calls `bd --actor <actor> comments add <issue_id> --file <tmp> --author <actor> --json` and returns the parsed JSON (at minimum: comment id + created_at).
- `update_description(issue_id, plaintext)` → calls `bd --actor <actor> update <issue_id> --body-file <tmp>` (or `--description` for short strings).

### C.3 Actor + author semantics

Beads stores two related concepts:
- Global `--actor` for audit trail.
- Comments table `author` field set by `bd comments add --author`.

**Decision**: set both to the same canonical identity string: `Current.identity.email_address` (P5 posture).

This makes comment author mapping in the poller deterministic (email→Identity→User).

### C.4 Unsupported operations: edit/delete comment

Beads exposes no edit/delete comment commands and has no schema support (no updated_at, no deleted flag).

**Decision**: In V1, Fizzy does not support editing or deleting comments.

Controller update/destroy:
- Remove UI affordances (edit/delete controls).
- Keep routes but return 405/403, or remove routes (implementation choice).

CommandClient methods `update_comment(comment_id, ...)` and `delete_comment(comment_id)` should exist only as `NotSupportedError` raisers (so accidental call sites fail loudly).

## §D — Comment poller contract (S9-owned mechanism; S6 specifies WHAT mirrors)

S6 specifies the mirror **contract**. S9 implements the poller mechanics.

### D.1 Mirroring Beads comments into MySQL `comments`

Given a Beads comment:
- `id` (char(36) UUID)
- `issue_id` (Beads issue id)
- `author` (email string)
- `text` (plaintext)
- `created_at` (datetime)

The mirror row in MySQL `comments` must be:
- `comments.id = beads_comment.id` (varchar(255) post-S6 migration)
- `comments.card_id = beads_comment.issue_id` (varchar(255) post-S1 `fizzy-0b8`)
- `comments.creator_id = User mapped from beads_comment.author` (fallback to SystemActor user)
- `comments.created_at = beads_comment.created_at`
- `comments.updated_at = beads_comment.created_at` (Beads has no updated_at)

**Caveat (expected in V1)**: if the author email cannot be mapped to a `User` (e.g., missing identity row), `creator_id` will fall back to the SystemActor user and therefore may “lie” about authorship. The canonical author remains `beads_comment.author`, preserved in Beads and available for admin/debugging.

Write posture: **callback-bypass** (S5 §B.3 / P9 mirror doctrine):
- Use `Comment.upsert_all` keyed by primary id.
- Do not invoke `Comment.create!` in the poller (would trigger Searchable/Mentions/Storage callbacks).

### D.2 Mirroring Beads comment text into ActionText cache

Because `Comment` stores body via ActionText:
- Upsert a row in `action_text_rich_texts`:
  - `record_type="Comment"`
  - `record_id=<comment.id>`
  - `name="body"`
  - `body=<derived_html>` from Beads plaintext `text`

This requires S1 `fizzy-jzw` (record_id widen).

### D.3 Explicit Search sync (poller must do it)

Because the poller writes bypass callbacks, it must explicitly update the FTS mirror:
- Upsert the appropriate `Search::Record` shard row for `searchable_type="Comment", searchable_id=<comment.id>`
- Content comes from the derived cache’s `.to_plain_text` or directly from Beads plaintext (truncate to `Searchable::SEARCH_CONTENT_LIMIT`)

(Exact helper API can follow P9’s sketched `Search::Record.upsert_for_comment`.)

### D.4 Watch + mention derivations (still poller-owned)

Callback-bypass means Comment’s `after_create_commit :watch_card_by_creator` will not fire.

Therefore poller must explicitly apply the side effects:
- Ensure the card is watched by the comment creator (equivalent to `card.watch_by(creator)`).
- Run mention parsing pipeline (§F) and create `mentions` rows (and their watch side effect).

These derivations may use AR (small N), but must be idempotent.

### D.5 Card description cache mirroring

In parallel to comments, poller must keep Card description cache synced:
- When Beads `issues.description` changes:
  - Upsert `action_text_rich_texts(record_type="Card", record_id=<issue_id>, name="description")` with derived HTML.
  - Explicitly upsert Card’s Search::Record content.

## §E — Cards::CommentsController rewire + optimistic UI posture

### E.1 Current upstream behavior

`app/controllers/cards/comments_controller.rb`:
- `#create` does `@card.comments.create!(comment_params)` which writes MySQL + ActionText + callbacks.
- `#update/#destroy` mutate MySQL comment rows.

### E.2 Fork behavior: writes go to Beads first

For `#create`:
1) Convert submitted ActionText body → Beads plaintext (`Fizzy::Beads::ActionTextToPlaintext.call(params[:comment][:body])`).
2) `beads_comment = CommandClient.current.add_comment(card.id, plaintext)`
3) Write derived MySQL cache for immediate UI response (optional but recommended):
   - Create/Upsert the MySQL `comments` mirror row with id = beads_comment.id.
   - Upsert ActionText cache for body from Beads plaintext (not from the user-submitted HTML) so the UI reflects canonical.
4) Render Turbo Stream as today using the derived comment row.

The poller later reconciles idempotently.

### E.3 Update/destroy are disabled

Because Beads comments are append-only:
- Remove edit/delete UI affordances for comments.
- `#update/#destroy` must be disabled (405/403) or removed from routes.

If future V2 adds “edit” semantics, it will be modeled as “append correction comment” (not mutation).

## §F — Mention parsing pipeline (poller-side; supports direct bd writes)

### F.1 Problem statement

Upstream Fizzy mention creation currently depends on ActionText “mention” attachments (see `app/models/concerns/mentions.rb`), not `@username` plaintext.

In the fork, Beads stores plaintext only, so mentions must be derived from plaintext content to support:
- comments created via UI (which become Beads plaintext),
- comments created directly via `bd comments add` (CLI authoritative),
- poller mirroring (callback-bypass).

### F.2 V1 decision: parse plaintext `@` tokens

Mention tokens in plaintext:
- Primary supported form: `@user@example.com` (i.e., a full email address; unambiguous).
- Optional supported form (best-effort): `@handle` where handle matches exactly one `User#mentionable_handles` entry.

### F.3 Implementation shape (I-S6)

Update the `Mentions` concern to include a plaintext parser path:
- Parse `mentionable_content` (already concatenates `.to_plain_text` from ActionText associations).
- Resolve tokens against “mentionable users” for the context:
  - While boards still exist: `board.users`
  - Post-S2 boardless posture: `account.users`
  - Implementation should be resilient: `respond_to?(:board) && board.present? ? board.users : account.users`

Then create mentions via existing `mentioned_by` path (idempotent):
- `mentionee.mentioned_by(mentioner, at: source)` which uses `find_or_create_by!`.

### F.4 Where mention parsing runs

- Controller path: after comment mirror write, schedule `Mention::CreateJob.perform_later(comment, mentioner: comment.creator)` (or call directly).
- Poller path: after upserting comment+actiontext cache, schedule the same job (because callbacks were bypassed).

This guarantees CLI-created comments also generate mention notifications.

## §G — Card description edit flow (UI → Beads plaintext → derived ActionText cache)

`CardsController#update` must stop treating ActionText HTML as canonical.

Fork behavior for description update:
1) Convert ActionText → Beads plaintext (same serializer as comments).
2) Call `CommandClient.current.update_description(card.id, plaintext)` (`bd update --body-file`).
3) Update derived ActionText cache from the same plaintext (for immediate UI).
4) Poller reconciles.

## §H — Test strategy (unit + integration; poller tests deferred to S9)

### H.1 Unit tests (S6-owned)

- `ActionTextToPlaintext` converter:
  - Handles blank.
  - Preserves paragraphs/newlines.
  - Serializes mention attachments (if any) to `@email` tokens (best-effort).
- `PlaintextToActionTextHtml` converter:
  - Escapes HTML.
  - Preserves newlines.
- `CommandClient#add_comment`:
  - Uses `bd --actor ... comments add ... --author ... --file ... --json`
  - Parses returned JSON id.
- `Mentions` plaintext parsing:
  - Creates mention rows for `@email`.
  - Does not create when unknown user or ambiguous handle.

### H.2 Integration tests (S6-owned)

- `Cards::CommentsController#create`:
  - Stubs CommandClient to return comment id + created_at.
  - Asserts a Comment exists with id=beads id and rich_text body derived from Beads plaintext.
  - Asserts update/destroy are disallowed (status code).

### H.3 Poller tests (S9-owned)

S6 specifies contract; S9 tests mirror correctness, search sync, and mention derivations.

## §I — Open questions / deferrals

1) Rich text formatting improvements (markdown, linkification) — V2.
2) Comment edit/delete UX modeled as “correction comment” — V2.
3) Attachment embeds in description/comments — S7.
4) Reactions on mirrored comments — depends on S1 `fizzy-hrf` + comment id migration; implement in I-S? (not here).

## §J — Child bead inventory (maps each AC to an impl bead)

Child beads (I-S6 implementation tasks) are minted under epic `fizzy-edq`.

| F.N | Bead | Title | Satisfies | Key dependencies |
|---|---|---|---|---|
| F.1 | `fizzy-edq.1` | Migrate comments.id uuid→varchar(255) (use Beads comment id) | §B.3 | `fizzy-0b8`, `fizzy-jzw` |
| F.2 | `fizzy-edq.2` | Add CommandClient#add_comment (bd comments add --author --file --json) | §C | `fizzy-5jt`, `fizzy-r4v` |
| F.3 | `fizzy-edq.3` | Add CommandClient#update_description (bd update --body-file) | §C, §G | `fizzy-5jt`, `fizzy-r4v` |
| F.4 | `fizzy-edq.4` | Implement ActionText→Beads plaintext serializer (Card.description + Comment.body) | §E.2, §G | none |
| F.5 | `fizzy-edq.5` | Implement Beads plaintext→ActionText HTML converter (derived cache) | §A.3, §D.2 | none |
| F.6 | `fizzy-edq.6` | Rewire Cards::CommentsController#create to Beads + derived cache; disable update/destroy | §E | `fizzy-edq.1`, `fizzy-edq.2`, `fizzy-edq.4`, `fizzy-edq.5`, `fizzy-3ad` |
| F.7 | `fizzy-edq.7` | Rewire CardsController#update description to Beads + derived ActionText cache | §G | `fizzy-edq.3`, `fizzy-edq.4`, `fizzy-edq.5` |
| F.8 | `fizzy-edq.8` | Mentions: parse plaintext @tokens + create Mention rows (supports CLI comments) | §F | `fizzy-edq.1`, `fizzy-edq.4`, `fizzy-33r` |
| F.9 | `fizzy-edq.9` | Integration tests: CommentsController#create (Beads write + derived cache) | §H.2 | `fizzy-edq.6` |
| F.10 | `fizzy-edq.10` | Unit tests: converters + CommandClient comment/description methods | §H.1 | `fizzy-edq.2`, `fizzy-edq.3`, `fizzy-edq.4`, `fizzy-edq.5` |
| F.11 | `fizzy-edq.11` | S9 poller: mirror Beads comments→MySQL comments + ActionText + search + mention/watch | §D | `fizzy-edq.1`, `fizzy-edq.5`, `fizzy-edq.8`, `fizzy-n9l` |

## §K — Validation checklist

- [x] §A states Beads plaintext is SoT; ActionText is derived cache
- [x] §B includes concrete comments.id widening decision (deferred from S1)
- [x] §C grounded in real `bd comments add` CLI surface (+ `--author` + `--json`)
- [x] §D follows S5 mirror precedent: callback-bypass upsert_all + explicit search sync
- [x] §E disables update/destroy as Beads is append-only
- [x] §F mention parsing is poller-capable and captures CLI writes
- [x] §J child beads minted and dependency graph wired (fizzy-edq.1..11)
- [ ] `[CODEX→CLAUDE S6 v1 ready]` sent + peer review complete
- [ ] `[FROM→TO S6: agreed]` 3-of-3 lock
