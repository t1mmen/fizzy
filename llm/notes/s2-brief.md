# Brief — S2-board-column-access-projection-spec

## Identity
- Round / bead: `S2-board-column-access-projection-spec` / `fizzy-eq4` (epic)
- Drafter / owner: `fizzy-codex` (alternation: S1=Claude → S2=Codex)
- Reviewers: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)
- CEO ratification: not required during round (P-batch already ratified; S-batch unblocked)

## Context (inputs)
- `llm/notes/p4-ui-projection-deep-dive.md` (entire doc — primary input)
  - §A Board model + label namespace `fizzy/board/<board_uuid>` + cardinality (single-board invariant)
  - §B Column model + ordering storage + V1 column-count posture
  - §C Status mapping (Beads ground-truth status set ↔ Fizzy-native column labels)
  - §D Card surface fields (V1 min + V1 recommended)
  - §E Dependencies UI (10 types grouped)
  - §F Hierarchy UI (`issues.parent_id`)
  - §G Goldness → priority resolution
- `llm/notes/p1-foundational-gap-inventory.md` §A entries for Board, Column, Access, Pin
- `llm/notes/p9-search-strategy.md` §A.2 (Card mirror — what columns Board/Column UI can SELECT against)
- `llm/notes/s1-card-fk-migration-spec.md` (already locked: `cards.id` is `varchar(255)`, FKs widened — Board projections SELECT against varchar `card_id`)
- `db/schema.rb` — current Board/Column/Access/Pin columns
- `app/models/board.rb`, `app/models/column.rb`, `app/models/access.rb` (current upstream behavior — what we KEEP vs REWIRE)
- `app/controllers/boards_controller.rb` + nested controllers (BoardsController, ColumnsController, AccessController) — current REST surface

## Objective (one sentence)
Produce an implementation-ready spec — captured as a parent epic + child task perfect-beads + a design doc — for projecting Boards, Columns, and Access onto Beads-backed Cards: how Board membership is queried (label-namespace SELECT against `cards.beads_status` + Card mirror), how Column placement is derived (status-driven for default columns + label-driven for custom), how Access is preserved (Fizzy-side, no Beads coupling), and what controller/query surface V1 ships.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/s2-board-column-access-projection-spec.md` complete with sections:
  - **§A** — Board projection model: how `Board.cards` is computed (label-namespace `fizzy/board/<board_uuid>` SELECT against Card mirror); single-board-per-issue invariant enforcement
  - **§B** — Column projection model: status-driven default columns (Triage/Open/In progress/Closed/Deferred) ↔ Beads `issues.status`; label-driven custom columns; ordering storage (per P4 §B.2)
  - **§C** — Card placement query plan: the actual SQL/AR queries that compute "which Card sits in which Column on which Board" (Card mirror `cards.beads_status` + label join; NO cross-DB join — Card mirror is Fizzy-MySQL)
  - **§D** — Controller surface for V1: Boards#index/show/create/update/destroy; Columns#create/update/destroy/reorder; Access#create/destroy; what argv `bd ...` calls are made on writes (board create/destroy = label namespace operations) vs pure Fizzy AR (Access)
  - **§E** — Pin projection: how `Pins` (per P4 §C.3) appear (Pin is a Fizzy sidecar pointing at `card_id varchar(255)` post-S1)
  - **§F** — Kanban + List view query patterns + acceptance criteria (drag-to-reorder column, drag-card-between-columns = label add/remove via `bd`)
  - **§G** — Single-board invariant enforcement: where (model validation? controller? poller?) and how (label add atomicity vs polling-detected drift)
  - **§H** — Open questions deferred to later S-rounds (with explicit handoff)
  - **§I** — Bead inventory (table mapping each AC to a child bead)
  - **§J** — Validation checklist
- [ ] Parent epic bead `<fizzy-S2-id>` exists with full perfect-bead structure
- [ ] Child task beads created — one per atomic projection unit (board-membership query, column-derivation query, controller wiring per resource, view template wiring, single-board invariant enforcement, pin projection, etc.). Each child has full perfect-bead structure (title verb-led, description=WHY, design=HOW, acceptance=WHAT verifiable, type, priority, labels, assignee, parent-child to S2 epic, blocks-deps where ordering matters)
- [ ] Dependency graph wired: child beads parent-child to S2 epic; ordering deps where applicable; cross-spec deps to S1 children where Card-mirror schema is a precondition
- [ ] Ratified 3-of-3 by `[S2: agreed]` signals

## Allowed paths (scope boundary)
- Writable: `llm/notes/s2-*.md`, `llm/LOG.md`, `llm/claude-state.md` (and codex/gemini equivalents), `.beads/` via `bd create` / `bd update`
- Read-only: app code, db/schema.rb, P1-P10 docs, S1 doc
- **Excluded**: any code change, any actual Board/Column rewire (this is SPEC, not IMPLEMENTATION); auth posture (S3 owns); lifecycle/entropy details (S4 owns); label sidecar table design (S5 owns — S2 only consumes the label namespace decision from P4 §A.5 + P7); rich text on Card description (S6 owns); attachments (S7 owns); search/filter/poller internals (S9 owns — S2 only consumes the Card-mirror schema from P9)

## Out of scope (explicit)
- Implementing the controllers / running migrations / wiring the views (that's I-S2 implementation round)
- Designing the labels sidecar AR model (S5)
- Designing the events/poller (S8 + S9)
- Any V2 features (per p10 §G.3 deferrals)

## Sources of truth
- `llm/notes/p4-ui-projection-deep-dive.md` (primary)
- `llm/notes/p9-search-strategy.md` §A.2 (Card mirror schema — what Board projections SELECT)
- `llm/notes/p7-multi-assignee-tags-labels.md` §A (label namespace + canonicality)
- `llm/notes/s1-card-fk-migration-spec.md` (post-migration FK types Board projections rely on)
- `db/schema.rb` (Board/Column/Access/Pin current shape)

## Verification plan
### Worker-verification
- `bd show <S2-epic>` shows the epic with full perfect-bead fields
- `bd list --label=spec --label=projection` (or equivalent) shows the parent + every child
- `bd show <child>` shows each child has parent-child dep to S2 epic + appropriate blocks-deps to predecessors
- Cross-check: every §C query in the design doc has a corresponding bead in §I
- Cross-check: every §D controller mentioned has a corresponding bead in §I
- Single-board invariant has at least ONE bead with explicit acceptance criteria (test plan)

### Operator-verification (CEO)
- Read `llm/notes/s2-board-column-access-projection-spec.md` and `bd show <S2-epic>` to understand the projection plan end-to-end
- Spot-check that Card mirror is the SQL substrate (no Dolt-side board queries) — this is the architecturally load-bearing claim

## Output location (artifact)
- `llm/notes/s2-board-column-access-projection-spec.md` (the design doc)
- Parent epic bead (TBD id; `bd create` during S2 v1 draft)
- Child task beads (created via `bd create` during S2 execution; counts TBD ~10-18)
- LOG entries

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[S2: agreed]`
- Parent epic stays OPEN until I-S2 implementation round consumes it (per S1 precedent)
- Commit + push to dev (incremental per work-persistence)
- Handoff to LOG: "S2 locked; opens S3 — Auth + actor propagation spec (P5 → impl beads)"

## Drafter alternation note
- S1 = Claude drafted, Codex peer, Gemini third-lens → locked
- **S2 = Codex drafts, Claude peer, Gemini third-lens** (this brief)
- S3 = Claude drafts, Codex peer, Gemini third-lens (next)
- Pattern: Claude/Codex alternate as drafter; Gemini is permanent third-lens
