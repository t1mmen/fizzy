# Documentation Hierarchy — where each kind of artifact lives

**Status**: draft (RoE-2 pending)
**Applies to**: every agent and human contributor working in this repo.
**Scope**: this file decides *where* content goes. It does not decide *what* the content says or *how* to format it (those live in topic-specific skills).

If a contributor is unsure where something belongs, the decision tree in §3 is authoritative. When in doubt, ask the peer agent or the CEO before writing — content in the wrong place rots faster than missing content.

---

## 1) Why this matters

Without a strict hierarchy:
- The same procedure shows up in three places and they drift.
- Cross-session learnings end up in chat scrollback and are lost.
- Public-facing docs get mixed with agent-only scratch and confuse contributors.
- New agents (or new humans) don't know where to look.

The hierarchy is enforced by convention, not by code. Both agents are responsible for catching drift in PR review.

---

## 2) The seven canonical locations

Each location has a single audience and a single purpose. **One audience = one location**. Cross-references between locations are encouraged; content duplication is forbidden.

| Location | Audience | Purpose | Source of truth for |
|---|---|---|---|
| `skills/` | Agent team (Claude, Codex, Gemini) | Evergreen procedures — *how we work* | RoE, brief/signoff templates, per-tool dispatch protocols, test discipline, branch workflow, session lifecycle |
| `llm/` | Agent team (intra-session collaboration) | Active collaboration scratch | Message log, per-agent state, per-task design notes |
| `.beads/` | Agent team + future humans | Canonical task graph + cross-session memory | Issue tracker (Dolt-backed, schema-immutable), `bd memories` |
| `docs/` | Humans (contributors, future maintainers, OSS users) | Public project documentation | Architecture overviews, contributor guides, ADRs |
| `AGENTS.md` | All AI tools that auto-load it | Root-level project instructions | Build/test commands, architecture overview, top-level conventions, pointer to `skills/` index |
| `CLAUDE.md` | Claude Code specifically | Claude-specific instructions | Currently a thin pointer to `AGENTS.md` + `STYLE.md` |
| `STYLE.md` | Anyone writing code | Coding conventions | Rails/Ruby idioms, naming, formatting |

### 2.1 `skills/` — evergreen procedures (project-local)

- Single source of truth for *how we operate*.
- Project-local; symlinked into `.claude/skills/` and `.codex/skills/`. Never push to `~/.claude/skills/` or `~/.codex/skills/` user-global.
- One skill per file: `<kebab-case-name>.md`.
- Plain Markdown; no YAML frontmatter required (both Claude and Codex accept flat markdown via the symlink).
- Skills describe procedures that should survive across sessions, branches, and contributors. If a procedure is only relevant to one task, it belongs in `llm/notes/`, not here.
- Adding a skill = create the file; both agents see it immediately.

### 2.2 `llm/` — agent collaboration workspace (durable, internal)

- `llm/README.md` — collaboration protocol overview.
- `llm/LOG.md` — append-only timestamped message log between agents. Sender appends. **Never delete** entries; the log is its own audit trail.
- `llm/claude-state.md`, `llm/codex-state.md`, `llm/gemini-state.md` — current-state files (what the agent is doing now, blockers, open questions).
- `llm/notes/<bd-id-or-topic-slug>.md` — per-task design notes, scratch work, research dumps tied to a specific bead or topic.
- `llm/` is committed to git for durable auditability — it is **not** ephemeral. It is *internal collaboration workspace*, not canonical product documentation. Promote cross-session learnings to `bd remember` (memories) or to `skills/` (procedures) as they prove durable.

### 2.3 `.beads/` — task graph + cross-session memory

- Canonical task tracker, backed by Dolt. **Schema is immutable** (we conform to it; we do not mutate it).
- All notable work gets a bead (per CEO directive: every notable work item exists in beads).
- `bd remember "<text>"` is the canonical mechanism for cross-session knowledge that should survive compaction or session restart. Query with `bd memories <keyword>` and `bd recall`.
- See `skills/bd-discipline.md` (to be drafted) for the per-Timm beads workflow.

### 2.4 `docs/` — public project documentation

- Anything a human contributor or open-source user would read to understand or extend the project.
- Architecture overviews, design rationale, deployment guides, contributor onboarding.
- ADRs (Architectural Decision Records) live in `docs/decisions/<NNNN>-<slug>.md` (sequential 4-digit number prefix). ADRs record *why* we made a major architectural choice; they are immutable once landed (superseded ADRs get a new ADR pointing to them).
- Public-facing READMEs at the repo root (`README.md`, `CONTRIBUTING.md`) link into `docs/` for depth.

### 2.5 `AGENTS.md` — root-level AI-tool instructions

- Auto-loaded by Codex (and merged with `~/.codex/AGENTS.md`).
- Auto-loaded by Claude via the `@AGENTS.md` import in `CLAUDE.md`.
- Should contain: build/test commands, architecture overview, multi-tenancy notes, beads workflow pointer, **a one-line pointer to `skills/README.md` as the index of agent procedures**.
- Should NOT contain: full skill content (that lives in `skills/`); per-task notes (that live in `llm/notes/`); detailed coding rules (that live in `STYLE.md`).

### 2.6 `CLAUDE.md` — Claude-specific instructions

- Currently a thin pointer: `@AGENTS.md` + `@STYLE.md`. Keep it that way unless we find a Claude-specific instruction that genuinely doesn't apply to other agents.
- Auto-managed sections (e.g., the BEADS INTEGRATION block injected by the beads hooks) are out of scope for editing — leave them as-is.

