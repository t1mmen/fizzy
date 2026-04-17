# P9 — Search Strategy + Filter Execution (Fizzy ↔ Beads)

**Status**: drafting (P9 round in flight)
**Bead**: `fizzy-ew9`
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/p9-brief.md`

This decision doc closes Q-S-023 (search strategy: Fizzy 16-shard FTS vs `bd search` vs hybrid) and Q-S-024 (Filter execution against Beads). Builds on P3 (SQL reads via Trilogy + CLI writes), P4 (board=label-namespace), P7 (label conventions), P8 (canonical events log = Beads, but search is read-side so events are tangential).

---

## §A — Search strategy decision (Q-S-023)

### A.1 Ground truth

**Fizzy** (`app/models/concerns/searchable.rb`, `app/models/search/record/trilogy.rb`):
- Sharded `Search::Record` across 16 MySQL FTS shards (`search_records_0`..`search_records_15`).
- Shard key = `Zlib.crc32(account_id.to_s) % 16`.
- Indexed entities: `Card` (denormalized title + content), `Comment` (denormalized body, joined to card_id).
- Index lifecycle: AR callbacks (`after_create_commit :create_in_search_index`, `after_update_commit :update_in_search_index`, `after_destroy_commit :remove_from_search_index`).
- Boolean fulltext query against `(account_key, content, title)`.

**Beads** (`bd search --help` empirically verified):
- `bd search [query]` searches title + ID exact/prefix; excludes closed by default.
- Flags: `--assignee`, `--label`, `--status`, `--priority-min/max`, `--created-after/before`, `--closed-after/before`, `--no-assignee`, `--no-labels`, `--desc-contains` (description substring case-insensitive), `--query`, `--sort`, `--reverse`, `--limit`.
- ID-like queries (`bd-123`) use fast prefix match.
- No real FTS engine; description match is `LIKE '%term%'` style (substring).

### A.2 Decision

**Adopt option (c) hybrid: Fizzy keeps the 16-shard FTS, `Card` survives as a Fizzy AR model that mirrors Beads `issues` (Beads is canonical; Card is a projection); Searchable callbacks stay on Card/Comment as upstream; `bd search` is exposed only via a thin "advanced search" surface (CLI users + power-user UI).**

Concretely:
- The existing `Search::Record` table + Searchable concern stay essentially as-is, including the `Card` and `Comment` AR models that own the callbacks.
- The Fizzy `cards` table becomes a **projection/mirror** of Beads `issues` — `cards.id` = Beads issue id (varchar, per P3 §E migration); `cards.title`, `cards.status`, `cards.last_active_at` etc. mirror the corresponding Beads fields.
- The Beads → Fizzy poller (see §C) keeps the Card mirror in sync with Beads on a tight cadence (writes triggered via `bd` CLI eventually propagate back to the Card mirror).
- All Fizzy-side joins (Search, Filter, Notification, Assignment, Tagging, etc.) use Card AR as today — **no cross-DB joins required** because Card is a Fizzy MySQL row.
- `Beads::Issue` (P3 §D AR model on the `:beads` Trilogy connection) remains the canonical read for direct Beads queries (e.g., dependency graph, native bead-only operations); it is NOT used for app-side joining with Fizzy sidecars.
- "Source of truth": Beads remains canonical for task state per CEO Q2. Card is a derived view that may briefly lag (poller cadence — see §C). Conflicts are resolved by re-syncing Card from Beads.

### A.3 Rationale (vs (a) all-Fizzy-FTS, (b) all-bd-search)

| Strategy | Pro | Con |
|---|---|---|
| (a) Fizzy 16-shard FTS only | Best UX latency (<50ms), boolean query, comment search | Reindex burden — every Beads write must trigger an index update |
| (b) `bd search` delegation only | Beads-native, no projection table to maintain, no reindex burden | No comment search; substring-only description match (not real FTS); per-query CLI shell-out cost (~100-500ms); no boolean query |
| (c) **Hybrid (recommended)** | Fast UX FTS for the 95% UI flow; bd search for power-users + CLI parity; comment indexing preserved | Two-search-systems-to-maintain; index sync risk (Q-S-NEW: drift detection) |

(c) wins because:
1. Fizzy's 16-shard FTS is a known-good investment (mature, tested) — discarding it for substring-matching downgrade is a UX regression.
2. Comment search matters (Fizzy upstream supports it; users rely on "find that comment about X").
3. `bd search` complements rather than replaces — it covers the CLI and power-user "structured filter" surface.

### A.4 Search source-of-truth boundary

- **Search results UI in Fizzy**: queries Fizzy's `Search::Record` (16-shard FTS).
- **`bd search` CLI**: queries Beads directly (no Fizzy involvement).
- **No round-trip**: a user typing in Fizzy UI never invokes `bd`; a user typing `bd search ...` never invokes Fizzy.
- Both surfaces will return overlapping results for the same query terms but the index is decoupled (Fizzy may have a few seconds of stale data; bd is always strict-current).

---

## §B — Filter execution decision (Q-S-024)

### B.1 Ground truth

`Filter` (`app/models/filter.rb`) compiles a complex AR query over Card + 6 join tables (assignees, assigners, closers, creators, boards, tags). The `cards` method composes:
- `creator.accessible_cards.preloaded.published`
- + scopes for not_now, closed, unassigned, assigned_to, creator_id, board, tagged_with, creation_window, closure_window, closed_by, mentioning(term), column_id
- `.distinct`

### B.2 Decision

**Adopt option (a) from P1 §E.9: the Filter compiles to an AR query against the `Card` mirror table (Fizzy MySQL — see §A.2) plus existing Fizzy sidecar joins. NO cross-DB joins to Beads. NO `bd query` shell-out. Beads-native dimensions (labels, dep counts) get mirrored into Card-side columns or sidecar tables maintained by the poller (see §C).**

Concretely:
- `Filter#cards` keeps essentially its current shape: `creator.accessible_cards.preloaded.published.where(...)` etc. — except the AR scopes now resolve against the Card MIRROR table (§A.2), not the upstream-Fizzy authoritative `cards`.
- Each Filter dimension translates to a SQL clause within the Fizzy MySQL connection:
  - `assignees` → join Fizzy `assignments` ON `card_id = cards.id` WHERE assignee_id IN (...) (sidecar stays Fizzy-native; FK type changed per P3 §E)
  - `boards` → join `taggings`/`tags` Fizzy-side, where board membership is mirrored via Beads label sync (the poller writes `taggings` rows to mirror Beads `labels` matching `fizzy/board/<uuid>`)
  - `tags` → join `taggings`/`tags` (also mirrored from Beads `labels` by the poller)
  - `closers` → Fizzy `closures` table (mirror of Beads close events; see §C reindex)
  - `creators` / `creation_window` / `closure_window` → direct Card mirror columns (mirrored from Beads `issues.created_by`, `created_at`, `closed_at`)
  - `mentioning(term)` → JOIN to `Search::Record` shard for the term, intersect with the rest (Search::Record stays as-is; populated from Card/Comment AR callbacks driven by the poller)
  - `column_id` → resolves to status (Card.status mirrored from Beads) + board label (P4)
