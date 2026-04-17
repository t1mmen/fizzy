# Session Lifecycle — open/close, interrupts, and security posture

**Status**: draft (RoE-7 pending)
**Applies to**: `fizzy-claude`, `fizzy-codex`, `fizzy-gemini`, and any human contributor.
**Scope**: session open/close mechanics and guardrails for safe day-to-day operation in this repo.

This file is the canonical home for:

- the “session bookends” (open + close checklists)
- interrupt handling (especially CEO interrupts)
- security/secrets/external-communications rules (deferred from RoE-1 §8.4)

Cross-links:

- Beads discipline references these bookends but does not duplicate them: `skills/bd-discipline.md` §9
- Documentation placement rules: `skills/documentation-hierarchy.md`
- Round mechanics: `skills/round-protocol.md`
- Brief/signoff templates: `skills/workflow-templates.md`

---

## 1) Purpose & scope

Sessions are where good process either compounds or decays. The goal of this skill is to make it hard to:

- lose context after compaction or a fresh session
- strand work locally (un-pushed branches)
- “forget” to claim work in Beads
- leak secrets into git history or logs

This is the operating checklist we follow every time we start/stop work.

---

## 2) Session open (mandatory checklist)

### 2.1 Recover context

Always start by reading the latest collaboration history and current state:

```bash
tail -n 100 llm/LOG.md
cat llm/claude-state.md
cat llm/codex-state.md
cat llm/gemini-state.md
```

If you are resuming after compaction, treat `llm/LOG.md` as authoritative.

### 2.2 Verify skills wiring (project-local only)

Confirm project-local skills are correctly mounted for all agents:

```bash
readlink .claude/skills
readlink .codex/skills
readlink .gemini/skills
```

Expected value for each: `../skills`

If a symlink is wrong, treat it as a plumbing issue (create a bead and fix it).

### 2.3 Refresh Beads context (do not assume auto-run)

`bd prime` is mandatory at session open. Do not rely on hooks or tool autoload.

```bash
bd prime
bd list
bd ready
```

### 2.4 Declare your “Now” state

Update your state file to make your intent obvious to peers:

- `llm/claude-state.md`
- `llm/codex-state.md`
- `llm/gemini-state.md`

Minimum fields:

- what you are doing now
- what bead/round you are working on
- blockers / questions for peers

### 2.5 Pick up work (only after you’re grounded)

If there is an available bead:

```bash
bd ready
bd show <id>
bd update <id> --claim
```

If you need to create work:

```bash
bd create --title "..." --description "..." --type task
```

---

## 3) Session close (mandatory checklist)

This section is the canonical version of the CEO session-close directive.

### 3.1 Capture follow-ups (never leave work implicit)

If you discovered new work:

```bash
bd create --title "..." --description "..." --type task
```

If a bead is partially complete, add an explicit stopping point:

```bash
bd update <id> --notes "Stopped at: <what is true right now>. Next: <next concrete step>."
```

### 3.2 Update bead status

- Close finished work:
  ```bash
  bd close <id>
  ```
- If you are handing off:
  ```bash
  bd update <id> --assignee=<peer>
  ```
  Then tmux ping the peer and update your state file.

### 3.3 Run quality gates (only if code changed)

If you changed code (not just docs/skills/logs):

```bash
bin/ci
```

If `bin/ci` fails for reasons unrelated to your changes, file a bead and ping the CEO rather than “papering over” the gate.

### 3.4 Push to remote (mandatory; work is not done until pushed)

```bash
git pull --rebase
bd dolt push
git push
git status
```

Notes:

- If `git pull --rebase` produces conflicts: resolve them in-place (do not `git rebase --abort` and try later — that strands the conflict for the next agent). When in doubt about a conflict, ping the peer who likely caused the divergence and resolve together.
- `bd dolt push` is best-effort right now (known broken against the configured `git+https://…` remote; see `llm/notes/r0-dolt-cleanup.md` §5). If it fails, capture the error in `llm/LOG.md` and proceed with `git push` (load-bearing for cross-machine visibility).
- `git status` must show you are up to date with the remote branch.

### 3.5 Final state + peer notification

- Update your `llm/<agent>-state.md` with end-of-session status.
- If something is waiting on a peer, tmux ping with the bead id and the specific ask.

---

## 4) Session interrupt (CEO drops in)

If the CEO interrupts mid-work:

1. Complete the in-flight tool call cleanly (no abandonment mid-mutation).
2. Attend to the CEO message immediately.
3. If the interrupt changes scope, update `llm/<agent>-state.md` before resuming.

This codifies RoE-1 §8.6.

---

## 5) Multi-day continuation

Work often spans days. The continuity contract is:

- The bead remains the canonical record of “what exists / what remains”.
- Your state file describes what you are doing **today**.
- Durable learnings go into `bd remember` once they prove reusable.

When resuming a bead after time away:

```bash
bd show <id>
bd history <id>
```

Then write a short “resume note” in the bead if needed:

```bash
bd update <id> --notes "Resuming on YYYY-MM-DD: <what I’m doing next>."
```

---

## 6) Multi-agent ownership across sessions

### 6.1 Ownership is explicit

- Claimed bead = owned bead.
- Do not work “under the table” on someone else’s bead without ping-ACK.

### 6.2 Picking up after an idle peer

If a bead is in progress but appears abandoned:

```bash
bd stale --status in_progress --days 1   # tighten to our cadence (hours/days, not weeks)
bd show <id>
```

(`bd stale --days 7` is the default; we operate on a much tighter loop, so 1–2 days is usually the right cutoff for "abandoned". Tune per situation.)

Then:

- Ping the owner via tmux.
- If no response in a reasonable window, reassign and note why:
  ```bash
  bd update <id> --assignee=<you> --notes "Reassigned due to inactivity; pinged <peer> on YYYY-MM-DD."
  ```

### 6.3 Hand-offs must be two-channel

A hand-off is only complete when all are true:

- bead assignee is updated
- tmux ping is sent
- handoff is logged in `llm/LOG.md`

---

## 7) Security, secrets, and external communications (non-negotiable)

This is the fully elaborated form of the RoE-1 §8.4 stub.

### 7.1 Never log secrets

- Never paste API keys, tokens, passwords, or private URLs into:
  - `llm/LOG.md`
  - `llm/notes/`
  - Beads notes/comments
  - commit messages

If a credential must be referenced, use a redacted placeholder and the storage system name (e.g., “stored in 1Password under …”).

### 7.2 Never push credentials (staged-change hygiene)

Before committing (especially after touching config files), check staged content:

```bash
git diff --cached
```

Treat this as required process, not optional.

### 7.3 Defense in depth (CI is not your only safety net)

- `bin/ci` runs `bin/gitleaks-audit`, but do not rely on it as the only line of defense.
- Beads hooks are installed in this repo (`bd hooks list` shows hooks present). Keep them installed.

Useful commands:

```bash
bd hooks list
bin/gitleaks-audit
```

### 7.4 External services — side effects vs read-only

External interactions split into two categories:

**A) Side-effecting external actions (CEO sign-off required)**

Examples:

- Deploys (Kamal)
- Sending outbound Slack messages or emails
- Creating/updating third-party tickets (Jira/Linear/GitHub issues) *as an action*, not read-only viewing
- Writing to production databases or production infra

Rule: do not perform these without explicit CEO sign-off.

**B) Read-only external actions (allowed)**

Examples:

- Documentation fetches (Context7, web browsing)
- GitHub browsing (read-only)

Rule: allowed, but do not leak secrets during the process.

### 7.5 If a secret accidentally lands in git history

Priority order:

1. **Rotate the secret first** (assume compromise).
2. Determine whether it was pushed:
   - If not pushed: fix locally (amend/rewrite) and proceed.
   - If pushed to `dev` (our trunk): peers may have already pulled. **Do not force-push** without coordinating with all active agents (`fizzy-claude`, `fizzy-codex`, `fizzy-gemini`) AND CEO approval. The safer path is usually to leave history intact + ensure the rotated secret is the only one in use; force-push is a last resort.
   - If pushed to `main`: never force-push without explicit CEO sign-off.

Always document the incident in `llm/LOG.md` with redaction (do not copy the secret), and file a bead if follow-up work is required.

---

## 8) Failure modes (what NOT to do)

- ❌ Start work without reading recent `llm/LOG.md` context (tail first).
- ❌ Skip `bd prime` at session open.
- ❌ Leave a bead in an ambiguous “half state” (no notes, no handoff, no close).
- ❌ Abandon an in-flight tool call on a CEO interrupt.
- ❌ Commit/push without reviewing `git diff --cached`.
- ❌ Log credentials (even temporarily) in chat/log/notes.
- ❌ Hand off without updating bead assignee + tmux ping + LOG entry.
- ❌ Leave local work unpushed at session end (“ready to push” is not done).

---

## 9) Convergence signal (RoE-7)

When all active agents agree RoE-7 is complete, each sends the others:

`[FROM→TO RoE-7: agreed]`

After all signals are present in `llm/LOG.md`, this file is locked and the CEO ratification phase begins.

**CEO ratification readout**: after lock, Claude assembles a batch summary in `llm/notes/roe-batch-ratification-readout.md` and pings the CEO with `[CLAUDE→CEO RoE-batch-ready]`.