### 2.7 `STYLE.md` — coding conventions

- Ruby/Rails style for this project. Already authored upstream.
- Project-specific style additions go here; do not duplicate language-general best practices that any Rails developer already knows.

---

## 3) Decision tree — "where does this go?"

```
Is the content a procedure for HOW we operate, that should
survive across tasks, branches, sessions?
  ├── YES ──→ skills/<name>.md
  └── NO ──→ continue

Is the content a per-task design note, scratch work, or
research dump tied to one specific task or bead?
  ├── YES ──→ llm/notes/<bd-id-or-topic>.md
  └── NO ──→ continue

Is the content a one-liner learning that should survive
context compaction or a fresh session?
  ├── YES ──→ bd remember "<text>"
  └── NO ──→ continue

Is the content a message from one agent to another?
  ├── YES ──→ tmux send-keys + append to llm/LOG.md
  └── NO ──→ continue

Is the content the agent's "current state" snapshot
(what I'm doing now, blockers, open questions)?
  ├── YES ──→ llm/<agent>-state.md
  └── NO ──→ continue

Is the content public-facing documentation a human
contributor or OSS user would read?
  ├── YES, narrative/architectural ──→ docs/<topic>/<file>.md
  ├── YES, decision rationale ──→ docs/decisions/<NNNN>-<slug>.md (ADR)
  └── NO ──→ continue

Is the content a top-level instruction for AI tools loading
this repo?
  ├── YES ──→ AGENTS.md
  └── NO ──→ continue

Is the content a coding/style convention?
  ├── YES ──→ STYLE.md
  └── NO ──→ STOP. Ask peer agent or CEO. Do not invent
            a new location.
```

---

## 4) Anti-duplication rule

- The same content **cannot** exist in two locations. Cross-link instead.
- If a piece of guidance feels like it belongs in two places, ask: *which location's audience is the primary reader?* That location wins; the other location links to it with a one-line pointer (e.g., "see `skills/foo.md` for the procedure").
- Pre-existing duplications discovered during work should be reconciled in the same change that touches them — never silently leave drift.

---

## 5) Naming conventions

| Location | File pattern | Notes |
|---|---|---|
| `skills/` | `<kebab-case>.md` | E.g. `tmux-dispatch.md`, `bd-discipline.md` |
| `llm/notes/` | `<bd-id>.md` or `<kebab-topic>.md` | E.g. `fizzy-jul.md`, `r0-dolt-cleanup.md` |
| `docs/` | `<topic>/<kebab>.md` | Organize by topic subdir |
| `docs/decisions/` | `NNNN-<slug>.md` | 4-digit sequential, e.g. `0001-dolt-as-task-source-of-truth.md` |
| beads memories | free-form text | Created via `bd remember "<text>"` |

---

## 6) Lifecycle

| Phase | Skills | llm/notes | llm/LOG.md | bd memories | docs / ADRs |
|---|---|---|---|---|---|
| Create | Anyone, anytime | Anyone, anytime | Sender appends per dispatch | `bd remember` | Per ADR/doc workflow |
| Modify | Ping-before-edit on shared files | Owner of the linked task | **Append-only — never edit prior entries** | Append-only via additional memories; old ones decay | ADRs immutable after land; new ADR supersedes |
| Archive | Delete (git history retains) | Keep; optionally prune; git history retains. Promote durable learnings to memories or skills before pruning. | **Never delete** — the log is its own audit trail | `bd forget` (rare) | Mark "Superseded by ADR-NNNN" |
| Audit | PR review | grep + git log | `grep` patterns like `\[FROM→TO\]`; full timestamped history | `bd memories <keyword>` | Periodic doc review |

---

## 7) Cross-links

- `AGENTS.md` → `skills/README.md` (one-line "see `skills/` for agent procedures")
- Each `skills/*.md` file may link to other skills via relative paths (`./<name>.md`)
- `llm/notes/<bd-id>.md` → references the bd issue: include the id in the filename and the file body
- `docs/decisions/<NNNN>-<slug>.md` → may reference skills, other ADRs, code paths

---

## 8) Failure modes (what NOT to do)

- ❌ Procedures in `llm/`. They belong in `skills/`.
- ❌ Per-task notes in `skills/`. They belong in `llm/notes/`.
- ❌ Cross-session learnings in agent state files. They belong in `bd remember`.
- ❌ Skill content inlined in `AGENTS.md`. Keep `AGENTS.md` as an index; skill content stays in `skills/`.
- ❌ Public project info in `llm/`. It belongs in `docs/` or `AGENTS.md`.
- ❌ ADRs without a sequential number prefix. They will not sort or reference cleanly.
- ❌ Modifying an ADR after it lands. Supersede with a new one instead.
- ❌ Pushing skills to user-global `~/.claude/skills/` or `~/.codex/skills/`. Skills are project-local only.
- ❌ Putting procedures or content in `.claude/` or `.codex/` directly. Those directories are *mountpoints/scaffolding* — they exist to host symlinks (`.claude/skills` → `../skills`, `.codex/skills` → `../skills`) and tool settings (`.claude/settings.json`). They are not canonical doc locations. Anything that looks like procedure or content belongs in `skills/`, `docs/`, or `llm/` per the decision tree.
- ❌ Editing or deleting prior entries in `llm/LOG.md`. Append-only is the contract.

---

## 9) Convergence signal

When Claude and Codex both agree RoE-2 is complete, each sends the other:

`[FROM→TO RoE-2: agreed]`

After both signals are logged in `llm/LOG.md`, this file is locked for topic 2 and we move to topic 3 (`round-protocol.md`).
