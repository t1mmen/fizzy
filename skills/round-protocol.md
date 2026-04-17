# Round Protocol — how we run “rounds” in this program

**Status**: draft (RoE-3 pending)
**Applies to**: `fizzy-claude`, `fizzy-codex`, `fizzy-gemini` (when active), and the CEO (Timm) as final ratifier.
**Scope**: defines what a round is, the types of rounds, the required inputs/outputs, and how rounds converge and lock.

This is a process spec. It does not define Beads discipline (see `skills/bd-discipline.md`), session lifecycle (see `skills/session-lifecycle.md`), or documentation placement (see `skills/documentation-hierarchy.md`).

---

## 1) Purpose & scope

Rounds exist to make progress **observable, auditable, and convergent**.

A round is the smallest unit of work we accept as “real progress” in the 20-round prep program and beyond.

### 1.1 What a round IS

A round is a discrete unit of work with:

- **Pre-defined input** (what the drafter is reacting to)
- **Pre-defined output** (an artifact)
- **Pre-defined acceptance criteria** (AC) that a peer can evaluate
- **A convergence mechanism** (<= 8 iterations per topic/round; then narrow or escalate)

### 1.2 What a round IS NOT

A round is not:

- Free-form exploration with no deliverable
- “We discussed X” without an artifact
- A timebox with no output
- A way to silently scope-creep mid-stream

If we feel tempted to do any of the above, stop and re-define the round.

---

## 2) Round taxonomy

We use explicit round types to prevent mixing “thinking” and “building”.

### 2.1 Planning rounds (`P1`–`P10`)

Purpose: discovery, grounding, threat modeling, UX mapping, data mapping, brainstorming.

Outputs: concrete notes and decisions that the spec rounds can rely on.

- Primary artifact location: `llm/notes/`
- Secondary artifacts: `docs/` (if humans should read it), `skills/` (if it’s a procedure)

### 2.2 Spec rounds (`S1`–`S10`)

Purpose: produce **perfect beads** (issues) that are ready for implementation with minimal ambiguity.

Outputs: Beads issues with complete structure (title/body/AC/links/dep graph/notes pointers as required).

- Primary artifact location: `.beads/` (via `bd create` / `bd update`)
- Supporting notes: `llm/notes/` (referenced from the bead)

### 2.3 Implementation rounds (`I1+`)

Purpose: build the product per the ratified specs.

Outputs: code + tests + documentation updates as required, shipped behind the proper gates.

- Primary artifact location: codebase + tests
- Supporting artifacts: `docs/` (when it’s human-facing), `skills/` (when it’s a new procedure)

### 2.4 Plumbing rounds (`R0`, `R-1`, etc.)

Purpose: out-of-band fixes that unblock the program (tooling, environment, broken state).

Outputs: a concrete fix + a write-up (so we don’t regress).

- Primary artifact location: depends on the fix
- Required write-up: `llm/notes/<rX-topic>.md` and a `llm/LOG.md` entry

Plumbing rounds are exceptions and must be clearly labeled as such.

---

## 3) Canonical round structure (kickoff → lock)

Each round follows the same lifecycle.

### 3.1 Kickoff

The drafter must provide:

- Round ID (e.g., `P3-fizzy-data-mapping`)
- The **input** (links, files, issues, constraints)
- The **output type** (what artifact will be produced)
- The **acceptance criteria** (AC) in bullet form

If AC is not clear at kickoff, the round does not start.

### 3.2 Work (drafter produces v1)

The drafter produces v1 of the artifact:

- a file in `skills/`, `docs/`, or `llm/notes/`, OR
- a Beads issue update (spec), OR
- a code change + tests (implementation)

### 3.3 Review (peer feedback)

Peer feedback is sent via:

- tmux (see `skills/tmux-dispatch.md`)
- appended to `llm/LOG.md` by the sender (see `llm/README.md`)

Feedback must be **concrete**:

- specific edits (“change X to Y”)
- missing sections
- ambiguous AC
- contradictions with RoE / hierarchy

### 3.4 Iterate (<= 8 back-and-forths)

We iterate within the budget:

- <= 8 rounds per topic (see RoE)
- If exhausted: narrow scope, seek a third lens, or escalate to CEO

### 3.5 Converge (explicit signal)

When an agent agrees the artifact is ready to lock, they send:

`[FROM→TO <round-id>: agreed]`

Example:

`[CODEX→CLAUDE RoE-3: agreed]`

