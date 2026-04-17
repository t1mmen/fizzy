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

**Adopt option (c) hybrid: Fizzy keeps the 16-shard FTS, `Card` survives as a Fizzy AR model that MIRRORS Beads `issues` (Beads is canonical; Card is a projection); Searchable callbacks stay on Card/Comment as upstream; `bd search` is exposed only via a thin "advanced search" surface (CLI users + power-user UI).**

**CRITICAL constraint (per Codex round-3 catch)**: the poller MUST write to Card/Comment via callback-bypassing methods (`upsert_all` / `update_columns`) and then EXPLICITLY trigger `Search::Record.upsert!` for each. Naive AR `update!` would fire Eventable / Mentions / Watchable / Notifiable / `eventable.event_was_created` callbacks — producing duplicate Fizzy events, system comments, webhook firings, and notification spam. See §C and §D for the safe write pattern.

Concretely:
- The existing `Search::Record` table + Searchable concern stay essentially as-is, including the `Card` and `Comment` AR models that own the callbacks for *user-initiated* writes (which the fork has fewer of, since most writes go through `bd` CLI).
- The Fizzy `cards` table becomes a **projection/mirror** of Beads `issues` — `cards.id` = Beads issue id (varchar, per P3 §E migration); `cards.title`, `cards.last_active_at`, etc. mirror Beads fields.
- **Status enum disambiguation (per Codex round-3 catch)**: Fizzy `Card.status` enum is `{drafted, published}`; Beads `issues.status` is `{open, in_progress, blocked, deferred, closed}`. We keep `Card.status` enum unchanged (for upstream code paths that still depend on it), AND add a NEW `cards.beads_status` string column that mirrors Beads `issues.status`. Mapping rule:
  - Card mirror always created with `status='published'` (no `drafted` in fork — issues only exist after `bd create`).
  - "Inbox" (no board label) is recognized via absence of `fizzy/board/*` Tagging row, NOT via Card.status.
  - `Card::Searchable#searchable?` continues to gate by `published?` (which is always true for mirror cards). Closed-search policy (§C.3) handled separately.
- The Beads → Fizzy poller (see §C) keeps the mirror in sync with Beads on a tight cadence.
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

P3 routes all writes through `bd` CLI. Fizzy `Search::Record` is updated via AR `after_*_commit` callbacks on `Card` and `Comment`. With Card now a Fizzy mirror of Beads (per §A.2), the callbacks survive — but their TRIGGER must be the poller updating Card from Beads, not direct user writes (which now flow through `bd` first).

The poller has TWO mirroring jobs:
1. Keep Card + Comment + sidecars (Closure, Tagging, etc.) in sync with Beads.
2. As a side effect of those AR writes, Searchable callbacks fire and Search::Record updates.

### C.2 Decision

**Reindex via the Beads → Fizzy ingestion poller (defined in P8 §D), but with a much tighter cadence (every 30s vs hourly for events) and broader scope (Card + Comment mirror updates, not just Search::Record).**

Concretely:
- The poller (deferred-but-designed in P8) becomes a real V1 component for **mirror-sync** (Card / Comment / Closure / Tagging mirror tables) — the Search::Record updates fall out for free via the existing Searchable AR callbacks.
- On each tick (every 30s):
  1. Query Beads `events` since last cursor for `event_type IN ('created', 'updated', 'closed', 'reopened', 'label_added', 'label_removed', 'status_changed')` plus Beads `comments` since last cursor.
  2. For each unseen event:
     - `created` → `Card.create!(id: <beads-id>, ...)` (AR triggers `Searchable#create_in_search_index`)
     - `updated` / `status_changed` → `Card.find(<beads-id>).update!(...)` (AR triggers `update_in_search_index`)
     - `closed` → `Card.find(<beads-id>).update!(status: 'closed', closed_at: ...)` AND `Closure.create!(card: <card>, user: <resolved from event.actor>)` mirror; AR fires update callback (see §C.3 for closed-search policy)
     - `reopened` → reverse: clear `Closure`, update Card status
     - `label_added` / `label_removed` → upsert Tagging row, mirror Beads label string into Fizzy Tag (find or create)
  3. For each unseen Beads comment: `Comment.create!(card: <card>, body: ..., creator: <resolved from event.actor>)`
  4. Advance cursor (with the lookback-window pattern from P8 §D.3 for safety).

### C.3 Closed-search policy

**Search::Record stays for closed cards** (do NOT destroy on close). Default UI search filter excludes closed; user can opt in via "include closed" toggle (matches upstream Fizzy behavior). Keeping closed indexed preserves "find that closed bug from 6 months ago" — a real workflow.

### C.4 V1 freshness guarantee

- "Last 30 seconds of writes may not appear in Fizzy search OR in Fizzy UI Card listing."
- Acceptable for typical kanban use; documented in user-facing release notes.
- Power users can fall back to `bd search` for strict-current results (no projection lag).

