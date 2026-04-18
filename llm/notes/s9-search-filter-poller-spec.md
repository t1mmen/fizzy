# S9 — Search + Filter + Poller Spec (the Beads→Fizzy mirror engine)

**Status**: v1 ready for peer review
**Bead**: `fizzy-pmi` (epic)
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/s9-brief.md`

This spec defines the **single poller engine** that ingests Beads canonical state and writes the Fizzy MySQL mirror tables, plus the filter compilation and search execution layers that read from that mirror. S9 closes 4 placeholders on lock: `fizzy-1iz` (S4), `fizzy-eq4.12` (S2 single-board drift), `fizzy-edq.11` (S6 comments), `fizzy-n3l.6` (S8 events).

Architectural one-liner: **One poller, one cursor per source, callback-bypass writes, eventually-consistent UI, no cross-DB joins anywhere.**

---

## §A — Poller architecture

### A.1 Engine shape

A single `BeadsPoller` recurring job runs every **30 seconds** (P9 §C.4 freshness target). Implemented as a Solid Queue recurring job (per `config/recurring.yml`).

```ruby
class BeadsPoller < ApplicationJob
  def perform
    Current.with(account: Account.singleton, actor: SystemActor.email) do
      Current.beads_mirror = true   # S8 §B.4 mirror-mode guard
      Beads::Mirror::Cursor.advance_all
    end
  end
