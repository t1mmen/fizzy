# `skills/` — single source of truth for agent procedures (PROJECT-LOCAL)

Reusable procedures, rules of engagement, brief/signoff templates, and cross-session conventions for the Fizzy+Beads agent team (`fizzy-claude`, `fizzy-codex`, `fizzy-gemini`).

**Scope:** project-local **only**. Skills live in this repo, are version-controlled, ship with every clone. **Do NOT push these into `~/.claude/skills/` or `~/.codex/skills/` user-global** — they belong to the Fizzy project, not the user.

**Layout (verified working for both agents):**

```
fizzy/
  skills/                     ← single source of truth, in git
    README.md
    tmux-dispatch.md
    rules-of-engagement.md    (TBD — produced via R0 RoE brainstorm)
    brief-template.md         (TBD)
    signoff-template.md       (TBD)
    bd-discipline.md          (TBD)
    ...
  .claude/skills/  →  ../skills    (symlink; Claude reads project-local)
  .codex/skills/   →  ../skills    (symlink; Codex reads project-local)
```

For `fizzy-gemini` we'll add `.gemini/skills/ → ../skills` when that session is provisioned.

**Conventions:**
- One skill per file: `<kebab-case-name>.md`
- Plain Markdown (no required YAML frontmatter — both Claude and Codex symlink loaders accept flat markdown)
- Short, actionable, evergreen — no per-round artifacts (per-round work goes in `llm/notes/`)
- Skills describe HOW we do work; per-task design notes describe WHAT we are doing

**Adding a skill:**
1. Create `./skills/<name>.md`
2. Both agents see it immediately via their symlinks; no sync, no script
3. Reference it from `AGENTS.md` if a wider audience needs to discover it