- All within ONE Fizzy connection. No cross-DB. No bd shell-out per filter eval.

### B.3 Why not (b) translate to `bd query` DSL

- `bd query` syntax is documented but limited (boolean over fields like status/priority/label; no FTS join).
- Fizzy `Filter` has FTS-like dimensions (`mentioning(term)`) that bd query can't express.
- Per-filter shell-out cost is unacceptable for kanban refresh patterns.
- Two-target compilation (sometimes SQL, sometimes bd) doubles the testing burden.

### B.3a Why NOT cross-DB joins (Beads::Issue ⋈ Fizzy sidecars)

Original v1 of this doc proposed joining the Beads::Issue AR model (Dolt connection) with Fizzy sidecars in a single SQL query. **This is impossible — Rails cannot join across two different database connections in one SQL statement.** The mirror-via-poller approach (§A.2 + §C) is the canonical fix: keep all join targets in the Fizzy DB, populated from Beads via the poller.

If for some advanced query we need a cross-DB intersection (e.g., "issues with bead-native dep type X AND Fizzy custom field Y"), we use the 2-phase intersect pattern: query Beads for issue_ids matching bead-native dims, then `Card.where(id: those_ids).joins(...).where(fizzy_dims)`. Spec round S-cross-db-intersect owns the helper.

### B.4 Performance budget

V1 target: a Filter eval (typical: 1 board + 2 tags + assignment scope) returns within **<200ms** for typical kanban view (~50-200 issues). Achievable because:
- All joins are Fizzy MySQL (Trilogy)-side; no fork, no cross-DB.
- Card mirror has indexes on `status`, `account_id`, `board_id`, etc. (preserves upstream indexes).
- `Search::Record` has FTS index on `(account_key, content, title)`.
- The poller updates Card mirror eagerly so cards reflect recent state within the freshness budget.

If empirical V1 testing shows >200ms, options: caching (Solid Cache layer over `Filter#cards.to_sql.hash`), denormalization (e.g., precomputed `card_label_set` column), or pagination tightening.

---

## §C — Reindex pipeline

### C.1 The problem

P3 routes all writes through `bd` CLI. Fizzy `Search::Record` is updated via AR `after_*_commit` callbacks on Card. With Card gone as an AR model (replaced by `Beads::Issue` which is `readonly?`), there are no AR callbacks to fire.

### C.2 Decision

**Reindex via the Beads → Fizzy ingestion poller (defined in P8 §D), but with a much tighter cadence (every 30s vs hourly for events).**

Concretely:
- The poller (deferred-but-designed in P8) becomes a real V1 component scoped to search reindex only (webhooks remain deferred).
- On each tick (every 30s):
  1. Query Beads `events` since last cursor for `event_type IN ('created', 'updated', 'closed', 'reopened', 'label_added', 'label_removed')` plus Beads `comments` since last cursor.
  2. For each unseen event/comment: call `Search::Record.upsert!` for the affected issue.
  3. Advance cursor (with the same lookback-window pattern from P8 §D.3 for safety).
