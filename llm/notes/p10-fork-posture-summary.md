# P10 — Fork Posture Summary (Final Planning Synthesis)

**Status**: drafting (P10 round in flight)
**Bead**: `fizzy-5ol`
**Drafter**: `fizzy-codex`
**Reviewers**: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/p10-brief.md`

This document is the final Planning-round synthesis. It confirms the fork posture, closes Q-S-007 (import/export) and Q-S-027 (backup strategy), consumes community Beads UI research as a cross-check, and produces a single “spec readiness” view that the Spec phase (S1–S10) can build on.

---

## §A — Fork posture confirmation (hard fork, no merge-back)

This fork posture is the non-negotiable foundation for Spec/Implementation. It is derived from CEO ground truths (captured in `llm/LOG.md`) and the P1–P9 locked decisions.

### A.1 CEO ground truths (quoted from LOG)

- **Fizzy is the canonical UI for Beads** (“Fizzy = canonical UI for Beads”; Beads data sovereign). (`llm/LOG.md:139-144`)
- **Dolt is source-of-truth for all task data**; **Beads schema is immutable** (we conform; we do not mutate). (`llm/LOG.md:140-142`)
- **Single-tenant installs only**; multi-tenancy is retired. (`llm/LOG.md:141-142`)
- **Hard fork; no merge-back**. Absorb only query/mutation semantics from community Beads UIs; keep Fizzy visual language. (`llm/LOG.md:144`)
- **V1 scope**: core CRUD + associations + comments + typical task workflow; orchestration layer (gates/molecules/formulas/swarms/federation) is v2+. (`llm/LOG.md:130`)

### A.2 P-round doctrines (what Planning actually decided)

- **Data sovereignty**: Beads/Dolt is canonical for tasks; Fizzy MySQL holds non-task concerns + projections. (P1 §C; P3; P8; P9)
- **Read/write split**: SQL reads via Dolt SQL server (Trilogy `:beads` connection); **all task mutations via `bd` CLI** (preserves hooks/events/audit). (`llm/notes/p3-data-path-decision.md`)
- **Actor attribution**: every `bd` invocation includes a global argv prefix `bd --actor <email> ...` (never env var). (`llm/notes/p5-auth-bridging.md`)
- **UI projection**: Board and Column stay as Fizzy entities, backed by Beads labels/status. V1 ships **Kanban + List** (list is accessibility anchor). Board membership uses reserved label namespace `fizzy/board/<board_uuid>`. Single-board-per-issue invariant preserved. (`llm/notes/p4-ui-projection-deep-dive.md`)
- **Lifecycle**: status transitions are Beads-native (`issues.status` + `defer_until` + `closed`), with Fizzy-side entropy config driving system-actor CLI writes. (`llm/notes/p6-lifecycle-adapter.md`)
- **Tags/labels**: Beads labels are canonical; Fizzy Tag survives as display/normalization object, but its string maps 1:1 to Beads label. `fizzy/*` prefix reserved for system labels. (`llm/notes/p7-multi-assignee-tags-labels.md`)
- **Search + filters**: UI search stays Fizzy 16-shard FTS over a **Card mirror projection** (no cross-DB joins). Beads is canonical; Fizzy runs a 30s poller that mirrors Beads into Card/Comment/Closure/Tagging via callback-bypassing upserts and explicit Search::Record writes. (`llm/notes/p9-search-strategy.md`)
- **Events**: canonical event log is Beads `events` + Beads `comments` (two streams); Fizzy `Event` becomes either a dropped table or a UI-only projection in v2. Webhook bridging is explicitly deferred. (`llm/notes/p8-events-sync.md`)

## §B — Import/export posture (Q-S-007)

Q-S-007 is “What is the export/import story for the fork?” The answer has to match CEO posture: V1 is about getting the fork product working, not back-compat with upstream.

### B.1 Decision

- **V1**: **fresh installs only**. No upstream-Fizzy ZIP import, no “account export” feature parity. Any upstream Fizzy data is treated as disposable in the fork.
- **V1 task-data egress**: **use `bd export`** (JSONL) as the canonical task export path; keep it CLI-driven (no Fizzy UI export workflow in V1).
- **V2+**: if we ever support migration from upstream Fizzy → fork, it is a **separate, opt-in import path** that requires a mapping strategy for IDs and for Fizzy-side projections/sidecars.

### B.2 V2+ candidate migration strategies (for completeness)

These are the three strategies surfaced in P3 (kept here as a registry; no further decision required in V1):

- **I-a — Disposable**: declare “no migration from upstream”; only new installs. Lowest cost.
- **I-b — Mapping table (recommended if migration is required)**: introduce a mapping table that links old Fizzy UUIDs to new Beads ids (string). Allows sidecars (attachments, ActionText, notifications) to remap.
- **I-c — Drop sidecars**: import only core task data (title/status/priority) into Beads; drop or ignore attachments/rich text/history. Lower implementation cost, higher user loss.

P3 reference: `llm/notes/p3-data-path-decision.md` §E (import strategies).

## §C — Backup strategy posture (Q-S-027)

Q-S-027 is “backup strategy.” In this project, “backup” has two scopes:
(1) **project artifacts** (code + `llm/` docs + skills) and (2) **task DB state** (Beads Dolt).

### C.1 Decision

- **V1 (local-dev only)**: `git push` is the load-bearing backup mechanism for **everything in the repo**, including planning/spec docs.
- **Beads task backup today**: the repo includes `.beads/issues.jsonl` (generated by `bd export` / hooks), which is committed and pushed — this acts as an off-machine “task snapshot” even while `bd dolt push` is broken.
- **Beads full-fidelity DB backup (preferred)**: `bd dolt push` should push the full Dolt repo state for off-machine recovery, but it is **currently broken** (known from R0). Fix in a future plumbing round (R-plumbing-2). Until then, treat it as best-effort and non-blocking for Planning/Spec work.

### C.2 Practical “V1 backup” runbook (what we actually do)

- For artifacts: follow `skills/session-lifecycle.md` close protocol (commit + `git pull --rebase` + `git push`).
- For tasks: ensure `.beads/issues.jsonl` is up to date (it is produced automatically during commits in this repo; verify with `wc -l .beads/issues.jsonl`).
- For emergency off-machine restore today: in a fresh clone, run `bd import` from `.beads/issues.jsonl` (exact import command/flags to be validated in spec/impl; P10 does not introduce new CLI behavior).

## §D — Community Beads UI cross-check (absorbed patterns)

This section cross-checks `llm/notes/community-bead-uis-research.md` against what P3–P9 decided. The goal is: “did we miss any community-stable query/mutation semantics?”

| Community pattern | Adopted? | Where it lands (or why deferred) |
|---|---|---|
| 1) **Hybrid read/write split** (SQL reads + CLI writes) | Yes | Core doctrine in P3: `llm/notes/p3-data-path-decision.md`. |
| 2) **Multi-source data access** (SQL + CLI; JSONL as resilience) | Partial | SQL+CLI proven in P2+P3. JSONL is present as `.beads/issues.jsonl` backup; UI fallback is deferred until needed. |
| 3) **Multi-view projection** (kanban + list; tree later) | Yes | P4: V1 ships Kanban + List, list is accessibility anchor; tree/graph deferred. |
| 4) **File watching + SSE push** for sub-second UI freshness | Deferred | Explicitly queued as Q-S-035 (P3). V1 uses polling cadence (P9: 30s tick). |
| 5) **Drag-drop kanban status mutation** → `bd update --status` | Yes (semantic), impl deferred | P4 commits to kanban; P6 defines lifecycle transitions via CLI. Actual DnD library choice is an implementation detail (Spec/Impl). |
| 6) **Inline editing modal + explicit save intent** | Yes (already Fizzy-native) | Fizzy already uses explicit edit flows; spec rounds should keep that discipline when adding beads-backed fields. |
| 7) **Keyboard-driven UX** | “Match Fizzy” | We do not copy community hotkey schemes, but we keep Fizzy’s a11y/keyboard standards (CEO Q9). P4 list view supports keyboard-first browsing. |
| 8) **Epic tree + progress aggregation** (`parent_id` + child counts) | Deferred | P4 answers hierarchy rendering (Q-S-031) but keeps epic-progress UI as v2 polish; may become a Spec add-on if cheap. |
| 9) **Atomic claim / reservation semantics** | Yes | We already use `bd update --claim` operationally; UI can surface the same semantics in v1. |
| 10) **Batch mutations** (`bd batch`, bulk edits) | Deferred | Explicitly out of v1; queued as v2 polish, overlaps rate-limit Q-S-052 and multi-write atomicity note in P3. |

**Missed patterns worth explicitly tracking:** community UIs repeatedly recommend file-watcher invalidation for freshness. We have Q-S-035 for it; P10 confirms it should stay in the deferred registry (not forgotten).

## §E — Reserved follow-ups registry (deferred / v2+)

This is the explicit “won’t do in V1” registry. These items should not be accidentally pulled into S1–S10 unless the CEO overrides scope.

### E.1 Explicit v2+ deferrals (CEO scope + P-round findings)

- **Orchestration layer** (gates/molecules/formulas/swarms/federation): v2+ per CEO Q4a. (Not a Q-S id; included here because it is the largest hidden scope risk.)
- **Q-S-022** — Outbound webhook bridging for Beads-driven state changes: v2+ (P8 keeps webhooks as a concept but defers implementing the bridge).
- **Q-S-033** — Branch-aware connection pooling strategy (only matters once we introduce branches): v2+ (from Dolt adapter research).
- **Q-S-035** — File watcher + SSE for UI freshness: v2+ (P9 uses 30s poller for v1).
- **Q-S-036** — CLI fork cost scaling under load: v2+ (v1 local-dev; revisit before multi-user SaaS-like scale).
- **Q-S-043** — Inbound webhooks auth model: v2+ (explicitly not in v1).
- **Q-S-044** — Token rotation UX for bearer tokens: v2+ (no external integration surface required in v1 beyond what exists).
- **Q-S-052** — Adapter write rate limiting for bulk operations: v2+ unless v1 UX requires bulk-tagging.

### E.2 Plumbing rounds required (not Spec rounds)

- **R-plumbing-2**: fix `bd dolt push` (backup-only) failure discovered in R0 (`llm/notes/r0-dolt-cleanup.md`).

## §F — Spec-phase readiness checklist (S1–S10 preconditions)

This is a proposed S1–S10 shape; the CEO can reorder, merge, or split. The important part is: each spec has explicit input artifacts and explicit “done” outputs (perfect beads).

| Proposed Spec round | Owns | Requires (inputs) | Must produce |
|---|---|---|---|
| **S1 — Card id + FK migration spec** | Q-S-002a / Q-S-011 tombstone | P1 §A FK inventory; P3 §E migration posture | Perfect bead(s) for per-table migration sequence + safety checks + rollback plan |
| **S2 — Board/Column/Access projection spec** | P4 decisions into implementation plan | P4; P1 entities (Board/Column/Access) | Beads-backed controller/query plan + UI acceptance criteria |
| **S3 — Auth + actor propagation spec** | Q-S-004 + Q-S-045 | P5; existing auth code refs | Exact `CommandClient` API + job-actor propagation design + tests |
| **S4 — Lifecycle + entropy spec** | Q-S-013..016 + Q-S-049/050 | P6 | Exact CLI argv table; status transitions; entropy job rules |
| **S5 — Labels + assignees spec** | Q-S-017/018 + Q-S-051 | P7; P4 label namespace | Sidecar tables + invariants + removal semantics |
| **S6 — Rich text + comments spec** | Q-S-012 + Q-S-019 | P1; Beads comments schema | Canonical storage of HTML vs plaintext; mirror plan; mention parsing |
| **S7 — Attachments + storage quotas spec** | Q-S-025 + Q-S-026 | P1 attachments + storage models | How ActiveStorage record_id becomes string; quotas posture |
| **S8 — Events + activity feed + (deferred) webhooks** | Q-S-021 + Q-S-054..056 | P8 | Poller requirements + loop-avoidance plan; what UI reads |
| **S9 — Search + filter + poller spec** | Q-S-023/024 + Q-S-057..059 | P9 | Mirror schema (Card/Comment/Closure/Tagging) + poller algorithm + drift handling |
| **S10 — Metadata boundary spec** | Q-S-002 + Q-S-032 | P1 mapping table; P3 | Rulebook: “metadata vs sidecar table” + reserved key namespaces |

**Note**: Import/export and backup posture are already decided at Planning level (P10 §B/§C). If a Spec round is needed, it should be strictly “implementation details” (UI copy, command wiring), not re-litigating posture.

## §G — Resolved Q-S tally (answered vs deferred)

### G.1 ANSWERED in Planning (P-round lock list)

Each item here should be treated as settled; Spec rounds convert them into perfect beads, but should not re-open the decision without CEO override.

- **Q-S-001 / Q-S-001a / Q-S-002a** — data-path + FK migration posture → P3 (`llm/notes/p3-data-path-decision.md`)
- **Q-S-003 / Q-S-009 / Q-S-010 / Q-S-028 / Q-S-029 / Q-S-030 / Q-S-031 / Q-S-038 / Q-S-039 / Q-S-040 / Q-S-041 / Q-S-042** — UI projection → P4 (`llm/notes/p4-ui-projection-deep-dive.md`)
- **Q-S-004 / Q-S-006a / Q-S-008 / Q-S-046** — auth/actor + team posture → P5 (`llm/notes/p5-auth-bridging.md`)
- **Q-S-013 / Q-S-014 / Q-S-015 / Q-S-016** — lifecycle/entropy → P6 (`llm/notes/p6-lifecycle-adapter.md`)
- **Q-S-017 / Q-S-018 / Q-S-053** — labels + multi-assignee + CLI flags → P7 (`llm/notes/p7-multi-assignee-tags-labels.md`)
- **Q-S-005 / Q-S-021** — events/webhook-trigger mechanism and canonical events log → P8 (`llm/notes/p8-events-sync.md`)
- **Q-S-023 / Q-S-024** — search/filter strategy → P9 (`llm/notes/p9-search-strategy.md`)

### G.2 CLOSED BY P10

- **Q-S-007** — import/export posture → answered in this doc (§B).
- **Q-S-027** — backup posture → answered in this doc (§C).

### G.3 OPEN for Spec phase (V1 scope; not deferred)

These are the biggest “implementation-shaping” open questions we intentionally did not solve in Planning:

- **Q-S-002** — where Fizzy-side concerns live (sidecar tables vs metadata)
- **Q-S-006** — Account collapse mechanics (singleton implementation details)
- **Q-S-011** — tombstone / overlap with Q-S-002a (spec should treat as the same work item)
- **Q-S-012** — rich text source-of-truth for Card.description
- **Q-S-019** — comment rich text vs beads plaintext
- **Q-S-020** — Step/checklist survival
- **Q-S-025** — ActiveStorage attachment record_id string migration + bridging
- **Q-S-026** — storage totals/quotas posture in single-tenant
- **Q-S-032** — metadata vs sidecar boundary + reserved namespaces
- **Q-S-045** — propagate `Current.identity` in jobs (IdentityTenanted concern)
- **Q-S-047** — formal role-based authorization boundaries (owner-only ops)
- **Q-S-048 / Q-S-049 / Q-S-050** — last-active signal + standard argv table + pinned status
- **Q-S-051** — primary-assignee removal semantics
- **Q-S-054 / Q-S-055 / Q-S-056** — event mirroring loop avoidance + board attribution + comment/event merging
- **Q-S-057 / Q-S-058 / Q-S-059** — search drift detection + ephemeral issue handling + relevance normalization

### G.4 DEFERRED / v2+ (explicit won’t-do list)

See §E.1 (Q-S-022/033/035/036/043/044/052 plus orchestration layer).

## §H — Open questions to carry into spec phase

P10 does not add new questions beyond the open registry in §G.3. The Spec phase should treat §G.3 as its “question backlog”, and §E.1 as its “scope guardrails”.

If the CEO wants a shorter Spec backlog, the recommended triage is:
1) FK migration + mirrors (S1 + S9) — unblocks all other work.
2) Rich text + attachments (S6 + S7) — biggest UX mismatch risk.
3) Account singleton + identity propagation (S3 + S10) — correctness + operability.
