# Beads Discipline — `bd` workflow rules

**Status**: draft (RoE-4 pending)
**Applies to**: `fizzy-claude`, `fizzy-codex`, `fizzy-gemini`, and all future agents.
**Scope**: how we use `bd` (Beads) for task tracking. This is not the spec for what Beads *is* (see `llm/notes/grounding-codex.md` and Beads upstream); this is the per-Timm operating rules for *how we use it* in this program.

This file refers to but does not duplicate:
- `skills/round-protocol.md` (rounds and their relationship to beads)
- `skills/documentation-hierarchy.md` (where notes/memories live)
- `skills/session-lifecycle.md` (session open/close mechanics) — to be drafted

---

## 1) Ground truths

These are non-negotiable facts about Beads in this repo:

- Backend: **Dolt** (server mode), at `.beads/dolt/fizzy`. R0 cleanup ratified this; see `llm/notes/r0-dolt-cleanup.md`.
- **Schema is immutable.** We do not add columns, change types, or alter constraints to the `issues`, `dependencies`, or any other Beads table. We conform to Beads as it ships.
- Issue ID prefix: `fizzy-<suffix>` (configurable in `.beads/config.yaml`; do not change).
- Single project DB per install (per CEO Q3 ii). No federation in V1.
- `bd dolt push` is for **off-machine backup** of the Beads DB. Cross-agent collaboration in this repo works without it — all agents read the same local Dolt server. **Currently broken** (`fatal: this operation must be run in a work tree` against the configured `git+https://…` remote — see `llm/notes/r0-dolt-cleanup.md` §5). Treat `bd dolt push` as **best-effort**; **`git push` is load-bearing** for cross-machine visibility (skills, notes, LOG, code) until the dolt remote is fixed.

---

## 2) The "every notable work" rule

Per CEO standing directive:

> Every notable work item exists in Beads. No exceptions.

Operationalized:

- **Yes, file a bead for**: every Planning round, every Spec round, every Implementation round, every Plumbing round, every research dump that has a name, every product feature, every bug, every chore, every architectural decision (one bead per ADR + the actual ADR file in `docs/decisions/`).
- **No, do not file a bead for**: tmux pings between agents, single-file typo fixes inside an already-claimed bead, or anything covered by an active bead's scope.

When in doubt, file. More beads than intuition suggests is healthy.

---

## 3) Forbidden alternatives

The following are **banned** as task-tracking mechanisms in this repo:

- ❌ `TodoWrite` / `TaskCreate` (Claude built-in tools) — use `bd create` instead.
- ❌ Markdown TODO lists in any file (`TODO.md`, inline `## TODO` sections, `// TODO` in code unless tied to a bead id like `# TODO(fizzy-xyz):`)
- ❌ `MEMORY.md` files for cross-session knowledge — use `bd remember` instead.
- ❌ Any per-agent task store (e.g., Claude's task tool, Codex's planner) as the canonical record. They may be used as scratch *for one turn*, but the canonical record is always Beads.

---

## 4) Issue lifecycle

The standard flow:

```
bd ready                        ← find unblocked issues you could pick up
bd show <id>                    ← read the full issue
bd update <id> --claim          ← claim ownership (sets in_progress + assigns to you)
work happens                    ← code, notes, design — owner controls scope
bd update <id> --notes "..."    ← add interim notes if useful
bd update <id> --comment "..."  ← add a discussion comment if collaborating
bd close <id>                   ← mark complete (or close many at once: bd close <id1> <id2>)
bd close <id> --reason "..."    ← if closing without completion (won't fix, duplicate, etc.)
```

Hand-off:

```
bd update <id> --assignee=<peer>   ← reassign to another agent
+ tmux ping the peer with the bead id
+ update your llm/<agent>-state.md to reflect handoff
```

Block on a peer:

```
bd update <id> --notes "blocked on <reason>, pinged <peer>"
+ tmux ping the peer
+ status remains in_progress (or move to blocked if `bd` supports the status)
```

---

## 5) Perfect-bead structure (the spec target)

Per CEO Q6: spec rounds produce "perfect beads following the perfect bead structure". Every bead created during a Spec round (`S1`–`S10`) must have:

