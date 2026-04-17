# P6 — Lifecycle Adapter: status / closure / postpone / entropy (Fizzy → Beads)

**Status**: drafting (P6 round in flight)  
**Bead**: `fizzy-v4j`  
**Drafter**: `fizzy-codex`  
**Reviewers**: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)  
**Brief**: `llm/notes/p6-brief.md`  

This doc closes lifecycle questions from P1 §E.4 for V1:
Q-S-013, Q-S-014, Q-S-015, Q-S-016.

Constraint reminders:
- P3: **SQL reads (Trilogy) + CLI writes (`bd`)** (`llm/notes/p3-data-path-decision.md`).
- P4: **Board membership label + status→column mapping** (`llm/notes/p4-ui-projection-deep-dive.md`).
- P5: **Actor is explicit via `bd --actor <email>`** (`llm/notes/p5-auth-bridging.md`).

---

## §A — Status mapping table (Q-S-013)

TODO: decide how Fizzy `cards.status` (`drafted`/`published`) maps to Beads `issues.status` (and/or metadata), given Beads has no drafted/published native.

---

## §B — Closure migration (Q-S-014)

TODO: decide how Fizzy `closures` (with `user_id`) maps to Beads `issues.status='closed'` and Beads `events` history.

---

## §C — NotNow → deferred (Q-S-015)

TODO: decide how Fizzy `card_not_nows` presence (with `user_id`) maps to Beads `issues.status='deferred'` and `issues.defer_until`.

---

## §D — Entropy → defer_until (Q-S-016)

TODO: decide how Board/Account entropy config maps to per-issue `defer_until` and auto-postpone job mechanics.

---

## §E — Goldness (confirm P4 disposition)

TODO: restate P4 decision (priority replaces goldness) and any lifecycle implications.

---

## §F — ActivitySpike (confirm v1 disposition)

TODO: decide whether to keep as sidecar, compute, or drop.

---

## §G — Reopen semantics

TODO: decide how reopen maps to Beads status transition and whether we restore prior status/column.

---

## §H — Lifecycle hook plumbing (sketch only)

TODO: where this logic will live (likely a `Beads::Lifecycle` helper and/or `Beads::IssueRepository` methods).

---

## §I — Resolved Q-S items (links back to P1)

TODO: mark Q-S-013/014/015/016 ANSWERED with backlinks to this doc.

---

## §J — Open questions for downstream rounds

TODO: new Q-S items discovered while mapping.

---

## Convergence signal (P6)

When all three agents agree P6 is complete, each sends:

`[FROM→TO P6: agreed]`

After all signals are in `llm/LOG.md`, this file is locked, bead `fizzy-v4j` is closed, and P7 opens.