end
```

Single engine = single source of ordering. NO parallel mirror workers in V1 (avoids cursor races; revisit in V2 if 30s budget tightens).

### A.2 Per-source cursors

**IMPORTANT — Beads UUID semantics**: Beads `events.id` and `comments.id` are MySQL `uuid()` (v1 timestamp-MAC, not v7) — NOT monotonic across rows. Therefore the cursor MUST be timestamp-based, NOT id-based. (Per Gemini S9 prior #1.)

The poller maintains independent cursors for each Beads canonical source. Stored in a small new MySQL table `beads_mirror_cursors(source varchar pk, last_seen_at datetime(6), last_advanced_at datetime, processed_ids text)`:

- `last_seen_at` = `created_at` of the highest-watermark Beads row processed.
- `processed_ids` = JSON array of Beads ids processed within the **overlap window** `(last_seen_at - overlap_seconds, last_seen_at]`. Used to dedupe rows that share the cursor's timestamp on next tick.
- `overlap_seconds` = `2` (seconds) — covers MySQL `datetime(6)` precision + microsecond clock skew between Beads and Fizzy connections.

| Source | Source query |
|---|---|
| `events` | `SELECT * FROM events WHERE created_at >= :cursor_at - INTERVAL :overlap SECOND ORDER BY created_at, id LIMIT :batch` (Beads SQL via `:beads` connection); skip rows whose id is in `processed_ids` |
| `comments` | `SELECT * FROM comments WHERE created_at >= :cursor_at - INTERVAL :overlap SECOND ORDER BY created_at, id LIMIT :batch`; skip rows whose id is in `processed_ids` |
| `issues_snapshot` | `last_advanced_at` = wall-clock; full periodic resync of all open issues (anti-drift; §D) |

After a tick processes a batch:
1. Find max `created_at` in the batch → new `last_seen_at`.
2. Collect ids of rows with `created_at == new last_seen_at` → new `processed_ids` (replaces the prior tick's set wholesale; older ids are no longer in the overlap window's intersection with the new cursor).
3. Commit the cursor row.

Cursor advance happens **only after every per-row mirror procedure commits its MySQL transaction in the batch**. A poller crash mid-tick replays the entire batch on next tick — per-procedure idempotency (B.1 + S8 §B.2 dedup unique index + the `processed_ids` overlap-dedupe) keeps this safe.

**Why this works**: even if two Beads rows have identical `created_at` and were created in different order than `id` would suggest, the overlap window guarantees we re-scan that timestamp band on next tick; the `processed_ids` set prevents reprocessing what we already did; the unique indexes catch any leakage.

### A.3 Batch size + backpressure

`batch = 200` per source per tick (configurable). If a tick processes a full batch in less than 5 seconds, the next tick fires immediately (backlog burndown). Otherwise normal 30s cadence.

### A.4 Scope of procedures invoked per row

Each Beads row passes through ONE dispatch table that determines which mirror procedures fire:

| Beads source | Procedures (in order) | Owner |
|---|---|---|
| `events` row | (a) issue snapshot refresh for `issue_id` (cards mirror), (b) tag/tagging delta for label_added/removed, (c) Event row mirror (S8 §A mapping) | §C.1 + §C.3 + §C.5 |
| `comments` row | (a) comments mirror upsert + ActionText cache (S6 §D), (b) mention parser (S6 §F), (c) `comment_created` Event row (S8 §A.4 last row), (d) watch derivation | §C.4 + §C.5 |
| Periodic resync | full diff of issues+labels+comments since last full sweep | §D.1 |

All procedures are **callback-bypass** (`upsert_all` / `update_columns` / direct SQL) per P9 §A.2 + S5 §B.3 + S6 §D.2.

## §B — Mirror write contract (callback-bypass + explicit side effects)

### B.1 Idempotency

Every mirror procedure is idempotent on the same Beads row:
- `cards`: `upsert_all([{id: issue.id, beads_status: ..., closed_at: ..., defer_until: ...}], unique_by: :id)`
- `tags`/`taggings`: per S5 §B.3 `upsert_all` keyed by unique constraints
- `comments`: `upsert_all` keyed by `id` (Beads comment id, post-S6 widening)
- `events`: `Event.create!` (NOT `upsert_all` — we MUST preserve `after_create_commit` callbacks for Notifiable + WebhookDispatchJob per §B.2 #4-5). Idempotency comes from the unique index on `events.beads_event_id` (S8 §B.2): on `ActiveRecord::RecordNotUnique`, treat as success (the row was already mirrored on a prior tick).

A poller restart that replays already-processed rows produces zero new mirror rows + zero new side effects: cards/tags/taggings/comments paths are `upsert_all` (idempotent at SQL layer); events path catches `RecordNotUnique` (idempotent at AR layer while preserving callbacks).

### B.2 Explicit side effects (replacing bypassed callbacks)

Because `upsert_all` bypasses AR callbacks, the poller MUST explicitly invoke side effects that callbacks would normally trigger:

1. **Search::Record sync** — after every `cards`/`comments` upsert: `Search::Record.upsert!(attrs)` per shard (account-id-routed).
2. **Watch derivation** — when mirroring a `comment_created` Event: ensure card is watched by the comment creator (equivalent to `card.watch_by(creator)` but via direct SQL).
3. **Mention derivation** — per S6 §F.4 `Mention::CreateJob.perform_later(comment, mentioner: comment.creator)` after comment + Event are committed.
4. **Notification fanout** — Event creation via `Event.create!` does fire `Notifiable.after_create_commit` (this we WANT — see §C.5 + S8 §F.1). The mirror-mode guard (S8 §B.4) is scoped to `Card#touch_last_active_at` only.
5. **Outbound webhook dispatch** — same as #4: `Event::WebhookDispatchJob` is `after_create_commit` and we WANT it to fire (S8 §D.2).