1. **Title** — verb-led, specific, file-scoped if applicable. Bad: "Improve UI". Good: "Migrate `Card` model to read from `bd issues` table via `BeadsRecord` adapter".
2. **Description (`--description`)** — **the WHY**. What problem does this solve? What user-visible behavior changes? What is the business/technical motivation?
3. **Design (`--design`)** — **the HOW**. Concrete approach: which files, which classes, which methods, which migration steps. Reference existing code paths. Pseudocode/flowcharts welcome.
4. **Acceptance criteria (`--acceptance`)** — **the WHAT** (verifiable). Bullet list a peer can run/test against. File-grounded ("file X compiles", "command Y returns Z", "test file T passes"). NEVER "convert all pages" or "make it work".
5. **Notes (`--notes`)** — supplementary context, links to research dumps in `llm/notes/`, decisions made along the way.
6. **Type (`--type`)** — `task` | `bug` | `feature` | `epic` | `chore` | `decision`. Default: `task`.
7. **Priority (`--priority`)** — `0` (critical/P0) … `4` (backlog/P4). Default: `2` (medium).
8. **Labels (`--labels`)** — kebab-case, multiple. Use existing labels before inventing new ones (`bd list --json | jq '.[].labels'`).
9. **Assignee (`--assignee`)** — `fizzy-claude`, `fizzy-codex`, `fizzy-gemini`, or unassigned (open for `bd ready` claim).
10. **Dependencies (`bd dep add`)** — wired correctly, with the right relationship type (see §6).
11. **Estimate (`--estimate`)** — minutes integer, optional but encouraged for spec rounds.

Validation: `bd create --validate` checks for required sections; `bd lint` checks existing issues.

---

## 6) Dependency types (10 of them)

Beads supports 10 relationship types. Two commands:

- `bd link <a> <b> --type <type>` — **shortcut form**, only supports the 5 most common types: `blocks | tracks | related | parent-child | discovered-from` (verified via `bd link --help`).
- `bd dep add <a> <b> --type <type>` — **full form**, supports all 10 types.

### 6.1 Direction convention (read carefully)

```
bd dep add B A --type blocks     →  A blocks B   (B depends on A)
bd dep add child parent --type parent-child  →  parent is parent of child
bd dep add new old --type supersedes  →  new supersedes old
```

The first argument is the *subject* of the relationship; the second is the *target*. When in doubt, run `bd show <id>` after adding and confirm the rendered direction matches your intent.

### 6.2 Type table

