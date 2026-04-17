# Workflow Templates — brief + signoff (bookends for rounds and beads)

**Status**: draft (RoE-5 pending)
**Applies to**: `fizzy-claude`, `fizzy-codex`, `fizzy-gemini`, and future maintainers.
**Scope**: two reusable templates:

- a **brief** that opens a round/bead with crisp scope + verifiable AC
- a **signoff** that closes or pauses a round/bead with an auditable handoff

These templates are deliberately strict. They are meant to prevent:

- scope creep
- ambiguous “done”
- lost context across multi-agent work
- “it worked on my machine” handoffs

Cross-links:

- Where artifacts live: `skills/documentation-hierarchy.md`
- Round mechanics: `skills/round-protocol.md`
- Beads rules + “perfect bead” requirements: `skills/bd-discipline.md`

---

## 1) When to use these templates

Use the **brief** before starting meaningful work on:

- any round (`P*`, `S*`, `I*`, `R*`, `RoE-*`)
- any bead you are about to claim or execute

Use the **signoff** when:

- you are done with the round/bead
- you are blocked and need help
- you are pausing and handing off
- you discovered follow-ups that need beads

---

## 2) Brief template (kickoff)

### 2.1 Template

Copy/paste and fill. Keep it tight and concrete.

```md
# Brief — <round-id or bead-id> — <short topic>

## Identity
- Round / bead: `<P3-foo>` or `<fizzy-xyz>`
- Drafter / owner: `<fizzy-claude | fizzy-codex | fizzy-gemini>`
- Review target: `<peer session(s) + CEO if needed>`

## Context (inputs)
- Input artifact(s): `<path(s) / bead id(s) / links>`
- What came before (1–3 bullets): `<prior rounds / decisions / constraints>`
- Non-negotiables: `<RoE constraints, no-code-change, schema-immutable, etc.>`

## Objective (one sentence)
`<Verb-led: e.g., “Draft v1 of skills/round-protocol.md with taxonomy + convergence mechanics.”>`

## Acceptance criteria (verifiable)
- [ ] `<AC 1 — file-grounded>`
- [ ] `<AC 2 — command/output-grounded>`
- [ ] `<AC 3 — tests/linters as applicable>`

Rules for AC:
- Must be unambiguous and checkable.
- Avoid “make it perfect”, “convert everything”, “works better”.

## Allowed paths (scope boundary)
- Writable/editable paths: `<default: .>`
- Explicitly excluded paths (if any): `<e.g., app/models/**>`
- Non-code boundaries: `<e.g., no beads claim, no external writes>`

## Out of scope (explicit)
- `<Thing we are NOT doing in this round>`
- `<Thing we are NOT deciding yet>`

## Sources of truth (anchors)
- `<file:line anchors that govern behavior>`
- `<skills docs that constrain process>`
- `<bd issue ids that constrain scope>`

## Verification plan
### Worker-verification (agent runs)
- `<commands the agent will run and include output for>`

### Operator-verification (human / elevated context)
- `<commands or checks the human should run (if any)>`

## Output location (artifact)
- Primary output: `<path/to/file.md | bead id | PR/branch>`
- Secondary outputs: `<llm/LOG.md entry, llm/notes/… link, bd remember…>`

## Definition of done
- [ ] AC satisfied
- [ ] Artifact written and readable
- [ ] Peer review requested via tmux + appended to `llm/LOG.md`
- [ ] If committed work: pushed (`git push`) and status clean
```

### 2.2 Brief notes specific to this program

- If the work is a **Spec** round (`S*`), the canonical “brief” is usually the bead itself (fields: description/design/acceptance/notes). Use a separate `llm/notes/…` brief only when coordinating across multiple beads, and link it from the bead.
- If the work is a **Planning** round (`P*`), the brief typically lives in `llm/notes/<round-id>.md` and a bead can be created once the work becomes “notable” per `skills/bd-discipline.md`.

---

## 3) Signoff template (close / pause / handoff)

### 3.1 Template

Copy/paste and fill. Every section must be present, even if “none”.

```md
# Signoff — <round-id or bead-id> — <short topic>

## Status
- Round / bead: `<P3-foo>` or `<fizzy-xyz>`
- Status: `<complete | blocked | partial>`
- Owner at signoff: `<fizzy-claude | fizzy-codex | fizzy-gemini>`
- Review requested from: `<peer session(s) / CEO>`

## Output(s)
- Primary artifact: `<path / bead id / commit sha>`
- Supporting artifacts: `<llm/notes/... | docs/... | skills/...>`
- Log entry: `llm/LOG.md` (timestamp header)

## What changed (tight)
- `<1–5 bullets, concrete>`

## Verification
### Worker-verification (ran)
- `<commands actually run + result>`

### Operator-verification (recommended)
- `<commands the operator should run, if any>`

## Concerns / follow-ups (always filled)
- `<none | list>`

## Pre-existing issues found (always filled)
- `<none | list; include file:line if applicable>`

## Suggested next tasks (always filled)
- `<none | list; if needed, propose bead titles or create beads>`

## Agent friction report (always filled)
- Tooling failures: `<none | list>`
- Process failures: `<none | list>`
- Missing docs / unclear rules: `<none | list>`

## What worked well (always filled)
- `<none | list>`
```

### 3.2 Signoff placement rules

Choose one canonical home; do not duplicate.

- If there is a bead: signoff goes into the bead (`bd update <id> --notes "..."` and/or `--comment "..."`), optionally with a linked `llm/notes/<id>-signoff.md` if too large.
- If there is no bead (rare): signoff goes into `llm/notes/<round-id>-signoff.md` and the follow-up should include creating a bead if the work is “notable”.

---

## 4) Worked examples (hypothetical Spec round)

### 4.1 Example brief (Spec)

```md
# Brief — S3-card-model-adapter — perfect bead drafting

## Identity
- Round / bead: `S3-card-model-adapter`
- Drafter / owner: `fizzy-claude`
- Review target: `fizzy-codex` (process), CEO (batch ratification later)

## Context (inputs)
- Input artifact(s): `llm/notes/grounding-codex.md`, `skills/bd-discipline.md`, `AGENTS.md`
- What came before: RoE-1..RoE-4 locked; planning notes exist for data model.
- Non-negotiables: Beads schema immutable; no Fizzy code changes during spec drafting.

## Objective (one sentence)
Draft a perfect bead that specifies how Fizzy’s Card CRUD will be driven by Beads issues data.

## Acceptance criteria (verifiable)
- [ ] A bead exists with title/description/design/acceptance/notes/type/priority/labels/assignee/deps/estimate populated.
- [ ] Dependencies use correct direction and type (validated by `bd show <id>` rendering).
- [ ] Peer review requested via tmux and logged in `llm/LOG.md`.

## Allowed paths (scope boundary)
- Writable/editable paths: `.beads/` via `bd` + `llm/notes/`
- Excluded: `app/**` (no code changes)

## Output location (artifact)
- Primary output: new bead id (e.g., `fizzy-abc`)
- Secondary outputs: `llm/notes/fizzy-abc.md` (optional), `llm/LOG.md` entry

## Definition of done
- [ ] AC satisfied
- [ ] Bead reviewed by peer
```

### 4.2 Example signoff (Spec)

```md
# Signoff — fizzy-abc — card model adapter spec

## Status
- Round / bead: `fizzy-abc`
- Status: complete
- Owner at signoff: fizzy-claude
- Review requested from: fizzy-codex

## Output(s)
- Primary artifact: `fizzy-abc` (bead fields populated)
- Log entry: `llm/LOG.md` (2026-04-XX HH:MM)

## What changed
- Added full design + AC
- Added deps to `fizzy-def` (`blocks`) and `fizzy-ghi` (`related`)

## Verification
### Worker-verification (ran)
- `bd show fizzy-abc` (confirmed all fields present + deps render correctly)

### Operator-verification (recommended)
- none

## Concerns / follow-ups
- none

## Pre-existing issues found
- none

## Suggested next tasks
- Create implementation bead for adapter layer + tests

## Agent friction report
- Tooling failures: none
- Process failures: none
- Missing docs: none

## What worked well
- Direction convention examples prevented a dependency inversion mistake
```

---

## 5) Convergence signal (RoE-5)

When all active agents agree RoE-5 is complete, each sends the others:

`[FROM→TO RoE-5: agreed]`

After all signals are present in `llm/LOG.md`, this file is locked and we move to topic 6 (`test-discipline.md`).