Ordering matters: comments mirror MUST commit BEFORE the `comment_created` Event row (so the Event's `eventable_id` resolves to the just-committed Comment row).

### B.3 Transaction boundary per Beads row

Each Beads row's procedure list runs in a single MySQL transaction. Side-effect job enqueues happen inside that transaction (Solid Queue jobs are MySQL-backed; the enqueue commits with the transaction). Cursor advance happens AFTER the transaction commits.

If the transaction rolls back (DB error, validation failure on Event.create!): cursor does NOT advance; next tick replays. The unique-index constraints (events.beads_event_id, comments.id, tags(account_id, title)) ensure replay is idempotent.

## §C — Per-source mirror procedures

### C.1 Issue snapshot → cards mirror

Triggered: by an `events` row OR by periodic resync (§D).

```ruby
def mirror_issue(issue_id)
  beads_issue = Beads::Issue.find(issue_id)  # SELECT * FROM issues WHERE id = ? via :beads
  Card.upsert_all([{
    id: beads_issue.id,
    beads_status: beads_issue.status,
    closed_at: beads_issue.closed_at,
    defer_until: beads_issue.defer_until,
    close_reason: beads_issue.close_reason,
    title: beads_issue.title,
    updated_at: Time.current
  }], unique_by: :id)
  Search::Record.upsert!(card_attrs(beads_issue))
end
```

Closes S4 §C.3 + S4 placeholder `fizzy-1iz`.

### C.2 Custom statuses → mirror table (S2 dependency)

S2 §B.2 requires custom_statuses categorization (done/frozen/unspecified) for column routing. New mirror table:

```sql
CREATE TABLE beads_custom_statuses (
  name varchar(64) PRIMARY KEY,
  category varchar(32) NOT NULL,  -- 'done', 'frozen', 'unspecified', etc.
  updated_at datetime NOT NULL
);
```

Refreshed by periodic resync (§D.1): `SELECT name, category FROM custom_statuses` from Beads, `upsert_all` to MySQL. Low frequency (custom statuses don't change often).

### C.3 Label delta → tags + taggings mirror

Triggered: by `events` row with `event_type IN ('label_added', 'label_removed')` (S8 detects the type from the event payload).

Per S5 §B.3:
- For added: `Tag.upsert_all([{account_id:, title: normalized}], unique_by: [:account_id, :title])` then `Tagging.upsert_all([{card_id:, tag_id:}], unique_by: [:card_id, :tag_id])`.
- For removed: `Tagging.where(card_id:, tag_id:).delete_all`.
- Skip labels failing `LabelNormalizer.call` (per S5 §E.4 CLI-only stance).

### C.4 Comment row → comments + ActionText + mention pipeline

Per S6 §D:
1. `Comment.upsert_all([{id: bc.id, card_id: bc.issue_id, creator_id: ActorMapper.call(bc.author), created_at: bc.created_at, updated_at: bc.created_at}], unique_by: :id)`
2. `ActionText::RichText.upsert_all([{record_type: "Comment", record_id: bc.id, name: "body", body: PlaintextToActionTextHtml.call(bc.text)}], unique_by: [:record_type, :record_id, :name])`
3. `Search::Record.upsert!(comment_attrs(bc))`
4. Watch derivation: ensure comment.card.watched_by(comment.creator) — direct INSERT IGNORE on `watches`.
5. `Mention::CreateJob.perform_later(comment_id: bc.id, mentioner: comment.creator)` (per S6 §F.4)

Closes S6 placeholder `fizzy-edq.11`.

### C.5 Event mirror (per S8 §A mapping table)

After C.1-C.4 complete for the row, mirror the canonical Event:

```ruby
mapped = Beads::EventMapper.call(beads_event, prior_snapshot: snapshot_before)
return if mapped.nil?  # unmapped event types are skipped per S8 §A

Event.create!(
  action: mapped[:action],
  eventable_type: mapped[:eventable_type],
  eventable_id: mapped[:eventable_id],
  board_id: resolve_board_at_time(card_id, beads_event.created_at),  # S8 §C.2
  creator_id: ActorMapper.call(beads_event.actor),  # S8 §B.3
  created_at: beads_event.created_at,
  particulars: mapped[:particulars],
  beads_event_id: mapped[:beads_event_id]  # S8 §A.3 unique key
)
# Notifiable + WebhookDispatchJob fire via after_create_commit (we want)
# touch_last_active_at is silent because Current.beads_mirror? = true (S8 §B.4)
```

Closes S8 placeholder `fizzy-n3l.6`.

**Side-effect note**: `Event.after_create -> { eventable.event_was_created(self) }` will still fire for poller-created Events (S8 §B.4 mirror-mode guard is scoped to `Card#touch_last_active_at` only, not to other downstream `event_was_created` work). This includes Card system commenter creation (Fizzy-only artifacts derived from Beads history). This is INTENTIONAL — the system commenter rows ARE the visible activity feed entries that users expect to see for Beads-originated changes. If a future round wants to disable system commenter for poller-created Events specifically, it can extend the mirror-mode guard further.

## §D — Drift detection + reconciliation

### D.1 Periodic full resync (default 24h)

A separate `BeadsResync` recurring job runs nightly:
- Iterates ALL open Beads issues.
- For each: invoke `mirror_issue` (§C.1) — idempotent upsert.
- Diff Beads `labels(issue_id)` against MySQL `taggings(card_id) join tags`. Apply any missing add/remove (§C.3).
- Refresh `beads_custom_statuses` (§C.2).

This catches any rows the event-cursor poller missed (rare — but cursor strategy can drop rows if Beads writes events out-of-order under load).

### D.2 Single-board invariant correction (closes S2 `fizzy-eq4.12`)

Per S2 §G.2: cards must have at most ONE `fizzy/board/<uuid>` label. The poller checks this on every `mirror_issue` tick:

```ruby
board_labels = beads_issue.labels.select { |l| l.start_with?("fizzy/board/") }
if board_labels.size > 1
  # Deterministic correction per S2 §G.2:
  # Prefer most-recent label-added event in events table
  keep = most_recent_board_label_added(beads_issue.id, board_labels)
  others = board_labels - [keep]
  others.each { |label| CommandClient.for(SystemActor.identity).remove_label(beads_issue.id, label) }
end
```

The corrective `remove_label` write goes through CommandClient (S5) with system actor — produces its own Beads event that the poller will see on next tick (no infinite loop because the correction is deterministic and idempotent).

Closes S2 placeholder `fizzy-eq4.12`.

### D.3 Orphan attachment cleanup (S7 §F.1 hook)

When a Beads issue is hard-deleted (detected by `mirror_issue` returning 404 from Beads): enqueue `OrphanCleanupJob.perform_later(issue_id)` (the actual destroy logic is Fizzy AR cascade per S7 §F.1).

## §E — Filter compilation (Fizzy filter UI → Card mirror SQL)

### E.1 Substrate

All filter queries compile to MySQL against:
- `cards` (mirror table, post-S1)
- `cards.beads_status`
- `taggings` join `tags`
- `assignments` join `users` join `identities`
- `comments` (for "has comment containing X")

NO `:beads` connection joins. NO cross-DB queries. Per Gemini's S2 prior #1 + P9 §B.

### E.2 Compiler structure

Existing `Filter` model + `Filter::Translator` (or successor — verify in I-S9) compiles user filter expressions. S9 ensures the compiler only emits queries against the substrate above.

Filter operators supported in V1:
- `status:open|closed|deferred|...` → `cards.beads_status = ?`
- `tag:foo` → `EXISTS(SELECT 1 FROM taggings JOIN tags ON ... WHERE taggings.card_id = cards.id AND tags.title = ?)`
- `assignee:me` / `assignee:user@email` → `EXISTS(SELECT 1 FROM assignments WHERE card_id = cards.id AND ...)`
- `created:>2026-01-01`, `closed:>2026-01-01` → range conditions on mirrored timestamps
- `text:"foo bar"` → routes through 16-shard FTS (§F)

### E.3 Performance budget

P9 §B.4 sets target: filter result <100ms p95 over 10K cards on a single account. Indexes on `cards(beads_status)`, `taggings(card_id, tag_id)`, `assignments(card_id, assignee_id)` already exist or get added in I-S9.

## §F — Search execution (16-shard FTS)

### F.1 Shard routing

`Search::Record` uses 16 shard tables (`search_records_0..15`). Shard determined by `CRC32(account_id) % 16`. Existing pattern; preserved.

### F.2 Content sourcing

Each shard row's `content` is sourced from the mirror:
- For `searchable_type="Card"`: card.title + card.beads_status + concatenated tag titles
- For `searchable_type="Comment"`: comment body plaintext (truncated to `Searchable::SEARCH_CONTENT_LIMIT`)

Updated by §C procedures via `Search::Record.upsert!` — no callbacks.

### F.3 Query execution

`Search::Record.search(query, user:)` (existing scope) — preserved unchanged. The 16-shard FTS routing happens server-side via the included DB-adapter module (`include const_get(connection.adapter_name)`).

## §G — Failure modes

### G.1 Poller crash mid-tick

Cursor advances only after transaction commit. Replayed rows are idempotent (B.1 + S8 §B.2). No data loss; possible duplicate side-effect job enqueues (since enqueues commit with transaction, this is OK).

### G.2 Beads adds new event types or status values

Mirror is conservative: unmapped `events.event_type` rows produce NO Fizzy Event (S8 §A "anything else not mirrored"). Unmapped `cards.beads_status` values are stored verbatim (varchar(32)) but routed to "Todo" fallback per S2 §B.2.

### G.3 30s budget exceeded

If a tick takes >30s consistently, options: (a) increase batch size, (b) parallelize per source (events parallel to comments — not per-row), (c) defer to V2 multi-worker design. V1 monitors via Solid Queue dashboards.

### G.4 Beads SQL connection failure

Tick fails fast; cursor doesn't advance; next tick retries. If failures persist, ops investigates.

### G.5 Mirror data divergence detected

§D.1 periodic full resync catches divergence. If divergence is structural (e.g., `cards.beads_status` doesn't match `beads_issue.status` after resync), it's a bug — log + alert.

## §H — Test strategy

### H.1 Unit tests
- `Beads::Mirror::Cursor.advance_all` advances each source independently.
- `BeadsPoller#perform` runs in `Current.beads_mirror?` context.
- Per-procedure idempotency (mirror_issue twice = same result).

### H.2 Integration tests
- End-to-end: Beads SQL row → poller tick → MySQL row + Search::Record + side effects.
- Replay: same Beads row processed twice → no duplicate Event, no duplicate notification.
- Single-board invariant violation → corrected on next tick.

### H.3 Performance tests
- 200-row batch processed in < 5s on dev hardware.
- 10K-card account filter query < 100ms p95.

### H.4 Drift tests
- Manually delete a Tagging row; trigger periodic resync; verify it's restored.

## §I — Open questions deferred

1) **Real-time SSE/WebSocket UI freshness** — V2+ per p10 §G.3 (Q-S-035).
2) **Multi-worker parallel poller** — V2 if 30s budget tightens.
3) **Branch-aware Dolt connection pooling** — V2 (per Q-S-033, only matters once branches exist).
4) **Bootstrap / backfill of historical Beads events** — covered by D.1 periodic resync but a one-time install-time backfill may be needed if forking from existing Beads data. Defer to install-setup spec.
5) **Search::Record reindex on schema change** — existing `SearchReindexJob` (per recent commit `466b215ef`) handles this; verify it works with mirror-sourced content.