| Type | Command form | Meaning | Use when |
|---|---|---|---|
| `blocks` | `bd link` or `bd dep add` | A blocks B (B can't start until A done) | Hard sequencing |
| `tracks` | `bd link` or `bd dep add` | A tracks B (loose coupling, A wants visibility) | Cross-team awareness |
| `related` | `bd link` or `bd dep add` | A and B are bidirectionally related | Same surface, different angles |
| `parent-child` | `bd link` or `bd dep add` | A is parent of B | Epic → tasks; sub-decomposition |
| `discovered-from` | `bd link` or `bd dep add` | B was discovered while working A | Spec round emits child beads |
| `until` | `bd dep add` only | A is valid until B happens | Temporary measures |
| `caused-by` | `bd dep add` only | A is caused by B | Bug → root cause |
| `validates` | `bd dep add` only | A validates B (B's AC verified by A's outcome) | Test/verification beads |
| `relates-to` | `bd dep add` only | Generic association (when none of the above fit) | Last resort |
| `supersedes` | `bd dep add` only | A supersedes B (B is obsolete) | Replaced approaches |

Pick the most specific type. Don't default to `blocks` for everything.

---

## 7) Memories (`bd remember` vs notes vs skills)

Per `skills/documentation-hierarchy.md` §2.3:

- `bd remember "<text>"` — cross-session learnings, one-liners, "fact about this codebase". Survives compaction. Searchable via `bd memories <keyword>` and `bd recall`.
- `llm/notes/<bd-id>.md` — per-task design notes, scratch work, research dumps. Tied to a specific bead.
- `skills/<name>.md` — evergreen procedures (HOW we operate). Cross-task, cross-round.

Decision tree:

```
Is it a procedure that other agents should follow?     → skills/
Is it a one-liner that should survive compaction?      → bd remember
Is it task-specific design or research?                → llm/notes/<bead-id>.md
```

---

## 8) Conventions

### 8.1 Naming

- Issue prefix: `fizzy-<suffix>` (auto-generated by bd)
- Topic suffix in round labels: kebab-case, short, specific (e.g., `S5-card-model-adapter`)
- Labels: kebab-case (e.g., `data-model`, `auth`, `card-model`, `playwright-coverage`)

### 8.2 Priority levels

- `0` (P0) — critical, must do now (production bug, blocking deploy)
- `1` (P1) — high, do this iteration (V1 must-have)
- `2` (P2) — medium, default
- `3` (P3) — low, do when time
- `4` (P4) — backlog, may never do

Do not use words like "high", "medium", "low" — `bd` rejects them. Use the integer or `P0`–`P4`.

### 8.3 Issue types

- `task` — generic work item (default)
- `bug` — defect in existing behavior
- `feature` — new product capability
- `epic` — multi-bead container (use `parent-child` deps to its children)
- `chore` — maintenance, refactoring, plumbing
- `decision` — ADR-tracked architectural decision (paired with file in `docs/decisions/`)

---

## 9) Session bookends

### 9.1 Session open

Run `bd prime` explicitly at the start of every session — do **not** rely on auto-execution by hooks. Some integrations may run it for you, but the contract is "you ran it" and you should confirm by inspecting its output.

```bash
bd prime                  # MANDATORY at session open — do not assume auto-runs
bd ready                  # find available work
bd show <id>              # read the issue you'll work on
bd update <id> --claim    # take ownership
```

### 9.2 Session close (per CEO directive — mandatory)

```bash
# 1. File any newly-discovered followups
bd create --title "..." --description "..." --type task

# 2. Run quality gates if code changed
bin/ci   # full suite (rubocop, brakeman, tests, system tests)

# 3. Update issue status
bd close <id> [<id> ...]              # finished work
bd update <id> --notes "stopped at X" # in-progress

# 4. PUSH TO REMOTE — MANDATORY, work is NOT done until this succeeds
git pull --rebase
bd dolt push
git push
git status   # MUST show "up to date with origin"
```

If `bd dolt push` fails (currently a known issue per `llm/notes/r0-dolt-cleanup.md` §5), document it and proceed — git push is the load-bearing step for cross-agent visibility.

---

## 10) Multi-agent ownership

- A bead is **owned** by whoever last ran `bd update <id> --claim` (or by `--assignee=`).
- Owner has authority to edit fields, add notes, close, or hand off.
- Non-owners may add `--comment` for discussion but should not mutate other fields without ping-ACK.
- Ping-before-edit also applies to bead state when in doubt.

When two agents are working in parallel on related beads:

1. Use `parent-child` or `related` deps to make the relationship explicit.
2. Each owner stays in their own lane (their own bead's scope).
3. Cross-cutting concerns get their own bead with `discovered-from` deps to both originating beads.

---

## 11) Failure modes

- ❌ Working without a claimed bead. Reclaim or create one *before* meaningful work starts.
- ❌ Closing a bead without completing the AC or filing a follow-up bead for what's left.
- ❌ "Quick fix" beads with no description — every bead has a WHY.
- ❌ Using `--description` for design notes; `--design` is its own field for a reason.
- ❌ Creating duplicate beads — search first (`bd list --status=open` and `bd search <terms>`).
- ❌ Putting cross-session learnings into `llm/<agent>-state.md` instead of `bd remember`.
- ❌ Pushing code without running `bin/ci` first when code changed.
- ❌ Closing a session without `git push` — work is not complete until pushed.

---

## 12) Convergence signal

When Claude and Codex (and Gemini if active) all agree RoE-4 is complete, each sends the others:

`[FROM→TO RoE-4: agreed]`

After all signals are in `llm/LOG.md`, this file is locked and we move to topic 5 (`workflow-templates.md`).
