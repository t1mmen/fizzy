# Brief — P9-search-strategy — Q-S-023/024

## Identity
- Round / bead: `P9-search-strategy` / `fizzy-XXX` (created at dispatch)
- Drafter / owner: `fizzy-claude` (alternation: P5 Claude, P6 Codex, P7 Claude, P8 Codex → P9 Claude)
- Reviewers: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)

## Context
- P1 §A.7 (Fizzy 16-shard MySQL FTS), §B (Beads has no native FTS — only `bd search` over title/body), §E.9 (Q-S-023 search strategy / Q-S-024 Filter execution against Beads)
- P3 (Beads SQL access via Trilogy), P4 (saved-Filter-as-board pattern), P7 (label conventions for filter dimensions)
- `app/models/search/record.rb`, `app/models/search/record/trilogy.rb`, `app/models/search/query.rb`
- `app/models/concerns/searchable.rb`
- `app/models/filter.rb` and join tables
- `bd search --help`

## Objective
Decide how full-text search and saved-filter queries execute over a Beads-source-of-truth world: Fizzy 16-shard FTS (Fizzy-side projection table) vs `bd search` delegation vs hybrid. Closes Q-S-023 and Q-S-024.

## Acceptance criteria
- [ ] File `llm/notes/p9-search-strategy.md` with sections:
  - **§A — Search strategy** (Q-S-023): pick one of (a) Fizzy 16-shard FTS over Beads-mirrored projection; (b) delegate to `bd search`; (c) hybrid (Fizzy FTS for cards/comments, bd for native bead-DSL queries). With trade-off analysis.
  - **§B — Filter execution** (Q-S-024): how Fizzy `Filter` objects compile to backend queries (SQL against Beads issues, OR `bd query` DSL, OR both). With sketch.
  - **§C — Re-indexing pipeline**: who keeps the search index in sync with Beads writes (post-CLI hook, Solid Queue job, lazy reindex, etc.).
  - **§D — Search performance budget**: V1 latency target (<200ms? <500ms?) and approach to staying within it.
  - **§E — Adapter shape**: how `Search::Record` (existing 16-shard model) interacts with `Beads::Issue` (P3 AR model).
  - **§F — Resolved Q-S items**.
  - **§G — Open questions**.
- [ ] Cross-link from p1 inventory.
- [ ] No code changes; sketches only.
- [ ] Ratified 3-of-3 by `[P9: agreed]`.

## Allowed paths
- Writable: `llm/notes/p9-*.md`, LOG/state, p1 (Q-S markers).
- Read-only: app code, P3-P8 docs.

## Out of scope
- Implementation (Spec round S-search).
- Fork posture review (P10).

## Sources of truth
- `app/models/search/record.rb`, `record/trilogy.rb`, `record/sqlite.rb`
- `app/models/search/query.rb`
- `app/models/concerns/searchable.rb`
- `app/models/filter.rb` + join tables (assignees_filters, etc.)
- `bd search --help`
- P3 (data path), P4 (board=label = filter), P7 (label conventions)

## Verification
- For each chosen pattern, demonstrate via Rails console / Dolt SQL the round-trip behavior.

## Output
- `llm/notes/p9-search-strategy.md`
- Updated p1 inventory
- Bead `fizzy-XXX` close
- LOG entries

## Definition of done
- AC satisfied
- 3-of-3 `[P9: agreed]`
- `bd close fizzy-XXX`
- Commit + push (per `work-persistence.md` — at first-write, then incrementally)
- Handoff: "P9 locked; opens P10 — fork posture review (Q-S-007/027 + community-bead-UIs research)"
