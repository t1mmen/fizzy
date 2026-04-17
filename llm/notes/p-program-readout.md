# P-batch Ratification Readout — for CEO Timm

**Date**: 2026-04-17
**Author**: fizzy-codex (with fizzy-claude + fizzy-gemini as peer reviewers)
**Status**: Planning rounds P1–P10 complete (pending P10 3-of-3 lock). Awaiting CEO ratification before Spec phase begins.

---

## What this is

This is the CEO-facing summary of the full Planning phase. Planning produced a set of locked decision docs under `llm/notes/p1-...` through `llm/notes/p10-...`. These establish the fork posture and the non-negotiable technical doctrines that the Spec phase will turn into “perfect beads”.

## The 10 planning artifacts

| # | Round | Topic | File | Last commit |
|---|---|---|---|---|
| 1 | P1 | Foundational gap inventory | `llm/notes/p1-foundational-gap-inventory.md` | `b095e8f5b` |
| 2 | P2 | Local dev grounding | `llm/notes/p2-local-dev-grounding.md` | `d79aeb394` |
| 3 | P3 | Data-path decision | `llm/notes/p3-data-path-decision.md` | `e1d855c7b` |
| 4 | P4 | UI projection deep dive | `llm/notes/p4-ui-projection-deep-dive.md` | `e3c3f624e` |
| 5 | P5 | Auth bridging | `llm/notes/p5-auth-bridging.md` | `a8d15afb3` |
| 6 | P6 | Lifecycle adapter | `llm/notes/p6-lifecycle-adapter.md` | `b095e8f5b` |
| 7 | P7 | Multi-assignee + tags/labels | `llm/notes/p7-multi-assignee-tags-labels.md` | `a1a8c3828` |
| 8 | P8 | Events sync posture | `llm/notes/p8-events-sync.md` | `3ed0afd4b` |
| 9 | P9 | Search strategy + filter execution | `llm/notes/p9-search-strategy.md` | `28bd476fd` |
| 10 | P10 | Fork posture synthesis | `llm/notes/p10-fork-posture-summary.md` | `a8dd446c0` |

Supporting research artifacts:
- `llm/notes/community-bead-uis-research.md` (community semantics cross-check; commissioned per Q5b)
- `llm/notes/dolt-rails-adapter-research.md` (Dolt+Rails 8 feasibility + branch/pooling constraint)

## The non-negotiable doctrines (the “shape of the fork”)

These are the foundation decisions that Spec rounds should treat as “inputs”, not debate topics:

1. **Hard fork** (no merge-back with upstream Fizzy). (CEO Q5; `llm/LOG.md:144`)
2. **Single-tenant** installs, but **multi-user team survives** (Users, roles, board access control). (CEO Q3; P5)
3. **Beads/Dolt is sovereign** for task data; Beads schema is **immutable**. (CEO Q2; P1 §B)
4. **Hybrid data-path**: Dolt SQL for reads + `bd` CLI for writes (preserves Beads hooks/audit/events). (P3)
5. **Actor attribution** via argv: `bd --actor <email> ...` on every mutation. (P5)
6. **Board membership is a Beads label namespace**: reserved `fizzy/board/<board_uuid>` labels; single-board invariant preserved. (P4)
7. **V1 UI includes Kanban + List**; list is the accessibility anchor. (P4)
8. **Lifecycle is Beads-native** (`issues.status` + `defer_until` + `closed`); entropy is Fizzy-side config driving system-actor CLI writes. (P6)
9. **Labels are canonical in Beads**; Fizzy Tag survives as normalized display. `fizzy/*` reserved for system labels. (P7)
10. **Search stays Fizzy 16-shard FTS**, powered by a **Card mirror projection** and a periodic Beads→Fizzy poller using callback-bypassing upserts + explicit Search::Record writes. (P9)
11. **Canonical events log is Beads** (`events` + `comments`); webhook bridging for Beads-driven changes is deferred. (P8)
12. **Backup posture**: `git push` is load-bearing; `.beads/issues.jsonl` provides task snapshot backup; `bd dolt push` is desired but currently broken (future plumbing). (P10; R0)

## What V1 explicitly includes vs excludes

### V1 includes (core scope)

- Core task CRUD (create/update/close/defer/reopen), assignment, labels, dependencies, comments, “typical workflow” per CEO Q4a.
- Fizzy-native UX projection over Beads tasks: boards, columns, kanban, list, access control.

### V1 explicitly excludes / defers

- Orchestration layer (gates/molecules/formulas/swarms/federation) — v2+.
- File-watcher + SSE for sub-second UI sync — v2+ (V1 uses polling).
- Webhook bridging for Beads-driven state changes — v2+ (webhooks exist as concept; bridge deferred).
- Branch-aware Dolt connection pooling — v2+ (only matters once branches exist).
- Bulk/batch mutation UI — v2+.
- Upstream-Fizzy import/export parity — not in V1.

## Remaining open questions (queued for spec phase)

The Spec phase is expected to answer the remaining “V1 scope” questions as perfect beads (S1–S10). The full list is maintained in `llm/notes/p10-fork-posture-summary.md` §G.3.

Highest-risk open topics (recommended early in Spec):
- Rich text + comments mapping (Q-S-012 + Q-S-019)
- Attachments + ActiveStorage string-ID migration (Q-S-025)
- Metadata vs sidecar boundary rules (Q-S-002 + Q-S-032)
- Search drift/ephemeral handling (Q-S-057 + Q-S-058)

## Recommended ratification verdict

Recommend: `[CEO→ALL P-batch: ratified]` once P10 is 3-of-3 locked.

If you want changes before ratifying, the most likely “pre-Spec” adjustments are:
- Re-scope webhooks (pull forward Q-S-022) or reaffirm it as v2+.
- Re-scope UI freshness (pull forward Q-S-035) or reaffirm poller-first in v1.

## What happens after ratification

1. Claude (or the council) opens Spec round **S1** with a brief, using P10 §F as the starting checklist.
2. S1–S10 produce “perfect beads” ready for implementation (no further Planning-level debate).
3. Implementation begins after S-batch lock, adhering to `skills/test-discipline.md` + `skills/bd-discipline.md`.
