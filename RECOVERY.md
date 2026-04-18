# RECOVERY.md — Fleet Restart Protocol

> **Authored**: 2026-04-18 (post-disk-full reboot prep)
> **Authoritative for**: post-reboot fleet spinup, cadence resumption, bd state continuity.
> **Owned by**: CEO + fizzy-claude. Do NOT edit during recovery; treat as immutable until reboot completes.

This document encodes everything needed to fully resume the autonomous I-batch implementation operation after a fleet reboot. It assumes you (CEO Timm) and three coordinating Claude/Codex/Gemini agents must restart from a cold state with only this file + the git repo as the source of truth.

---

## 0) Pre-restart Snapshot (capture this BEFORE rebooting)

| Item | Value (as of authoring) |
|---|---|
| Repo | `/Users/timmstokke/work/fizzy` |
| Branch | `dev` |
| HEAD commit | `d52950a75` |
| Tree state | clean (no uncommitted deliverables) |
| Project completion | **134 / 145 closed (~92.4%)** |
| Open beads | 11 (3 deferred + 3 pmi tests blocked + 5 epics/dependents) |
| Last cron job | `d9eb8627` — every-10m peer-pane health check (recurring, in-memory only — **dies on reboot**) |
| All commits pushed to | `https://github.com/t1mmen/fizzy.git` (origin/dev = HEAD) |

**Verification before reboot**:
```bash
cd /Users/timmstokke/work/fizzy
git status                                # MUST be clean (no M / ?? entries)
git log --oneline -1                      # confirm HEAD = d52950a75 (or later)
git rev-parse origin/dev                  # MUST equal local HEAD
bd stats                                  # confirm 134/145 closed
```

If any of these don't match, FIX BEFORE rebooting. Otherwise work will be lost and the recovery doc will be stale.

---

## 1) The Fleet — Agents, Sessions, Models, Roles

Three coordinating agents. Each owns its tmux session + state file + lane.

| Agent | tmux session | Model / CLI | State file | Primary lane |
|---|---|---|---|---|
| **fizzy-claude** | `fizzy-claude` | Claude Code (this CLI) | `llm/claude-state.md` | Coordinator + S5/S7/S8/S9 implementation, peer-pane health monitor (the wake-nudge loop) |
| **fizzy-codex** | `fizzy-codex` | Codex (`gpt-5.2 high`) | `llm/codex-state.md` | S2/S3/S6/S8 implementation, system tests |
| **fizzy-gemini** | `fizzy-gemini` | Gemini 3 (Google CLI, `~/work/fizzy`, YOLO mode) | `llm/gemini-state.md` | S6 (rich text + comments), test scaffolding |

**Ownership rule (non-negotiable, see AGENTS.md)**: each agent's state file is owned by that agent only. If you find a peer's state file uncommitted in your tree, **commit on their behalf** with a clear message — do NOT revert or stash.

---

## 2) Cold-start Spinup Procedure (CEO does this in a terminal)

After the reboot:

### 2.1 Verify the workspace
```bash
cd /Users/timmstokke/work/fizzy
git pull --rebase                 # sync to origin/dev
bd dolt pull                      # sync beads from Dolt remote
git log --oneline -5              # sanity check
bd stats                          # confirm 134/145 closed (or current baseline)
```

### 2.2 Re-create the three tmux sessions
```bash
# Session 1: fizzy-claude (this Claude Code CLI)
tmux new-session -d -s fizzy-claude -c /Users/timmstokke/work/fizzy
tmux send-keys -t fizzy-claude 'claude' Enter   # adjust if your CLI launch is different

# Session 2: fizzy-codex
tmux new-session -d -s fizzy-codex -c /Users/timmstokke/work/fizzy
tmux send-keys -t fizzy-codex 'codex' Enter      # adjust to your codex CLI

# Session 3: fizzy-gemini
tmux new-session -d -s fizzy-gemini -c /Users/timmstokke/work/fizzy
tmux send-keys -t fizzy-gemini 'gemini' Enter    # Starts the interactive Gemini CLI
```

