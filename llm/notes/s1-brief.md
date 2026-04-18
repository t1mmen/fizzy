# Brief — S1-card-fk-migration-spec — Q-S-002a

## Identity
- Round / bead: `S1-card-fk-migration-spec` / `fizzy-669` (epic)
- Drafter / owner: `fizzy-claude`
- Reviewers: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
- CEO ratification: not required per Q8a

## Context (inputs)
- All P1-P10 locked artifacts (the entire Planning batch)
- `llm/notes/p1-foundational-gap-inventory.md` §A (every Fizzy entity + FK column inventory)
- `llm/notes/p3-data-path-decision.md` §E (FK migration approach: widen to varchar(255) for all card-referencing FKs; option M-a)
- `llm/notes/p9-search-strategy.md` §A.2 (`cards.beads_status` new column added; Card stays as Fizzy mirror of Beads issues)
- `llm/notes/p7-multi-assignee-tags-labels.md` §A.2 (assignments sidecar FK type change confirmed)
- `db/schema.rb` — current FK column types
- Beads issue id format: `fizzy-<suffix>` per `.beads/config.yaml`

## Objective (one sentence)
Produce a complete, implementation-ready migration spec — captured as a parent epic + child task perfect-beads + a design doc — for converting every Fizzy table's `card_id`/`record_id`/`eventable_id` FK column from `uuid` to `varchar(255)` to accommodate Beads issue ids, plus adding the `cards.beads_status` column from P9.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/s1-card-fk-migration-spec.md` complete with sections:
  - **§A** — Migration approach + ordering + safety strategy
  - **§B** — Per-table migration plan (every affected table from P1 §A enumerated; ~16+ rows)
  - **§C** — Polymorphic column handling (events, mentions, reactions, notifications, action_text_rich_texts, active_storage_attachments)
  - **§D** — Rollback strategy
  - **§E** — Verification tests (per migration step)
  - **§F** — Card.beads_status column addition (per P9)
  - **§G** — Dry-run procedure
- [ ] Parent epic bead `fizzy-669` exists with full perfect-bead structure (currently in-progress; populate as S1 progresses)
- [ ] Child task beads created — one per atomic migration unit (per-table or per-cohesive-step). Each child has full perfect-bead structure (title verb-led, description=WHY, design=HOW, acceptance=WHAT verifiable, type, priority, labels, assignee, dependencies wired with parent-child to fizzy-669)
- [ ] Dependency graph wired: child task beads depend on each other where ordering matters; all are parent-child of fizzy-669
- [ ] Ratified 3-of-3 by `[S1: agreed]` signals

## Allowed paths (scope boundary)
- Writable: `llm/notes/s1-*.md`, `llm/LOG.md`, `llm/claude-state.md`, `.beads/` via `bd create` / `bd update` for perfect-bead authoring
- Read-only: app code, db/schema.rb, P1-P10 docs
- **Excluded**: any code change, any actual migration execution (this is SPEC, not IMPLEMENTATION)

## Out of scope (explicit)
- Running migrations (that's the I1+ Implementation round that consumes S1's beads)
- Adding the Card mirror table population logic (that's a separate spec round, S9 covers the poller)
- Auth/actor changes (S3 owns)
- UI changes (S2 owns)

## Sources of truth
- `db/schema.rb` (lines 1-859 — every table)
- `llm/notes/p1-foundational-gap-inventory.md` §A (entity inventory)
- `llm/notes/p3-data-path-decision.md` §E (M-a widen-all approach)
- `llm/notes/p9-search-strategy.md` §A.2 (Card mirror + beads_status column)
- `llm/notes/p7-multi-assignee-tags-labels.md` §A.2 (assignments sidecar)

## Verification plan
### Worker-verification
- `bd show fizzy-669` shows the epic with full perfect-bead fields
- `bd list --label=spec --label=migration` shows the parent + every child
- `bd show <child>` shows each child has parent-child dep to fizzy-669 + appropriate blocks deps to predecessors
- Cross-check: every table in §B mapping is enumerated in P1 §A FK list

### Operator-verification (CEO)
- Read `llm/notes/s1-card-fk-migration-spec.md` and `bd show fizzy-669` to understand the migration plan end-to-end

## Output location (artifact)
- `llm/notes/s1-card-fk-migration-spec.md` (the design doc)
- Parent epic: `fizzy-669` (already created)
- Child task beads (created via `bd create` during S1 execution; counts TBD ~15-25)
- LOG entries

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[S1: agreed]`
- `bd close fizzy-669` after I1 implementation round consumes it (NOT during S1 lock — epic stays open until child impl beads close)
- Commit + push to dev (incremental per work-persistence)
- Handoff to LOG: "S1 locked; opens S2 — Board/Column/Access projection spec (P4 → impl beads)"
