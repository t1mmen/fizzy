# Rules of Engagement (RoE) — Fizzy × Beads agent team

**Status**: draft (RoE-1 pending)
**Applies to**: all agent sessions working in this repo, including `fizzy-claude`, `fizzy-codex`, `fizzy-gemini`.
**Scope**: how we operate (not product design). For round mechanics, see `skills/round-protocol.md` once drafted.

This file is the *foundation* of the operating system for the Fizzy/Beads fork. If anything in later docs conflicts with this file, this file wins unless Timm explicitly ratifies an override.

---

## 1) Identity and team

### 1.1 Agents and tmux identities

- Each agent is identified by its **tmux session name**, not by the underlying model.
  - Claude: `fizzy-claude`
  - Codex: `fizzy-codex`
  - Gemini: `fizzy-gemini` (if/when active)
- Every direct message MUST be enveloped as: `[FROM→TO] message body`.

### 1.2 Ownership and “who can touch what”

- Ownership is established by **beads issue claim** (`bd update <id> --claim`).
- If an agent has claimed an issue, they own it end-to-end unless they explicitly hand it off.
- If a file might be touched by more than one agent in parallel, **ping before editing** and wait for an ACK.

---

## 2) CEO authority and decision model

### 2.1 CEO

- Timm is the CEO and final authority.
- Timm is **async-only** by default. We batch questions and present crisp deltas, not ongoing chatter.

### 2.2 Autonomy boundaries

- During the **prep program** (planning/spec rounds), we operate autonomously inside the approved scope of each topic/round.
- After the prep program is complete and ratified, we continue autonomously for implementation, with the exception below.

### 2.3 Explicit sign-off requirement

- **Kamal deploy** requires explicit CEO sign-off.
- All other changes are autonomous once the prep program is complete *and* the relevant topic rules are ratified.

---

## 3) Communication channels (non-negotiable)

### 3.1 Direct messaging: tmux send-keys

Use the strict protocol in:

- `skills/tmux-dispatch.md`
- `llm/README.md` (log and state conventions)

Failure to follow the tmux protocol is a *process bug* and must be treated as a priority fix.

### 3.2 Durable record: `llm/LOG.md`

- Every outbound tmux message is appended to `llm/LOG.md` by the **sender**.
- Log is append-only with timestamp headers. See `llm/README.md`.

### 3.3 Per-agent state

- Claude writes: `llm/claude-state.md`
- Codex writes: `llm/codex-state.md`
- State tracks: “what I’m doing now”, “what I’m blocked on”, “what I need from the other agent”.

---

## 4) Decision-making and disagreement

### 4.1 Default stance

- We are collaborators, not majority-rule voters.
- We do not “win” disagreements; we converge on a ratified truth.

### 4.2 Talk-it-out rule (no silent overrule)

- If there is disagreement on a material point, we must:
  1. Make the disagreement explicit (what exactly differs).
  2. Provide evidence (paths, command outputs, concrete constraints).
  3. Attempt reconciliation.

No agent may silently proceed as if their position won without ACK or CEO ratification.

### 4.3 Budget: ≤ 8 rounds per topic

- For any RoE/topic doc: we cap iteration at **8 rounds**.
- When the budget is exhausted, we either:
  - narrow scope and ship the minimal ratifiable version, or
  - escalate to CEO for a decision, with a tight options list.

### 4.4 Escalation criteria (when to ask Timm)

Escalate when any of the following are true:

- We are stuck on a binary value judgment (taste, priorities, irreversible bet).
- A decision has significant downstream blast radius (workflow, repo layout, security posture).
- We hit the topic round budget without convergence.
- The decision changes the meaning of “done” for a major milestone.

---

## 5) Round structure (pointer)

This RoE document does not define round mechanics. It defines **how we behave**.

Round mechanics live in `skills/round-protocol.md` (to be drafted/ratified next).

---

## 6) Quality bar (evergreen)

### 6.1 “Evergreen” means maintainable for 10 years

- Prefer boring, conventional solutions over clever ones.
- If we must do something uncommon, it must be:
  - justified,
  - documented,
  - testable,
  - reversible (when possible).

### 6.2 No shortcuts policy

- No “temporary hacks” without an explicit owner + follow-up issue.
- No silent scope creep.
- No landing partially-understood codepaths.

### 6.3 Verification-first culture

- Claims about behavior should be backed by:
  - concrete code pointers (`path:line`),
  - command outputs,
  - reproducible steps.

---

## 7) Operating values (team norms)

- Assume a room of talented Rails+DB engineers will read this code.
- Prefer holistic design over local optimizations.
- Avoid NIH: do not reinvent what is already solid in Fizzy/Rails unless we must.
- Avoid wheel reinvention: if a thing exists, name it and link it; don’t clone it.
- Prefer clarity over maximal abstraction.

---

## 8) Process constraints specific to this program

### 8.1 Fork posture

- This is a **hard fork**. There is no merge-back upstream.
- UX should remain Fizzy-native; data/behavior is Beads-driven (per CEO directives recorded in `llm/LOG.md`).

### 8.2 Beads is canonical for work tracking

- Beads (`bd`) is the only source-of-truth for task tracking.
- Do not use ad-hoc TODO lists as task tracking.
- Details live in `skills/bd-discipline.md` (to be drafted/ratified).

### 8.3 Prep vs build phases

- During planning/spec rounds, avoid implementation changes unless the CEO has explicitly approved a “plumbing fix” exception (example: R0 Dolt cleanup).
- During implementation, follow beads ownership and quality gates.

---

## 9) Failure-mode log (append-only)

This section records *process* failures we want to prevent from recurring. Add entries as they occur; do not rewrite history.

### 9.1 tmux silent-stall

- Failure: message pasted into receiver input but not submitted (missing Enter), causing both sides to idle.
- Fix: strict three-call tmux dispatch + capture-pane verify.
- Canonical procedure: `skills/tmux-dispatch.md`.

---

## 10) Convergence signal

When Claude and Codex both agree RoE-1 is complete, each sends the other:

`[FROM→TO RoE-1: agreed]`

After both signals are logged in `llm/LOG.md`, this file is locked for topic 1 and we move to topic 2.

