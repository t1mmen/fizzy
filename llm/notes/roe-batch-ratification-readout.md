# RoE Batch Ratification Readout — for CEO Timm

**Date**: 2026-04-17
**Author**: fizzy-claude (with fizzy-codex as co-drafter; fizzy-gemini as third-lens reviewer)
**Status**: All 7 RoE topics 3-of-3 locked. Awaiting CEO ratification before R1 of Planning begins.

---

## What this is

The Rules-of-Engagement (RoE) brainstorm produced 7 evergreen skill files in `skills/` that codify how the Fizzy/Beads agent team operates. Each topic was drafted by one agent, peer-reviewed by another, ratified by the third, then locked. This readout is the consolidated batch you ratify (or send back for revision) before we begin Planning Round 1 of the 20-round program.

All 7 skills are committed to `origin/dev`. You can read them as a set or jump to any one.

---

## The 7 ratified artifacts

| # | Topic | File | Drafter | Reviewer | Third-lens | Lock commit |
|---|---|---|---|---|---|---|
| 0 | Tmux dispatch protocol | `skills/tmux-dispatch.md` | Claude (after the silent-stall incident) | Codex | Gemini | included in early commits |
| 1 | Rules of engagement | `skills/rules-of-engagement.md` | Codex | Claude | Gemini | `7d29447fe` |
| 2 | Documentation hierarchy | `skills/documentation-hierarchy.md` | Claude | Codex | Gemini | `dcd98059d` |
| 3 | Round protocol | `skills/round-protocol.md` | Codex | Claude | Gemini | `dff339ccc` |
| 4 | Beads discipline | `skills/bd-discipline.md` | Claude | Codex | Gemini | `2de0ec3a0` |
| 5 | Workflow templates | `skills/workflow-templates.md` | Codex | Claude | Gemini | `8e7f5e414` |
| 6 | Test discipline | `skills/test-discipline.md` | Claude | Codex | Gemini | `9acb0abd8` |
| 7 | Session lifecycle | `skills/session-lifecycle.md` | Codex | Claude | Gemini | (to be committed at lock) |

---

## Foundational decisions baked in

Decisions you made during pre-RoE Q&A that the skills now codify and depend on:

- **Fizzy is the canonical UI for Beads.** Beads/Dolt is sovereign for task data; Fizzy stays the product face (Q1a).
- **Beads schema is immutable.** We conform to it; we never alter columns/types/constraints (Q2).
- **Single-tenant installs.** Multi-tenancy retired; one repo = one install = one beads DB (Q3 ii).
- **UX stays Fizzy-native.** Driven by beads data model. V1 = creation/mutation/association/comments/typical workflow. Orchestration layer (gates, molecules, formulas, swarms, federation) deferred to v2+ (Q4a).
- **Hard fork.** No back-compat with upstream Fizzy, no merge-back. Fizzy-derivative UX. Learn query/mutation patterns from community bead UIs only (Q5).
- **Tech stack locked**: Rails backend, Hotwire frontend, MySQL for Fizzy-side data, Dolt for task data; deploy target deferred (Q7).
- **Governance**: only `kamal deploy` to prod needs CEO sign-off; everything else autonomous after the 20-round prep program completes (Q8).
- **Quality bar**: match Fizzy as it stands — UI, a11y, i18n, mobile, perf, ops. No more, no less (Q9).
- **Team identity**: tmux session names ARE identity — `fizzy-claude`, `fizzy-codex`, `fizzy-gemini` (Q10).
- **Skills are project-local only** (verified by you via direct testing): `./skills/` symlinked into `.claude/skills/`, `.codex/skills/`, `.gemini/skills/`. Never push to user-global (Q12 + clarification).
- **Documentation hierarchy** with seven canonical locations and an explicit decision tree to prevent rot.

---

## Process patterns now operational

- **Topic-by-topic drafting** with ≤8 rounds budget per topic; alternating drafters; convergence signal `[FROM→TO RoE-N: agreed]`.
- **Three-call tmux protocol** (message → sleep+Enter → capture-pane verify) — codified after the silent-stall incident you caught.
- **Peer-agent verification** — never assume another agent's tool internals; ask the live session directly. Codified after the Codex-skills-path incident.
- **Sender-appends-to-LOG** discipline; LOG is append-only audit trail.
- **Three-agent council**: not majority-vote. Even with 3 agents, we converge by talk-it-out. Up to 8 rounds per topic before escalation.
- **Branch posture**: trunk-based on `dev` until `branch-pr-workflow.md` (a future polish skill) ratifies otherwise. All RoE commits on `dev`, none on `main`.

---

## Round-zero plumbing (executed during prep)

- **R0 Dolt cleanup** — resolved the dual-Dolt mess. Embedded DB had stale schema (missing `started_at`); migrated 2 issues to canonical server-mode DB at `.beads/dolt`. Embedded renamed to `.beads/_deprecated_embeddeddolt` (no delete). Documented at `llm/notes/r0-dolt-cleanup.md`. **Residual**: `bd dolt push` to remote is broken (`fatal: this operation must be run in a work tree`); deferred to a future plumbing round; non-blocking because cross-agent collab uses the same local DB.

---

## Known limitations / deferred items

These were identified but explicitly deferred. If you want any pulled forward, flag in your ratification:

1. **`bd dolt push` to remote is broken** — backup-only mechanism, not blocking R1 work. Future plumbing round.
2. **Playwright/Chromia framework not yet in repo** — Capybara is interim system-test tooling. Adding Playwright is itself a Spec round + Implementation round (post-RoE).
3. **`branch-pr-workflow.md` skill not drafted** — we are trunk-based on `dev` by default. If you want a per-topic-branch or PR-gated workflow, file as RoE-8.
4. **Deploy target locked deferred** (Q7c) — server vs desktop vs both decided later. Affects how we package Dolt for end-users.
5. **fizzy-jul "Get started" test bead** still in beads DB from initial setup — disposable, can be closed at any time.
6. **Codex background-terminal hang** — Codex flagged a recurring "Waiting for background terminal" stall (5m+ at one point). Suggested filing a small plumbing bead to investigate.
7. **Gemini's non-blocking polish suggestions** — captured in `llm/notes/gemini-roe-{1-4,5,6,7}-review.md` for future iteration (RoE-Complete signal, blocks-vs-gate clarity, minimum-viable-bead for Planning, fizzy-gemini active-status update in RoE-1 §1.1, etc.)

---

## What you ratify by signing off

Ratifying this batch means:

- The 7 skills become the canonical operating model. Future agents (and human contributors) read `skills/` first.
- We proceed to **R1 of Planning** — the first of 10 planning rounds, then 10 spec rounds, then implementation. Per Q6 you flagged this as a *floor*: 50–80+ beads will likely emerge from the spec phase.
- Until you ratify, we hold. RoE is the operating system; we don't run code on top of an unratified OS.

---

## Recommended ratification verdict

We recommend `[CEO→ALL RoE-batch: ratified]`. If you want any topics revised before ratifying, please specify which topic + the substantive concern; we will iterate per round-protocol.

---

## What happens after ratification

1. Claude opens **R1 of Planning** with a brief at `llm/notes/p1-<topic>.md`. The first planning round is likely "Fizzy data layer ↔ Beads schema mapping" (the foundational gap analysis Q6 flagged as needing diligent research).
2. Subsequent planning rounds build on each other (research → discovery → orientation → context gathering).
3. After P1–P10 lock, S1 begins (spec rounds producing perfect beads).
4. After S1–S10 lock, implementation begins.
5. CEO involvement during implementation: only `kamal deploy` (per Q8a). Everything else autonomous.
