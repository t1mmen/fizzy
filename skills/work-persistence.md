# Work Persistence — never lose a deliverable

**Status**: locked from first-write (this skill is itself the response to a near-loss)
**Applies to**: every agent producing a deliverable file (`llm/notes/`, `skills/`, `docs/`, code, anything).

---

## 1) The rule

**Every deliverable file gets `git add` + `git commit` at first write.** Do not hold deliverables uncommitted through review cycles.

The commit message can say `WIP:` or `draft:` — the point is the file is in git's object database and survives any working-tree event (pull/rebase/clean/restart).

```bash
# Right after Write or initial Edit on a new deliverable:
git add llm/notes/p7-foo.md && git commit -m "WIP: P7 brief skeleton"
```

Subsequent edits (review iterations) get their own commits at meaningful checkpoints (e.g., "v2 with Codex round-2 fixes"). The lock commit is the FINAL commit, not the FIRST.

---

## 2) Why this exists (incident)

**2026-04-17 ~16:00 PDT — P5 deliverable lost from working tree.**

`llm/notes/p5-auth-bridging.md` was Written + Edited multiple times, reviewed by both fizzy-codex and fizzy-gemini, ratified 3-of-3. But it was **never `git add`-ed**. Between Codex's `[P5: agreed]` and Claude's lock commit, the file vanished from the working tree. Likely cause: Codex ran `git pull --rebase` or a similar git operation that removed untracked files (or the file got cleaned by some other means).

Recovery: Claude recreated the file from edit history + reviewer summaries. Content was restored, but the round took an extra ~10 minutes and risked content drift.

The fix: don't depend on the working tree for durability. **Git is the source of truth.**

---

## 3) Operational pattern

### 3.1 First-write commit

When you Write or first-Edit a deliverable file:

```bash
git add path/to/file && git commit -m "WIP: <round-id> <one-line-purpose>"
```

Examples:
- `git add llm/notes/p7-brief.md && git commit -m "WIP: P7 brief skeleton"`
- `git add llm/notes/p7-foo.md && git commit -m "WIP: P7 v1 draft"`
- `git add skills/foo.md && git commit -m "WIP: skills/foo.md draft"`

### 3.2 Iteration commits

After each substantive edit (e.g., applying reviewer feedback):

```bash
git add path/to/file && git commit -m "<round-id> <iteration>: <what-changed>"
```

Example: `git commit -m "P7 v2: Codex round-2 fixes (3 corrections applied)"`

### 3.3 Lock commit

The 3-of-3 lock commit is what closes the bead and marks "this is the final agreed version":

```bash
git add path/to/file llm/LOG.md llm/<agent>-state.md && \
  git commit -m "<round-id> locked: <summary>" && \
  bd close <bead-id> --reason="<round-id> locked 3-of-3; artifact at <path>" && \
  git push origin dev
```

### 3.4 Push cadence

`git push origin dev` after EVERY commit during round work. Local commits are not safe — they only survive if the laptop survives. Remote (origin/dev) is the durable backup.

---

## 4) What about untracked-by-design files?

Some files SHOULD stay untracked forever (e.g., `tmp/`, `.beads/dolt/` runtime state, secrets). Those are governed by `.gitignore`. The rule above applies to **deliverable** files — anything you'd be sad to lose.

Quick check: if you would re-write the file from scratch if it disappeared, it's a deliverable. Commit it.

---

## 5) Cross-reference

- This skill complements `skills/session-lifecycle.md` §3 (session close), but operates **at a finer grain** — every file write, not every session.
- `skills/round-protocol.md` §3.6 says "Lock (commit)" — this skill says "and commit at every interim step too, not just lock".
- `skills/bd-discipline.md` §9.2 mandates `git push` at session close — this skill mandates it more often: at every commit during a round.

---

## 6) Failure modes

- ❌ Writing/editing a deliverable file but never `git add`-ing it. **Top cause of work loss.** Always at least add before reviewing.
- ❌ Holding multiple files uncommitted across review cycles. Stage them all.
- ❌ Trusting the working tree as durable. The working tree is volatile; git is durable.
- ❌ Skipping `git push` because "I'll push at session close". Push every commit; session close becomes a no-op verification.
- ❌ Squashing WIP commits before lock. Keep the history; squash is optional and only on explicit CEO/peer ask.

---

## 7) Convergence signal

This skill is locked from first-write (no review cycle needed for a forensic post-mortem). Future iteration via the normal RoE pattern if anything needs adjusting.
