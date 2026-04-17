# Brief — P1-foundational-gap-inventory — Fizzy ↔ Beads

## Identity
- Round / bead: `P1-foundational-gap-inventory` / `fizzy-08o`
- Drafter / owner: `fizzy-claude`
- Review target: `fizzy-codex` (peer review), `fizzy-gemini` (third-lens)
- CEO ratification: not required for this round (only `kamal deploy` per Q8a); CEO sees output at lock

## Context (inputs)
- **Input artifacts**:
  - `llm/notes/grounding-codex.md` — Codex's prior grounding (Fizzy data layer + beads internals)
  - `llm/notes/r0-dolt-cleanup.md` — confirmed canonical Dolt at `.beads/dolt`
  - `llm/notes/roe-batch-ratification-readout.md` — ratified RoE batch summary
  - All 7 ratified RoE skills in `skills/`
  - The Fizzy codebase itself (`app/models/`, `db/schema.rb`, `config/`)
  - Beads as installed in this repo (`.beads/dolt`, `bd` CLI)
- **What came before**: 20-round prep program kicked off after Q1-Q15 CEO Q&A; RoE meta-program closed (7 artifacts ratified); R0 Dolt plumbing fixed; Codex + Claude + Gemini all grounded.
- **Non-negotiables**:
  - Beads schema is **immutable** (RoE-4 §1) — we describe it; we do not propose changes to it.
  - No code changes during P1 (planning round).
  - Per CEO Q6: *every assumption needs diligent research*. Verify, do not infer.

## Objective (one sentence)
Produce `llm/notes/p1-foundational-gap-inventory.md` — a single source of truth that maps every Fizzy domain entity to its Beads equivalent (full / partial / Fizzy-only / hybrid), verifies each CEO-flagged assumption against ground truth, and surfaces a numbered list of architectural questions for the spec phase (S1-S10).

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/p1-foundational-gap-inventory.md` exists with the following five sections all populated:
  - **§A — Fizzy domain entities**: every model in `app/models/`, every table in `db/schema.rb`, every key field listed with type + purpose + `file:line` reference.
  - **§B — Beads schema**: every field in `dolt schema show issues`, every field in `dolt schema show dependencies`, every other Beads table verbatim.
  - **§C — Mapping table**: each Fizzy entity/field marked one of `[Beads-native]`, `[Beads-equivalent (with adapter)]`, `[Fizzy-only]`, `[Hybrid]`, or `[Drop in fork]`. Every row anchored to file:line + bead-field.
  - **§D — Verified assumptions**: explicit confirm/refute (with evidence) for the CEO-flagged items: (1) rich text/markdown in beads description, (2) attachments in beads, (3) mentions, (4) reactions, (5) search, (6) dependencies (10 types verified), (7) anything else that surfaced.
  - **§E — Architectural questions for S* rounds**: numbered list (Q-S-001, Q-S-002, …) of explicit unresolved questions the spec phase must answer. Each with a one-line context + the entities affected.
- [ ] Every assertion is grounded — file path with line numbers, or `dolt sql` / `bd` command output quoted verbatim. No paraphrase.
- [ ] No vague AC language ("convert all", "make perfect", etc.) anywhere in the doc.
- [ ] Ratified by all three agents via `[FROM→TO P1: agreed]` signals in `llm/LOG.md`.

## Allowed paths (scope boundary)
- **Writable/editable**: `llm/notes/p1-*.md`, `llm/LOG.md`, `llm/claude-state.md`, `llm/codex-state.md`, `llm/gemini-state.md`, `.beads/` via `bd` for issue updates.
- **Read-only this round**: everything else (especially `app/`, `lib/`, `config/`, `skills/`, `docs/`).
- **Excluded**: any code change, any RoE doc edit, any fork architecture decision (those go to S* rounds).

## Out of scope (explicit)
- Designing the adapter layer (S* rounds).
- Choosing how Fizzy reads from Dolt (CLI shell-out vs MySQL-protocol — that is Q-S-NNN that THIS doc surfaces).
- Adding any Fizzy code or migrations.
- Modifying any Beads schema (immutable per RoE-4).
- Resolving the deferred items list (Playwright, branch-pr-workflow, dolt push remote fix, etc.).

## Sources of truth (anchors)
- `app/models/**/*.rb` — Rails domain models
- `db/schema.rb` — Fizzy DB schema
- `config/initializers/tenanting/account_slug.rb` — multi-tenancy middleware
- `config/routes.rb` — HTTP API surface
- `app/views/**/_*.json.jbuilder` — JSON API shapes
- `dolt sql -q "show tables"` (run inside `.beads/dolt/fizzy/`) — beads tables
- `dolt schema show issues` — beads `issues` schema
- `dolt schema show dependencies` — beads `dependencies` schema
- `bd --help`, `bd dep add --help`, `bd link --help`, `bd export --help` — verified CLI surface
- `bd export --no-memories` — sample issue JSONL
- `llm/notes/grounding-codex.md` — prior grounding (use as reference, but verify all claims independently)
- `llm/notes/r0-dolt-cleanup.md` — Dolt mode + path
- AGENTS.md, STYLE.md, CLAUDE.md — project conventions

## Verification plan

### Worker-verification (agents run)
- `bd show fizzy-08o` confirms the bead is `in_progress` and assigned correctly throughout
- `wc -l llm/notes/p1-foundational-gap-inventory.md` after each section commit
- Cross-check: every Fizzy entity in §A appears in §C with a mapping; every beads field in §B appears in §C
- Run `bd dep add --help` and `bd link --help` to verify the 10 dep types empirically (per RoE-4 §6.2)
- Connect to Dolt: `cd .beads/dolt/fizzy && dolt sql -q "show tables"` then `dolt schema show <table>` for each
- For rich text / attachments / mentions / reactions verification: read the relevant Fizzy model + the beads schema; ground each claim

### Operator-verification (CEO, optional)
- CEO can `bd show fizzy-08o`, then read the inventory file, and respond with `[CEO→ALL P1: ratified]` or surface concerns

## Output location (artifact)
- **Primary output**: `llm/notes/p1-foundational-gap-inventory.md` (the inventory itself)
- **This brief**: `llm/notes/p1-brief.md` (you are reading it)
- **Bead state**: `bd update fizzy-08o --notes "..."` for interim notes; `bd close fizzy-08o` after lock + commit
- **Log entry**: every dispatch + signal in `llm/LOG.md` (per protocol)

## Definition of done
- [ ] All 5 AC bullets satisfied (file written, all sections populated, every claim grounded, no vague language, 3-of-3 ratified)
- [ ] `bd close fizzy-08o` after both peer signals land in LOG
- [ ] Commit on `dev` + `git push` (no `bd dolt push` per `dolt.auto-push = false` setting; we'll deal with the remote in a future plumbing round)
- [ ] `git status` shows up-to-date with origin
- [ ] Handoff entry in LOG: "P1 locked; opens P2 — proposed scope: <next round seed>"