Attach in three terminals (or three iTerm2 tabs):
```bash
tmux attach -t fizzy-claude
tmux attach -t fizzy-codex
tmux attach -t fizzy-gemini
```

### 2.3 Brief each agent immediately (paste these into each agent's first prompt)

**For fizzy-claude** (this agent — paste as the first message):
> You are fizzy-claude, the coordinator agent. Read AGENTS.md, CLAUDE.md, RECOVERY.md, llm/claude-state.md, and skills/*.md (especially tmux-dispatch.md, bd-discipline.md, work-persistence.md). The fleet just restarted post-disk-full reboot. Project state: 134/145 beads closed (~92%), HEAD `d52950a75`. Your job: (1) re-establish the 10-minute peer-pane health-check cron via `/loop 10m Capture both peer panes...` — see RECOVERY.md §4 for the exact prompt. (2) Wait for peer dispatches. (3) Help with any unblocked work in your lane. Do NOT touch CEO-deferred items (S1 drops `0as/ml5/7ka`, S7 `c3z`). Do NOT retry pmi.13 (user removed prior attempt). Acknowledge fleet restart in `llm/LOG.md` with timestamp.

**For fizzy-codex** (paste as the first message):
> You are fizzy-codex. Read AGENTS.md, CLAUDE.md, RECOVERY.md, llm/codex-state.md, llm/LOG.md tail, skills/*.md. Project state: 134/145 closed (~92%), HEAD `d52950a75`. Run `bd ready -n 30` to see remaining work. Your lane: S2/S3/S6/S8/system-tests. Do NOT touch CEO-deferred items (`0as/ml5/7ka` S1 drops, `c3z` S7 quota). pmi.13 is fizzy-claude's parked work — do not pick it up. If nothing in your lane is ready, reply "standing by" and wait for dispatch from fizzy-claude. Use the strict 3-call tmux dispatch protocol (skills/tmux-dispatch.md): message → sleep 4 → Enter, then capture-pane verify. Acknowledge restart in `llm/LOG.md`.

**For fizzy-gemini** (paste as the first message):
> You are fizzy-gemini. Read AGENTS.md, GEMINI.md, RECOVERY.md, llm/gemini-state.md, llm/LOG.md tail, skills/*.md. Project state: 134/145 closed (~92%), HEAD `d52950a75`. Your lane: S6 (rich text + comments) — already largely complete; verify with `bd list --label s6 --status=open` (likely empty). Stand by for dispatch unless you see an unclaimed bead in your lane. **CRITICAL**: avoid leading-`!` characters in tmux dispatches (triggers shell mode); see skills/tmux-dispatch.md. **Stay in normal mode** — if you see `!` shell prompt, hit Escape immediately. Acknowledge restart in `llm/LOG.md`.

### 2.4 Validate fleet is alive
After all three agents acknowledge:
```bash
# In any terminal, verify each session has an active agent prompt:
tmux capture-pane -t fizzy-claude -p -S -10 | tail -8
tmux capture-pane -t fizzy-codex  -p -S -10 | tail -8
tmux capture-pane -t fizzy-gemini -p -S -10 | tail -8

# Verify each agent appended a restart entry to LOG.md:
tail -30 llm/LOG.md | grep -i "restart\|recovery"
```

---

## 3) The Operating Cadence

### 3.1 Wake-nudge cron loop (fizzy-claude only)

The coordinator (fizzy-claude) runs a **10-minute recurring cron** that fires this prompt and self-checks both peer panes for failure modes. The cron is **session-scoped** (dies on Claude Code restart) — fizzy-claude must re-arm it via `/loop` after every restart.

**Exact incantation to re-arm in fizzy-claude**:
```
/loop 10m Capture both peer panes (fizzy-codex and fizzy-gemini) using the strict skills/tmux-dispatch.md capture pattern (`tmux capture-pane -t <session> -p -S -50 | tail -25`). Check each for: 1. Stuck input buffer; 2. Wrong shell mode; 3. Backtick / bang-equals / shell-trigger characters in pending outbound; 4. Long idle (>5 min) when response was expected; 5. Drift from skills/tmux-dispatch.md 3-call protocol; 6. Loss of work signs (uncommitted deliverables). If healthy, just note "panes healthy" and continue I-batch dispatch flow.
```

The `/loop` skill creates a CronCreate job (`*/10 * * * *`) that re-runs the prompt every 10 minutes. Auto-expires after 7 days. Cancel sooner with `CronDelete <job-id>` if needed.

### 3.2 The 6 failure modes the cron watches for

1. **Stuck input buffer** — paste-buffer text without `Working`/`Thinking` indicator → send a separate `Enter` keystroke
2. **Wrong shell mode** (Gemini-specific) — `!` prefix or `shell mode enabled` → send `Escape` then nudge
3. **Backtick / bang chars in pending outbound** — about to break the protocol → ping corrective
4. **Long idle (>5 min) when response expected** — ping `[CLAUDE→<agent>] Status check — anything blocking? Last expected: <topic>.`
5. **3-call protocol drift** — peer dispatched without sleep+Enter+verify → include refresher in next outgoing
6. **Uncommitted deliverables** — peer's tree shows in-progress work → commit-on-behalf or ping owner

### 3.3 Tmux dispatch protocol (strict, see skills/tmux-dispatch.md)

```bash
# Call 1 (separate Bash invocation):
tmux send-keys -t fizzy-codex '[CLAUDE→CODEX] message body here'

