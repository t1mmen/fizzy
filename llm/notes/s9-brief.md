# Brief — S9-search-filter-poller-spec

## Identity
- Round / bead: `S9-search-filter-poller-spec` / `fizzy-pmi` (epic)
- Drafter / owner: `fizzy-claude` (alternation: S8=Codex, S9=Claude)
- Reviewers: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)

## Context (inputs)
- `llm/notes/p9-search-strategy.md` — primary input
  - §A.2 Card mirror doctrine (callback-bypass upsert_all + explicit Search::Record sync)
  - §B filter execution (compiled to Card mirror queries; no cross-DB joins)
  - §C 16-shard FTS architecture
  - §D drift detection + reconciliation
- All locked S-round mirror contracts that S9 must implement:
  - `llm/notes/s2-board-column-access-projection-spec.md` §B.3 (label projection — but actual label mirror is S5)
  - `llm/notes/s4-lifecycle-entropy-spec.md` §C.3 (cards.beads_status, closed_at, defer_until, close_reason mirror) — PLACEHOLDER `fizzy-1iz`
  - `llm/notes/s5-labels-assignees-spec.md` §B.3 (Tag/Tagging mirror callback-bypass; assignment one-way Fizzy→Beads, not mirrored back) — PLACEHOLDER fizzy-6iv was closed by S5 lock
  - `llm/notes/s6-rich-text-comments-spec.md` §D (comments mirror + ActionText cache + mention/watch derivations) — PLACEHOLDER `fizzy-edq.11`
  - `llm/notes/s7-attachments-storage-quotas-spec.md` §F.1 (orphan cleanup hook on Beads issue hard-delete)
  - `llm/notes/s8-events-activity-feed-spec.md` §A/§B (mirror Beads events/comments into Fizzy Event rows + dedup via beads_event_id) — PLACEHOLDER `fizzy-n3l.6`
- `llm/notes/s2-board-column-access-projection-spec.md` §G.2 (single-board invariant drift correction owned by S9 poller) — PLACEHOLDER `fizzy-eq4.12`
- `app/jobs/searchable_*` + `app/models/search/*` (existing 16-shard FTS code surface)
- `app/models/concerns/searchable*.rb` (existing Searchable concerns we mostly preserve)
- `db/schema.rb` (search_records_0..15 tables; post-S1 widened searchable_id)

## Objective (one sentence)
Produce an implementation-ready spec for the S9 poller — the single Beads→Fizzy mirror engine that ingests Beads `events` + `comments` + `issues` snapshots and writes (callback-bypass) into MySQL `cards`, `comments`, `tags`/`taggings`, `events`, `notifications`, `action_text_rich_texts`, AND the 16-shard `search_records_*` FTS — closing every poller-side placeholder bead from S2/S4/S5/S6/S8 — plus the filter compilation pipeline that turns user filter UI into MySQL queries against the Card mirror (no cross-DB joins).

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/s9-search-filter-poller-spec.md` complete with sections:
  - **§A** — Poller architecture: tick interval (P9 30s), event cursor strategy (Beads `events.id` highwater? timestamp?), idempotency contract
  - **§B** — Mirror write contract: callback-bypass upsert_all per P9; explicit Search::Record sync; explicit watch/mention derivations for events that don't fire normal callbacks
  - **§C** — Per-source mirror procedures: events→Event rows (per S8 mapping), comments→comments mirror + ActionText cache + Event rows + mentions (per S6+S8), labels→tags+taggings (per S5), issues snapshots→cards.beads_status + closed_at + defer_until + close_reason (per S4), custom_statuses→mirror table for S2 column routing
  - **§D** — Drift detection + reconciliation: full periodic resync; single-board invariant correction (per S2 §G.2); orphan attachment cleanup hook (per S7 §F.1)
  - **§E** — Filter compilation: how Fizzy filter UI compiles to Card mirror SQL (no cross-DB joins per Gemini's S2 prior #1); supports tag, status, assignee, date filters
  - **§F** — Search execution: 16-shard FTS query routing (existing pattern); Search::Record content sourcing from mirror (cards.title + cards.beads_status + comment bodies + tags)
  - **§G** — Failure modes: poller crash mid-tick recovery (cursor advance only after successful commit); Beads schema additions (custom_statuses) that the mirror layer doesn't yet know about
  - **§H** — Test strategy
  - **§I** — Open questions deferred
  - **§J** — Bead inventory
  - **§K** — Validation checklist
- [ ] Parent epic + child beads (~12-18 — biggest S-round so far)
- [ ] **Closes 4 placeholders on lock**: `fizzy-1iz` (S4 lifecycle mirror), `fizzy-eq4.12` (S2 single-board drift), `fizzy-edq.11` (S6 comments mirror), `fizzy-n3l.6` (S8 events mirror)
- [ ] Cross-spec deps to S1-S8 epics + their relevant child beads
- [ ] Ratified 3-of-3 by `[S9: agreed]` signals

## Allowed paths
- Writable: `llm/notes/s9-*.md`, `llm/LOG.md`, `llm/claude-state.md`, `.beads/`
- Read-only: app code, db/schema.rb, P1-P10 docs, S1-S8 docs

## Out of scope
- Implementation (I-S9); UI changes for filter editor (existing Fizzy UI mostly survives); FTS shard rebalancing (V2+); real-time SSE/WebSocket UI freshness (V2+ per p10)

## Sources of truth
- `llm/notes/p9-search-strategy.md` (primary)
- All S2-S8 mirror contracts (S9 implements them coherently)
- `app/jobs/searchable_*`, `app/models/search/*`, `app/models/concerns/searchable*.rb`

## Definition of done
- 3-of-3 `[S9: agreed]`; epic stays OPEN until I-S9
- 4 placeholders CLOSED with bd close on lock
- Handoff: "S9 locked; opens S10 — Metadata boundary spec (P1+P3, last spec round, Codex drafts per alternation)"

## Drafter alternation
- S9 = Claude drafts, Codex peer, Gemini third-lens
- S10 = Codex drafts (final S-round)