### C.5 Bootstrap / backfill

On first install setup (or any fresh-clone run): the poller does a full backfill scan of all Beads issues + comments to populate `Card` + `Comment` mirror tables (which then triggers `Search::Record` population via callbacks). One-time cost; spec round S-search-bootstrap owns the implementation.

---

## §D — Adapter shape (Search vs Filter)

```ruby
# app/models/concerns/searchable.rb (UNCHANGED from upstream)
# Card and Comment AR keep their after_*_commit callbacks.
# The TRIGGER for those callbacks is now the poller updating Card/Comment
# from Beads (not direct user controllers — those go through bd CLI first).

# app/models/card.rb (changed: now a mirror of Beads issues)
# - cards.id is varchar(255) matching Beads issue id (per P3 §E migration)
# - cards.beads_status NEW string column mirrors Beads issues.status; cards.status enum stays {drafted, published} (always 'published' for mirror)
# - All upstream Card concerns/scopes/associations stay
# - The poller writes to Card via callback-bypassing AR methods (upsert_all/update_columns); see Beads::Reindexer above
# - User-initiated writes still go through controllers but flow: controller → CommandClient (bd CLI) → Beads → poller → Card upsert (callback-bypass)
class Card < ApplicationRecord
  # Searchable, scopes, associations: all unchanged from upstream
  # NOTE: do NOT add a #upsert_from_beads(beads_issue) method that triggers `update!` —
  # that fires Eventable/Mentions/Watchable callbacks. Use AR's upsert_all in the
  # poller (Beads::Reindexer above) and explicitly trigger Search::Record updates.
end

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
    beads_issue = Beads::Issue.find(event.issue_id)
    case event.event_type
    when "created", "updated", "status_changed", "reopened"
      # CRITICAL: callback-bypassing write. AR upsert_all skips after_*_commit hooks
      # (Eventable, Mentions, Watchable, Searchable). Then explicit Search::Record sync.
      Card.upsert_all([{
        id: beads_issue.id,
        title: beads_issue.title,
        beads_status: beads_issue.status,
        status: 'published',  # Always published for mirror; see §A.2 status disambiguation
        last_active_at: beads_issue.updated_at,
        # ... other mirror columns
      }], unique_by: :id)
      Search::Record.upsert_for_issue(beads_issue.id)  # Explicit; bypasses Searchable callback
    when "label_added"
      sync_taggings_for_issue(beads_issue)  # Same callback-bypass pattern
    when "label_removed"
      sync_taggings_for_issue(beads_issue)
    when "closed"
      Card.upsert_all([{ id: beads_issue.id, beads_status: 'closed', last_active_at: beads_issue.updated_at }], unique_by: :id)
      Closure.upsert_all([{ card_id: beads_issue.id, user_id: resolve_actor(event.actor)&.id }], unique_by: :card_id)
      Search::Record.upsert_for_issue(beads_issue.id)  # Closed cards stay indexed per §C.3
    end
  end

  def self.process_comment(beads_comment)
    Comment.upsert_all([{
      id: beads_comment.id,
      card_id: beads_comment.issue_id,
      creator_id: resolve_actor(beads_comment.author)&.id,
      # body is rich-text-via-ActionText; needs separate ActionText::RichText insert.
      # Spec round S-comment-mirror owns the rich-text mirror complexity.
    }], unique_by: :id)
    Search::Record.upsert_for_comment(beads_comment.id)  # Explicit; bypasses Searchable callback
  end
end

# app/models/filter.rb (UNCHANGED from upstream — already queries Card via accessible_cards)
# The Card it queries is now a mirror of Beads, but the AR shape and joins are identical.
```

Adapter shape note: `Beads::Issue` (P3 §D, on `:beads` Trilogy connection) is used by the poller and by direct-Beads-query code paths (e.g., dependency graph rendering). Card AR (Fizzy MySQL connection) is what Filter / Search / Notification all join with.

---

## §E — Resolved Q-S items (links back to P1)

- **Q-S-023 — How does search work — Fizzy 16-shard FTS, `bd search`, or hybrid?** → ANSWERED. Hybrid (option (c)): Fizzy 16-shard FTS over a Beads-mirrored projection drives UI search; `bd search` complements for CLI + power-user. See §A.
- **Q-S-024 — How do Fizzy `Filter` queries execute against Beads?** → ANSWERED. Option (a): Filter compiles to AR/SQL queries against the `Card` MIRROR table (Fizzy MySQL) + existing Fizzy sidecar joins. **No cross-DB joins** (Rails cannot join Beads/Dolt with Fizzy/MySQL in one statement; Card mirror exists in Fizzy MySQL and is populated by the poller from Beads). No `bd query` shell-out. See §A.2, §B, §B.3a.

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