## §J — Child bead inventory

Child beads (I-S9 implementation tasks) minted under epic `fizzy-pmi`.

**Closes 4 placeholders on lock**: `fizzy-1iz`, `fizzy-eq4.12`, `fizzy-edq.11`, `fizzy-n3l.6`.

| F.N | Bead | Title | Satisfies | Key dependencies |
|---|---|---|---|---|
| F.1 | `fizzy-pmi.1` | Add `beads_mirror_cursors` table (last_seen_at + processed_ids overlap window) + `Beads::Mirror::Cursor` model | §A.2 | none |
| F.2 | `fizzy-pmi.2` | Implement `BeadsPoller` recurring job (30s tick, mirror-mode guard, single-engine) | §A.1, §A.4 | `fizzy-pmi.1`, `fizzy-du0` (S3 SystemActor), Current.beads_mirror? change from S8 (`fizzy-n3l.5`) |
| F.3 | `fizzy-pmi.3` | Implement `mirror_issue` procedure (cards + Search::Record sync) | §C.1 | `fizzy-pmi.2`, `fizzy-m6r` (S1 cards.beads_status) |
| F.4 | `fizzy-pmi.4` | Add `beads_custom_statuses` mirror table + refresh in periodic resync | §C.2, §D.1 | `fizzy-pmi.2` |
| F.5 | `fizzy-pmi.5` | Implement label delta procedure (tags+taggings upsert_all per S5) | §C.3 | `fizzy-pmi.2`, `fizzy-k48` (S1 taggings widening), `fizzy-5yn` (S5 LabelNormalizer) |
| F.6 | `fizzy-pmi.6` | Implement comment mirror procedure (comments + ActionText + mention enqueue) | §C.4 | `fizzy-pmi.2`, S6 children (fizzy-edq.1 comments.id widen + fizzy-edq.5 plaintext→HTML) |
| F.7 | `fizzy-pmi.7` | Implement event mirror procedure (Event row creation per S8 §A) | §C.5 | `fizzy-pmi.2`, S8 children (fizzy-n3l.1 beads_event_id index, fizzy-n3l.3 EventMapper) |
| F.8 | `fizzy-pmi.8` | Implement `BeadsResync` periodic job (24h full resync) | §D.1 | `fizzy-pmi.3`, `fizzy-pmi.5` |
| F.9 | `fizzy-pmi.9` | Implement single-board invariant correction in mirror_issue | §D.2 | `fizzy-pmi.3`, `fizzy-75i` (S5 _add_system_label) |
| F.10 | `fizzy-pmi.10` | Implement orphan cleanup hook (Beads 404 → OrphanCleanupJob) | §D.3 | `fizzy-pmi.3`, `fizzy-nid` (S7 OrphanCleanupJob) |
| F.11 | `fizzy-pmi.11` | Filter compiler audit: ensure all filter operators emit Card mirror SQL only (no :beads joins) | §E.2 | `fizzy-pmi.3` |
| F.12 | `fizzy-pmi.12` | Search::Record content sourcing audit: verify upsert! is invoked for every cards/comments mirror | §F.2 | `fizzy-pmi.3`, `fizzy-pmi.6` |
| F.13 | `fizzy-pmi.13` | Integration tests: end-to-end poller tick (Beads row → MySQL + side effects) | §H.2 | `fizzy-pmi.3`, `fizzy-pmi.5`, `fizzy-pmi.6`, `fizzy-pmi.7` |
| F.14 | `fizzy-pmi.14` | Replay/idempotency tests: same Beads row twice → no duplicate side effects | §H.2 | `fizzy-pmi.13` |
| F.15 | `fizzy-pmi.15` | Performance test: 200-row batch < 5s; 10K-card filter < 100ms p95 | §H.3 | `fizzy-pmi.13` |

## §K — Validation checklist

- [x] §A single-engine poller architecture + per-source cursors + 30s tick
- [x] §B callback-bypass writes + explicit side effects (Notifiable WANT fires; Card touch SILENT via mirror-mode guard)
- [x] §C per-source procedures cover S2 (custom statuses), S4 (lifecycle fields), S5 (labels), S6 (comments), S8 (events)
- [x] §D drift detection covers periodic resync + single-board invariant + orphan cleanup
- [x] §E filter compilation explicitly forbids cross-DB joins (Gemini S2 prior #1 reaffirmed)
- [x] §F search execution preserves existing 16-shard FTS pattern
- [x] §G failure modes enumerated
- [x] §H test strategy covers unit + integration + replay + performance
- [x] §J child beads (15 minted) close 4 placeholders + cross-spec deps to S1, S3, S5, S6, S7, S8
- [ ] `[CLAUDE→CODEX S9 v1 ready]` sent + peer review complete
- [ ] `[FROM→TO S9: agreed]` 3-of-3 lock + 4 placeholders bd close on lock commit