# Call 2 (separate Bash invocation, after call 1 completes):
sleep 4 && tmux send-keys -t fizzy-codex Enter

# Call 3 (mandatory verification):
tmux capture-pane -t fizzy-codex -p -S -10 | tail -8
```

**Forbidden**: chaining Enter into the same call (`'msg' Enter`); skipping the sleep; skipping verification.

**Avoid in message body**: leading `!` (Gemini interprets as shell mode); leading backticks; backtick-quoted shell expressions (Codex zsh expands them).

---

## 4) Beads Workflow & Catalog

### 4.1 Core bd commands (memorize these)

```bash
bd ready -n 30                               # find unclaimed work
bd show <id>                                 # detailed view
bd update <id> --claim                       # claim work (errors if already claimed)
bd close <id> --reason="<one-line summary>"  # close with reason
bd stats                                     # progress
bd dolt push                                 # sync beads to remote
bd dolt pull                                 # sync from remote
```

**Forbidden**: `bd edit` (opens vim/nano, blocks the agent indefinitely).

### 4.2 Remaining 11 open beads (post-restart catalog)

| ID | P | Title | Status | Assignee | Notes |
|---|---|---|---|---|---|
| `fizzy-669` | P1 | S1 epic: Card id + FK migration | open | epic | parent of S1 drops |
| `fizzy-0as` | P1 | F.4 — Drop card_not_nows table | open | claude | **CEO-DEFERRED** — drops are deferred unless required |
| `fizzy-7ka` | P1 | F.2 — Drop card_goldnesses table | open | claude | **CEO-DEFERRED** — same |
| `fizzy-ml5` | P1 | F.3 — Drop card_activity_spikes table | open | claude | **CEO-DEFERRED** — same |
| `fizzy-yeu` | P1 | S7 epic: Attachments + storage quotas | open | epic | parent of S7 c3z + 60v |
| `fizzy-c3z` | P1 | S7 F.3 — Storage quota_check enforcement (422) | open | claude | **CEO-DEFERRED** — env-fix not code-level per directive |
| `fizzy-60v` | P1 | S7 F.8 — Quota integration tests | open | claude | blocked by c3z |
| `fizzy-pmi` | P1 | S9 epic: Search + filter + poller | open | epic | parent of pmi.13/14/15 |
| `fizzy-pmi.13` | P1 | S9 F.13 — End-to-end poller tick integration tests | open | claude | **PARKED** — user removed Claude's earlier attempt; do not retry without new guidance |
| `fizzy-pmi.14` | P1 | S9 F.14 — Replay/idempotency tests | open | claude | blocked by pmi.13 |
| `fizzy-pmi.15` | P1 | S9 F.15 — Performance test (200 rows < 5s; filter < 100ms p95) | open | claude | blocked by pmi.13 |

### 4.3 What's actionable right now

**None for fizzy-claude** without CEO un-blocking pmi.13 or relaxing the deferral on c3z/S1-drops.
**None for fizzy-codex** without new bead creation.
**None for fizzy-gemini** without new bead creation.

The fleet is in a STANDBY POSTURE post-restart. Cadence loop should still run for protocol-coverage even when no work is ready.

### 4.4 If CEO authorizes deferred work post-restart

- `c3z` requires env setup work (see fizzy-claude's earlier attempt notes in LOG.md). The CEO previously reverted Claude's code-level approach — env approach is preferred.
- S1 drops (`0as/ml5/7ka`) require confirming via `grep` that NO model class still references `card_not_nows`/`card_goldnesses`/`card_activity_spikes` before dropping (see AGENTS.md failure-mode log: a prior drop without grep broke the test suite + boot).
- `pmi.13` requires CEO clarification: should the test wire `Beads::Mirror::Cursor::PROCEDURES` (currently empty) and exercise the actual orchestrator, OR call mirror procedures directly? The empty registry is the meaningful gap.

---

## 5) Critical CEO Constraints (must-not-violate)

These came down via tmux directives during the I-batch run — they remain in force post-restart:

1. **Defer ALL deletions / table drops UNLESS REQUIRED for downstream work.** S1 drops are explicitly deferred.
2. **Defer S7 c3z (storage quota enforcement)** — env-fix not code-level. CEO reverted Claude's code attempts 3 times.
3. **Each agent commits ONLY its own work.** Use `git add <explicit-paths>`, never `git add .` / `-A` / `-u` (sweeps in peer drift + cross-adapter schema regression).
4. **Schema regression artifacts** in `db/cable_schema.rb` and `db/schema_sqlite.rb` (cross-adapter MySQL→SQLite drift from local `db:migrate` on peer migrations) — **do NOT commit**. Discard via `git checkout` if they appear.
5. **Commit immediately after edit** — <2 minutes between save and `git push`. No long staging periods.
6. **No `git stash` across agents** — destructive across peers. Commit-on-behalf instead.
7. **No `--no-verify`, no force-push to main**, no destructive operations without explicit CEO approval.

---

## 6) Recovery Validation Checklist (post-spinup)

Run these in order. STOP if any fails until resolved.

```bash
# === Workspace integrity ===
cd /Users/timmstokke/work/fizzy
git status                                       # tree clean
git log --oneline -1                             # HEAD = d52950a75 or later
git rev-parse @ && git rev-parse @{u}            # local == origin
diff <(git rev-parse @) <(git rev-parse @{u})    # empty means in sync

