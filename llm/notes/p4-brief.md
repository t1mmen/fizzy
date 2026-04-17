# Brief — P4-ui-projection-deep-dive — kanban onto beads (board + column + status)

> **STATUS**: skeleton (drafted in advance; finalize after P3 lands so we cite P3 decision). Bead created at P4 dispatch time.

## Identity
- Round / bead: `P4-ui-projection-deep-dive` / `fizzy-XXX` (created at dispatch)
- Drafter / owner: `fizzy-codex` (alternation: P1 mixed, P2 Codex, P3 Claude → P4 Codex)
- Review target: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)

## Context (inputs)
- `llm/notes/p1-foundational-gap-inventory.md` §E.2 — Q-S-003 (board+column projection), Q-S-009 (Board as entity vs Filter), Q-S-010 (column position storage), Q-S-028 (Goldness vs priority), Q-S-029 (issue_type surface), Q-S-030 (dep types in v1), Q-S-031 (parent_id hierarchy)
- `llm/notes/p3-data-path-decision.md` (locked) — chosen data-path informs how we query for board/column views
- `app/models/board.rb`, `app/models/column.rb`, `app/views/boards/`, `app/views/columns/`, `app/views/cards/` — current Fizzy UI semantics
- Beads `issues.status` enum (default: open/in_progress/blocked/deferred/closed; can extend via `custom_statuses` table — see P1 §B)
- `llm/notes/community-bead-uis-research.md` — pattern library from beadboard/gastownhall (if relevant)

## Objective (one sentence)
Decide how the Fizzy kanban UI (Board → Column → Card) projects onto Beads data (status, labels, custom_statuses) — answering Q-S-003, Q-S-009, Q-S-010, plus the surface decisions for Q-S-028/029/030/031 — so the Spec phase can author concrete adapters and views.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/p4-ui-projection-deep-dive.md` with sections:
  - **§A — Board model decision**: Board stays as Fizzy entity OR collapses to a saved Filter OR becomes a labels-set. With evidence + trade-off analysis.
  - **§B — Column model decision**: Column is Fizzy entity OR derived from Beads `custom_statuses`/`labels` OR derived from a Fizzy-side group-by config. Including how column ordering survives.
  - **§C — Status mapping**: explicit table mapping every Beads status (open/in_progress/blocked/deferred/closed + any customs we add) to which UI column(s) it appears in by default, and how user-customizable that is.
  - **§D — Card surface fields**: explicit list of which Beads-native fields (priority, issue_type, estimated_minutes, acceptance_criteria, design, notes, due_at, defer_until) get UI surface in v1, with proposed widget for each.
  - **§E — Dependencies UI**: how the 10 dep types render in v1 (list view minimum; graph view optional). Grouping suggestion.
  - **§F — Hierarchy UI**: how `issues.parent_id` renders (tree view? indented children? collapse?). Recommendation for v1 minimum.
  - **§G — Goldness vs priority resolution**: pick one of the Q-S-028 candidates and justify.
  - **§H — Resolved Q-S items**: marks Q-S-003, 009, 010, 028, 029, 030, 031 as ANSWERED with link.
  - **§I — Open questions for downstream rounds**: any new Q-S items.
- [ ] Cross-link from p1 inventory's resolved Q-S entries to p4 §H.
- [ ] No code changes; visual sketches in ASCII or text references to existing Fizzy views OK.
- [ ] Ratified 3-of-3 by `[P4: agreed]`.

## Allowed paths (scope boundary)
- **Writable**: `llm/notes/p4-*.md`, `llm/LOG.md`, `llm/codex-state.md`, `llm/notes/p1-foundational-gap-inventory.md` (Q-S markers only).
- **Read-only**: app code, models, views, P3 decision doc.
- **Excluded**: any code change, any view template change, any model change.

## Out of scope (explicit)
- Implementing the column reordering UI (Implementation round).
- Choosing auth bridging (P5).
- Choosing lifecycle adapter (P6).
- Multi-assignee gap (P7).
- Events/webhooks (P8).
- Search (P9).

## Sources of truth (anchors)
- `app/models/board.rb`, `app/models/column.rb`, `app/views/boards/_board.json.jbuilder`, `app/views/columns/_column.json.jbuilder`, `app/views/cards/_card.json.jbuilder`
- Beads `issues.status` defaults + `custom_statuses` table (P1 §B)
- Beads `labels` table + `bd link --help` (5 of 10 dep types)
- `llm/notes/p3-data-path-decision.md` (data-path)
- `llm/notes/community-bead-uis-research.md` (UI patterns to consider/skip)

## Verification plan
### Worker-verification
- For each chosen mapping (e.g., "column = group-by status"), demonstrate via a Rails console / Dolt SQL query that we can list issues per column without N+1 patterns.
- Cross-reference every UI surface field decision against the Fizzy view that currently renders that field to flag deprecation or net-new work.

### Operator-verification
- CEO can read p4-ui-projection-deep-dive.md and follow §A → §B → §H to understand the kanban-onto-beads model.

## Output location (artifact)
- `llm/notes/p4-ui-projection-deep-dive.md`
- Updated `llm/notes/p1-foundational-gap-inventory.md` (Q-S markers)
- Bead `fizzy-XXX` notes/close
- LOG entries

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[P4: agreed]`
- `bd close fizzy-XXX`
- Commit + push to `dev`
- Handoff entry in LOG: "P4 locked; opens P5 — proposed scope: auth bridging deep-dive (Q-S-004/008)"