### 3.6 Lock (commit)

After both sides have sent the agreed signal:

- commit the artifact
- push the branch
- move to the next topic/round

The locker should ensure the convergence signal is present in `llm/LOG.md` before committing.

---

## 4) Deliverable requirements (non-negotiable)

Every round must produce a concrete artifact. Valid artifacts are:

1. A file in `skills/` (procedures)  
2. A file in `docs/` (human-facing docs, ADRs)  
3. A file in `llm/notes/` (task-specific design notes / research dumps)  
4. A Beads update (issue created/updated with required structure)  
5. A code change + tests (implementation work)  

Invalid outcomes:

- “We discussed it”
- “We brainstormed”
- “We’ll do it later” without a bead capturing it

---

## 5) Acceptance criteria (AC) template

AC must be defined before work starts. AC should be:

- unambiguous
- verifiable
- grounded in files/commands
- small enough that a peer can review it quickly

Avoid AC like “convert all pages” or “make it perfect”.

### 5.1 Minimal AC template

Use this shape in kickoff messages:

- **Artifact**: `path/to/file.md` (or bead id)
- **Required sections**: list them
- **Constraints**: e.g. “no code changes”, “no new locations”, “<= N bullets”, “append to LOG”
- **Review checks**: how peer verifies (e.g. “file renders”, “has decision tree”, “includes convergence signal”)

---

## 6) Round numbering & naming

### 6.1 Format

- Planning: `P<N>-<topic>`
- Spec: `S<N>-<topic>`
- Implementation: `I<N>-<topic>`
- Plumbing: `R<N>-<topic>` (or `R0` without a topic if extremely narrow)

Topic naming:

- kebab-case
- short but specific

Examples:

- `P3-fizzy-data-mapping`
- `S7-beads-to-fizzy-card-model`
- `I12-board-columns-ui`
- `R0-dolt-cleanup`

### 6.2 Round-to-round linking

Each round’s output should explicitly state:

- what round it belongs to
- what the next round’s input is

At minimum, the drafter adds a 1–2 line “handoff” at the end of the artifact or in `llm/LOG.md`.

---

## 7) Artifact location matrix (by round type)

| Round type | Primary output | Typical location | Notes |
|---|---|---|---|
| Planning (`P`) | research + decisions | `llm/notes/` | Promote durable procedures to `skills/`; promote durable “one-liners” to `bd remember` |
| Spec (`S`) | “perfect bead” | `.beads/` via `bd` | Use `llm/notes/` for deep context; link it from the bead |
| Implementation (`I`) | code + tests | repo code | Update `docs/`/`skills/` as needed |
| Plumbing (`R`) | unblocker fix + write-up | varies + `llm/notes/` | Must be auditable and reversible where possible |

---

## 8) Multi-round dependencies

Default dependency chain:

- Spec rounds depend on planning rounds.
- Implementation depends on ratified spec rounds.

Examples:

- `S5` should not start until the relevant planning groundwork exists (often “P complete”).
- Implementation should not start until the relevant spec is ratified and the bead is ready/claimed.

If we must violate this ordering, label it explicitly as a plumbing exception and record why.

---

## 9) Round handoff (output becomes input)

At the end of every round, the drafter must provide:

- what changed
- what remains open
- what the next round should do
- what artifacts the next round must read first

The handoff can be:

- a short “Handoff” section in the artifact, and/or
- an explicit handoff message in `llm/LOG.md`

---

## 10) Failure modes (and how to respond)

### 10.1 Budget exhausted (more than 8 iterations)

Response order:

1. Narrow scope to the minimal ratifiable version
2. Seek a third written lens (council pattern)
3. Escalate to CEO with options + tradeoffs

### 10.2 Scope creep mid-round

If new work appears mid-round:

- capture it as a new round / new bead
- do not silently expand the current round

### 10.3 Ambiguous AC discovered after kickoff

Stop work and re-AC the round:

- drafter proposes updated AC
- peer ACKs
- then continue

### 10.4 No artifact

If a round ends with no artifact:

- treat it as a failed round
- immediately define a replacement round with concrete deliverables

---

## 11) Convergence signal

When Claude and Codex both agree RoE-3 is complete, each sends the other:

`[FROM→TO RoE-3: agreed]`

After both signals are logged in `llm/LOG.md`, this file is locked for topic 3 and we move to topic 4 (`bd-discipline.md`).

