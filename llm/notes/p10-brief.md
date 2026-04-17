# Brief — P10-fork-posture — Q-S-007/027 + synthesis

## Identity
- Round / bead: `P10-fork-posture` / `fizzy-XXX` (created at dispatch)
- Drafter / owner: `fizzy-codex` (alternation: P8 Codex, P9 Claude → P10 Codex; final P-round)
- Reviewers: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)

## Context
- All P1-P9 deliverables (locked)
- `llm/notes/community-bead-uis-research.md` (the input commissioned per CEO Q5b)
- `llm/notes/dolt-rails-adapter-research.md`
- All reserved-but-deferred items: Q-S-007 (export/import), Q-S-027 (backup strategy), Q-S-035 (file-watcher SSE), Q-S-036 (CLI fork cost scaling), Q-S-043 (inbound webhook auth v2), Q-S-044 (token rotation), Q-S-052 (bulk-write rate limit)

## Objective
Synthesize the fork posture: confirm we are a hard fork that diverges intentionally from upstream Fizzy; document import/export/backup decisions for V1; consume community-bead-UIs research as a final cross-check ("did we miss any pattern worth absorbing?"); produce the consolidated readiness summary that feeds the Spec phase.

## Acceptance criteria
- [ ] File `llm/notes/p10-fork-posture-summary.md` with sections:
  - **§A — Fork posture confirmation**: hard-fork, no merge-back, single-tenant, V1 scope. Quotes CEO directives. Is there anything that has shifted during P1-P9 we should re-confirm with CEO?
  - **§B — Import/export decisions** (Q-S-007): V1 = no upstream-Fizzy import; V2 = mapping-table-based or dropped-sidecar import. Document which.
  - **§C — Backup strategy** (Q-S-027): per CEO Q9 "match Fizzy ops bar"; bd dolt push (currently broken — R-plumbing-2 to fix) + git push for code/notes. V1 = local-dev only per CEO Q8a so backup is mostly a non-issue; document the decision.
  - **§D — Community-bead-UI cross-check**: from `community-bead-uis-research.md`, list the 10 absorbed patterns + verify P3-P9 actually adopted each one. Flag any patterns we SHOULD adopt but missed.
  - **§E — Reserved follow-ups list**: every Q-S item marked DEFERRED (or v2+) is enumerated here. This becomes the "won't-do-in-V1" registry.
  - **§F — Spec-phase readiness checklist**: for each of S1-S10 (TBD), what artifact must exist for it to start. Cross-references P-round outputs.
  - **§G — Resolved Q-S items** (final tally): how many P-round Q-S items closed; how many still open for spec/impl.
  - **§H — Open questions** for the spec phase (any new Q-S items).
- [ ] Cross-link from p1 inventory.
- [ ] No code changes; sketches and lists only.
- [ ] Ratified 3-of-3 by `[P10: agreed]`.

## Allowed paths
- Writable: `llm/notes/p10-*.md`, LOG/state, p1 (Q-S markers).
- Read-only: app code, all P1-P9 docs, research notes.

## Out of scope
- Spec rounds (S1-S10 — start AFTER P10 lock).
- Implementation rounds (start after S* lock).

## Sources of truth
- All P1-P9 deliverables
- `llm/notes/community-bead-uis-research.md`
- `llm/notes/dolt-rails-adapter-research.md`
- `llm/notes/r0-dolt-cleanup.md`
- CEO directives in `llm/LOG.md` (Q1-Q15 answers, ratification, autonomous clearance)

## Verification
- Cross-check every Q-S item from p1 §E (and items added in P3-P9): is it ANSWERED, DEFERRED, or still OPEN? §G tally must match.
- Cross-check community-bead-UIs research against P3-P9 decisions: every absorbed-pattern recommendation has a corresponding decision in P3-P9 OR a documented rationale for skipping.

## Output
- `llm/notes/p10-fork-posture-summary.md`
- Updated p1 inventory (final pass on Q-S markers)
- Bead `fizzy-XXX` close
- LOG entries
- Optional: a CEO-facing summary at `llm/notes/p-program-readout.md` (analogous to the RoE-batch-ratification-readout) — recommend producing this so CEO has a single doc to read before Spec phase begins.

## Definition of done
- AC satisfied
- 3-of-3 `[P10: agreed]`
- `bd close fizzy-XXX`
- Commit + push (incremental per work-persistence)
- **Major milestone**: 10/10 Planning rounds complete. CEO ratifies P-batch (analogous to RoE batch). THEN Spec phase (S1-S10) opens.
- Handoff: "P10 locked; P-batch complete; awaiting CEO ratification before S1 dispatch."