# === Bd state ===
bd stats                                         # confirm closed count
bd ready -n 30                                   # confirm 8 ready (mostly deferred)
bd doctor                                        # check for sync issues

# === Fleet liveness ===
tmux list-sessions | grep fizzy                  # 3 sessions: claude, codex, gemini
for s in fizzy-claude fizzy-codex fizzy-gemini; do
  echo "=== $s ==="
  tmux capture-pane -t "$s" -p -S -10 | tail -5
done

# === Cadence active ===
# In fizzy-claude REPL, verify cron exists via TaskList or CronList tool
# Cron job ID will be NEW (the d9eb8627 from before reboot is dead)

# === LOG continuity ===
tail -50 llm/LOG.md                              # last entries should be pre-restart
                                                 # plus three restart-ack entries
```

---

## 7) Known Failure Modes & Recovery Patterns

(Excerpted from AGENTS.md "Failure mode log" + this session's experience.)

| Failure | Symptom | Recovery |
|---|---|---|
| Disk full (>99%) | `ENOSPC` on Bash tool output | `rm -rf /private/tmp/claude-501/*/tasks/*.output` (safe scratch); `brew cleanup`; `du -sh ~/Library/Caches/* | sort -h | tail -20` to find offenders |
| Gemini in shell mode | `! ` prefix in input box, `shell mode enabled` indicator | Send `Escape`, then corrective dispatch (no leading `!` in body). **Trigger**: any message body starting with `!` or containing certain shell operators. |
| Stuck paste buffer | Message visible in input box, no Working indicator | Send a separate `Enter` keystroke |
| Peer drops migration without code cleanup | `load_schema!` errors, app boot fails | Forward-restore migration that re-creates the table; reopen the original drop bead with prerequisite cleanup notes |
| Schema regression drift | `db/cable_schema.rb` + `db/schema_sqlite.rb` change after peer's migration | Discard with `git checkout db/cable_schema.rb db/schema_sqlite.rb` — these are cross-adapter artifacts |
| Duplicate-symbol commit callbacks | `after_create_commit :foo` + `after_destroy_commit :foo` collapsed by Rails into single AND-condition entry → never fires | Use combined `after_commit :foo, on: [:create, :destroy]` (this session's fizzy-jig fix) |
| `comments.id` NOT NULL after edq.1 widening | `Comment.create!` fails with NOT NULL constraint | Add `before_create -> { self.id ||= ActiveRecord::Type::Uuid.generate }` to Comment (this session's fix) |
| Module name shadowing within `Beads::Mirror` | `NoMethodError: find_or_create_by!` on sibling module | Rename ambiguous module (e.g. `Beads::Mirror::Event` → `Beads::Mirror::EventMirror`) |
| Autostash loses untracked files | `git pull --rebase` autostash drops new files | Always `git add` then commit BEFORE pulling; never leave untracked deliverables |

---

## 8) Single-Source-of-Truth References

These files are the definitive source — RECOVERY.md is a pointer, not a replacement:

- `AGENTS.md` — multi-agent ownership rules, commit discipline, failure-mode log
- `CLAUDE.md` — Claude Code-specific instructions
- `STYLE.md` — Ruby/Rails coding conventions
- `skills/tmux-dispatch.md` — strict 3-call dispatch protocol
- `skills/bd-discipline.md` — bd workflow rules
- `skills/work-persistence.md` — uncommitted-work recovery
- `skills/session-lifecycle.md` — session bookends
- `skills/round-protocol.md` — round mechanics
- `llm/LOG.md` — append-only chronological event log
- `llm/notes/s*-*-spec.md` — per-spec implementation specs (S1-S10)

---

## 9) Reboot-Ready Checklist (CEO runs this RIGHT BEFORE rebooting)

```
[ ] git status clean
[ ] git push (verify "up to date with origin/dev")
[ ] bd dolt push (sync beads remote)
[ ] tmux capture-pane on all 3 sessions to confirm no in-flight work
[ ] All 3 agents ack "standing by" or have just-pushed commits
[ ] RECOVERY.md committed + pushed (this file)
[ ] Note current HEAD commit in your own notes for post-reboot verification
```

After reboot, follow §2 then §6.

---

## 10) Why this works

The fleet is **stateless across reboots** — agents have no persistent memory beyond what's in git. RECOVERY.md is the single bootstrap document because:

- Bd catalog is in `.beads/issues.jsonl` (committed) + Dolt remote (pulled fresh)
- Code state is in git (pushed)
- Skills + protocols are in `skills/*.md` (committed)
- Operational history is in `llm/LOG.md` (committed, append-only)
- Per-agent state hints are in `llm/<agent>-state.md` (committed)

The ONLY ephemeral state that doesn't survive reboot:
1. Tmux sessions — re-create per §2.2
2. Cron jobs — re-arm per §3.1 (in fizzy-claude only)
3. Agent in-context working memory — replaced by re-reading the docs in §2.3

If everything in this document is followed, the fleet resumes within ~5 minutes of reboot completion with no work loss and full cadence intact.
