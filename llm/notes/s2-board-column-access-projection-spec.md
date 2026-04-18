# S2 — Board/Column/Access Projection Spec (Beads-backed Cards)

**Status**: drafting (S2 round in flight)
**Bead**: `fizzy-eq4` (epic)
**Drafter**: `fizzy-codex`
**Reviewers**: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/s2-brief.md`

This spec turns the P4 “UI projection” decisions into implementation-ready perfect beads:
- Boards remain Fizzy entities, but membership is computed from Beads labels projected into MySQL via the Card mirror.
- Columns remain Fizzy entities, but placement is derived primarily from Beads `issues.status` (mirrored to `cards.beads_status`), with optional label-driven refinement for custom columns.
- Access remains a Fizzy-side concern (no Beads coupling), and all queries must be satisfiable from MySQL (no cross-DB joins).

Three third-lens priors from Gemini are explicitly enforced:
1) §C query plans MUST use Card mirror + label joins (MySQL), no cross-DB joins.
2) §G single-board invariant must spec both halves: controller write-time enforcement + poller ingestion drift correction.
3) §C default-column ↔ Beads status mapping must be crisp so new boards have consistent out-of-box workflow.

---

## §A — Board projection model

TODO

## §B — Column projection model

TODO

## §C — Card placement query plan (MySQL-only)

TODO

## §D — Controller surface for V1 (Board/Column/Access)

TODO

## §E — Pin projection

TODO

## §F — Kanban + List view query patterns + AC

TODO

## §G — Single-board invariant enforcement (write-time + ingestion-time)

TODO

## §H — Open questions deferred to later spec rounds

TODO

## §I — Child bead inventory

TODO

## §J — Validation checklist

TODO