- For `event_type = 'closed'` AND we don't index closed issues by default: call `Search::Record.find_by(...).destroy` for that issue.

### C.3 V1 freshness guarantee

- "Last 30 seconds of writes may not appear in Fizzy search."
- Acceptable for typical kanban use; documented in user-facing release notes.
- Power users can fall back to `bd search` for strict-current results.

### C.4 Bootstrap / backfill

On first install setup (or any fresh-clone run): the poller does a full backfill scan of all Beads issues + comments to populate `Search::Record`. One-time cost; spec round S-search-bootstrap owns the implementation.

---

## §D — Adapter shape (Search vs Filter)

```ruby
# app/models/concerns/searchable.rb (modified — callbacks rewired)
# Old: hooked into Card AR lifecycle.
# New: called by Beads::Reindexer (the poller from §C).

# app/jobs/beads/reindex_job.rb (new)
class Beads::ReindexJob < ApplicationJob
  # Recurring every 30s via config/recurring.yml
  def perform
    Beads::Reindexer.tick!
  end
end

# lib/fizzy/beads/reindexer.rb (new)
module Fizzy::Beads::Reindexer
  def self.tick!
    cursor = Beads::ReindexCursor.singleton
    new_events = Beads::Event.where("created_at > ?", cursor.last_seen_event_at).order(:created_at)
    new_comments = Beads::Comment.where("created_at > ?", cursor.last_seen_comment_at).order(:created_at)
    new_events.find_each { |e| process_event(e) }
    new_comments.find_each { |c| process_comment(c) }
    cursor.advance!
  end

  private

  def self.process_event(event)
    case event.event_type
    when "created", "updated", "label_added", "label_removed", "reopened"
      Search::Record.upsert_for_issue(event.issue_id)
    when "closed"
      Search::Record.remove_for_issue(event.issue_id)
    end
  end

  def self.process_comment(comment)
    Search::Record.upsert_for_comment(comment)
  end
end

# app/models/filter.rb (modified — #cards rewired)
class Filter < ApplicationRecord
  def cards
    @cards ||= begin
      # OLD: result = creator.accessible_cards.preloaded.published
      # NEW: result = Beads::Issue.accessible_to(creator)
      #              .joins(...)  # sidecar joins + Beads label joins
      #              .where(...)  # per dimension
      #              .order(sorted_by)
      # ... rest similar but querying through Beads::Issue
    end
  end
end
```

---

## §E — Resolved Q-S items (links back to P1)

- **Q-S-023 — How does search work — Fizzy 16-shard FTS, `bd search`, or hybrid?** → ANSWERED. Hybrid (option (c)): Fizzy 16-shard FTS over a Beads-mirrored projection drives UI search; `bd search` complements for CLI + power-user. See §A.
- **Q-S-024 — How do Fizzy `Filter` queries execute against Beads?** → ANSWERED. Option (a): Filter compiles to AR/SQL queries against `Beads::Issue` + Fizzy sidecar joins via Trilogy connection. No `bd query` shell-out. See §B.

A subsequent edit to `p1-foundational-gap-inventory.md` will mark these ANSWERED with a backlink.

---

## §F — Open questions for downstream rounds

> **Q-S-057 — Drift detection between Search::Record and Beads canonical state?**
> What if the reindex poller misses an event (process restart, lookback-window edge case)? Need a periodic full-reindex sweep OR drift-detection check. Spec round S-search-drift owns.

> **Q-S-058 — How do we handle bd `--ephemeral` issues (no events row per P8 §A.3)?**
> Per P8, ephemeral creates don't fire `created` events. Either index them via direct Beads SELECT polling OR exclude them entirely (most likely). Spec round confirms.

> **Q-S-059 — Search relevance scoring across two systems (Fizzy FTS rank vs bd search)?**
> Fizzy 16-shard FTS uses MySQL FULLTEXT relevance; `bd search` may rank differently. If we ever merge results (e.g., dual-call for completeness), we need a normalization story. V2 deferred unless needed earlier.

---

## §G — Validation checklist (pre-lock)

- [ ] §A picks (c) hybrid; rationale concrete vs (a)/(b).
- [ ] §A.4 explicitly states no round-trip: Fizzy UI never invokes bd; CLI never invokes Fizzy.
- [ ] §B picks (a) AR/SQL compilation; no `bd query` shell-out.
- [ ] §B.4 sets a concrete <200ms latency budget with fallback options.
- [ ] §C reindex via poller with 30s tick + lookback-window safety + bootstrap backfill.
- [ ] §D adapter sketch is signature-only.
- [ ] §E marks Q-S-023/024 ANSWERED.
- [ ] §F surfaces 3 follow-up questions.

---

## Convergence signal (P9)

3-of-3 lock: `[FROM→TO P9: agreed]` from all three agents.

After lock + commit + close `fizzy-ew9`, P10 (fork posture review, brief at `p10-brief.md`, drafter Codex per alternation) opens — **the final P-round**.
