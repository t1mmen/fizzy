# P4 — UI Projection Deep-Dive: Fizzy Kanban onto Beads

**Status**: drafting (P4 round in flight)  
**Bead**: `fizzy-1bc`  
**Drafter**: `fizzy-codex`  
**Reviewers**: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)  
**Brief**: `llm/notes/p4-brief.md`  

This doc answers the *UI projection* questions from P1 §E.2 for V1:
Q-S-003, Q-S-009, Q-S-010, Q-S-028, Q-S-029, Q-S-030, Q-S-031.

It is constrained by P3’s data-path decision: **SQL reads via Trilogy, CLI writes via `bd`** (`llm/notes/p3-data-path-decision.md`).

---

## §A — Board model decision (Q-S-003, Q-S-009)

### A.1 Decision

**Board survives as a first-class Fizzy entity.**

However, the meaning of “Board.cards” changes:

- **Upstream Fizzy**: cards are rows in Fizzy DB (MySQL/SQLite) and belong to a board via `cards.board_id`. See `app/models/card.rb` and `app/models/board.rb`.
- **Fork**: cards are Beads issues. A board is a **saved lens** over Beads issues, backed by a **Beads label namespace** that defines membership.

Concretely:

- Each Board has a stable **system board-membership label**, e.g. `fizzy/board/<board_uuid>`.
- An issue is “on board X” iff it has that label for X.

This aligns with CEO direction that Beads is source-of-truth for task data while keeping Fizzy’s board-centric UX intact.

### A.4 Board membership cardinality (Q-S-039)

**Decision (V1): enforce exactly-one-board membership per issue.**

Even though labels *could* represent multi-board membership, upstream Fizzy is “one card belongs to one board”. V1 keeps that invariant to preserve the Fizzy mental model and avoid UI ambiguity (an issue cannot be simultaneously in two board workflows).

Mechanically, the adapter will enforce:
- The board-membership label namespace is exclusive (exactly one `fizzy/board/*` label per issue).
- “Move issue to board Y” = remove existing `fizzy/board/*` label(s), then add `fizzy/board/<board_uuid>` for Y.

Multi-board membership remains a v2+ decision if we ever explicitly choose to shift semantics.

### A.2 Why not “Board collapses into Filter”

Fizzy is board-centric; `Board` is a primary entity with rich semantics (access, publishable, entropy, webhooks) even if those evolve. See `app/models/board.rb` includes `Accessible`, `Publishable`, `Entropic`, `AutoPostponing`, etc.

`Filter` is already a secondary cross-board lens, not a replacement for boards (`app/models/filter.rb`). Collapsing Board into Filter breaks navigation/IA and would force “board” to behave like a remembered search query.

### A.3 Why board membership should live in Beads (labels) instead of Fizzy DB

Given P3’s posture, if board membership is stored only in Fizzy’s sidecar DB:
- It becomes “task data” split across two databases (Beads for issue core; Fizzy for board membership).
- It complicates Beads-first tooling (CLI, federation/integrations) because an issue’s board cannot be reasoned about outside Fizzy.

Beads already has a native label join table:
- `labels(issue_id, label)` with an index on `label` (P1 §B DDL). This makes “board = label filter” efficient and conceptually aligned.

### A.5 Board label namespace choice (Q-S-038)

**Decision (V1): use `fizzy/board/<board_uuid>` as the canonical board-membership label namespace.**

Rationale:
- **Collision avoidance**: `fizzy/…` is a reserved/system prefix, less likely to collide with user labels.
- **Rename safety**: UUID survives board renames; the label remains stable.
- **Enforceability**: the adapter can reliably enforce “exactly one board label” by filtering on a reserved prefix.

UI note: this system label should be **hidden from “user tags” UI** by default (or rendered as a non-editable board indicator), otherwise users can accidentally break invariants by editing it manually.

---

## §B — Column model decision (Q-S-003, Q-S-010)

### B.1 Decision

**Column stays a Fizzy entity (per-board, positioned), but a column no longer “owns” cards via `cards.column_id`.**

Instead, each Column becomes a **mapping rule** from Beads issue state → column membership:

- **Primary grouping dimension for kanban = `issues.status`** (Beads-native).
- Column ordering stays Fizzy-side (per-board) via the existing `columns.position` mechanics (`app/models/column/positioned.rb`).

This yields:
- Beads stores the *canonical state* (status).
- Fizzy stores *projection metadata* (column label, color, ordering, which statuses appear in this board view).

### B.2 Column ordering storage (explicit Q-S-010 answer)

**Column position remains in Fizzy’s `columns.position` (per board).**

Rationale:
- Ordering is a UI choice (projection), not core issue state.
- Beads has no per-board column concept; forcing this into Beads `metadata` would create a large, noisy write surface and complicate CLI usage.
- We already have the correct per-board ordering mechanism today (`Column::Positioned`).

### B.3 How many columns does V1 support?

V1 supports **a small canonical workflow** (default 5 columns) and allows **optional additional columns** later via Beads `custom_statuses`.

Evidence that custom statuses exist:
- `custom_statuses(name, category)` table exists in Beads (P1 §B DDL).
- `blocked_issues` view treats statuses in categories `done`/`frozen` specially (P1 §B, `blocked_issues` view).

V1 recommendation:
- Start with default statuses (open/in_progress/blocked/deferred/closed).
- Treat “custom statuses” as a v1.5 / v2 feature unless CEO demands richer workflows immediately.

### B.4 V1 ships both Kanban + List views (Q-S-042)

**Decision (V1): ship a List view alongside Kanban.**

Rationale:
- Kanban is excellent for drag/drop and visual scanning, but is mouse-heavy.
- A List view is the **accessibility and keyboard-first anchor** (screen readers, quick navigation, bulk edits later).
- This aligns with the community “multi-view projection” pattern (kanban primary, list secondary) and with CEO Q9 quality bar: match Fizzy’s accessibility standards.

Scope:
- V1 List view is the same board lens (membership label + status filters), rendered as a simple table/list with keyboard navigation.
- Tree/graph remain v2+.

---

## §C — Status mapping (Q-S-003)

### C.1 Beads status ground truth (as observed in schema)

`issues.status` is a free string column with default `'open'` (P1 §B `issues` DDL). The ecosystem assumes at least:
- `open`
- `in_progress`
- `blocked`
- `deferred`
- `closed`

Additionally:
- Beads views reference `status='pinned'` explicitly (`blocked_issues` view filters out `pinned` by status). So **`pinned` must be treated as a possible status** even if it’s “special”.
- `custom_statuses` can define extra status names and categorize them (done/frozen/unspecified).

### C.2 Default V1 column set (Fizzy-native labels)

| Column (UI label) | Beads `issues.status` values shown | Notes |
|---|---|---|
| **Todo** | `open` + any custom status with category `unspecified` that the board opts into | Default landing state |
| **Doing** | `in_progress` | “Started” semantics eventually tie to `started_at` (lifecycle round) |
| **Blocked** | `blocked` | Also surface blockers summary from `dependencies` |
| **Not now** | `deferred` | Optional sub-signal: show `defer_until` |
| **Done** | `closed` + custom statuses with category `done`/`frozen` | “Done” categories are already a Beads concept |

### C.3 Where does `pinned` appear?

Recommendation (V1):
- **Pinned is not a column**; it’s a **board overlay section** (a small “Pinned” list above the kanban), because pinning is orthogonal to workflow.

If Beads uses `status='pinned'` in practice, V1 UI should still show those issues:
- Either in the Pinned overlay, or in a dedicated “Pinned” pseudo-column that is always top/left and excluded from WIP reasoning.

This becomes an explicit follow-up Q in §I if we see pinned used heavily.

### C.4 User customization scope

V1 user-customizable aspects:
- Column ordering (per-board, `columns.position`)
- Column display name + color (Fizzy-side)
- Board chooses which statuses appear (subset) (board config, Fizzy-side)

V1 not customizable:
- The canonical meaning of `open/in_progress/blocked/deferred/closed` (Beads-native semantics).

---

## §D — Card surface fields (Q-S-028, Q-S-029, plus P1 §C.13)

The following Beads-native fields exist in `issues` schema (P1 §B DDL) and should be visible in V1 UI.

### D.1 Minimal V1 surface (must-have)

Rationale: V1 must support “typical workflow” creation/editing of beads-native issues, and spec rounds require perfect-bead structure (acceptance criteria + design + notes) for downstream execution. Therefore these fields are must-have surfaces (at least in the detail view).

| Beads field | Where it lives | V1 UI surface | Notes |
|---|---|---|---|
| `title` | `issues.title` | Card title + edit-in-place modal | Matches existing Fizzy card title concept |
| `description` | `issues.description` | “Why” section in card detail | Current Fizzy uses rich-text description; we can render as plain text initially or keep rich-text in Fizzy sidecar (P6/P8 territory) |
| `acceptance_criteria` | `issues.acceptance_criteria` | Dedicated “Acceptance criteria” section | Beads-native; aligns with spec-first workflow |
| `design` | `issues.design` | Dedicated “Design” section | Keeps “how” explicit |
| `notes` | `issues.notes` | Notes / scratchpad section | Captures ongoing context |
| `status` | `issues.status` | Column + status dropdown | Drag-drop updates status via `bd update --status` |
| `priority` (0-4) | `issues.priority` | Priority pill / dropdown (P0..P4) | Resolves goldness (see §G) |
| `issue_type` | `issues.issue_type` | Type pill + filter | V1: show in card header; default `task` |
| `labels` | `labels` join table | Tags UI (existing Fizzy idiom) | V1 must include board membership label + any user labels |
| `parent_id` | `issues.parent_id` | Parent + children panel | See §F |

### D.2 Secondary V1 surface (nice-to-have but recommended)

| Beads field | V1 UI surface | Why |
|---|---|---|
| `estimated_minutes` | Estimate input | Supports planning/triage |
| `assignee` | Single assignee picker | V1 supports single assignee even if Fizzy later adds sidecar multi-assign |
| `due_at` | Due date | Useful workflow cue |
| `defer_until` | Defer until date | Integrates with “Not now” |

---

## §E — Dependencies UI (Q-S-030)

Beads supports 10 dependency types (P1 §B `dependencies.type` is string, default `blocks`).

### E.1 V1 minimum UI

V1 must support:
- **View** dependencies on issue detail (two lists: “Blocked by” and “Blocks”).
- **Create/remove** `blocks` dependencies via UI (CLI mutation behind adapter, per P3).

These satisfy “typical workflow” and match Beads’ `ready_issues` / `blocked_issues` view semantics.

### E.2 V1 recommended UI (all 10 types, grouped)

Ground truth for the 10 types (from `bd dep add --help`):
`blocks`, `tracks`, `related`, `parent-child`, `discovered-from`, `until`, `caused-by`, `validates`, `relates-to`, `supersedes`.

Proposed grouping for UI:

1) **Blocking / readiness**
- `blocks` (render as “Blocked by” / “Blocks”)

2) **Hierarchy / structure**
- `parent-child` (note: Beads also has `issues.parent_id`; V1 UI should primarily use `parent_id` for hierarchy and treat `parent-child` deps as a legacy/advanced relationship if encountered)

3) **Lifecycle / causality**
- `discovered-from`
- `caused-by`
- `validates`
- `until`
- `supersedes`

4) **Weak relationships / navigation**
- `tracks`
- `related`
- `relates-to`

UI posture:
- Show “Blocks / Blocked by” prominently.
- Other groups collapsed by default with counts.

### E.3 Kanban surface

In kanban columns:
- Add a small “blocked” badge if `blocked_by_count > 0` (or compute via join).
- Optionally show a mini count “2 blockers” linking to dependency panel.

---

## §F — Hierarchy UI (`issues.parent_id`) (Q-S-031)

Beads has explicit hierarchy via `issues.parent_id` and bookkeeping table `child_counters` (P1 §B DDL).

### F.1 V1 minimum

On issue detail:
- Parent link (if present).
- Children list (if any), showing `id`, `title`, `status`, and progress summary `(closed children) / (total children)`.

This adopts the “epic tree + progress bars” semantic (Beadbox pattern), without committing to a full tree UI in kanban yet.

### F.2 Kanban surface (optional)

In kanban cards:
- If issue has children: show a compact progress badge, e.g. `3/7`.
- Clicking opens the issue detail with children panel.

Full tree view is v2 (or later) unless V1 demands it.

---

## §G — Goldness vs priority resolution (Q-S-028)

### G.1 Decision

**Surface Beads `priority` and drop Fizzy `Goldness` as a first-class concept in the fork.**

Rationale:
- Priority is Beads-native and already indexed (`idx_issues_priority` in P1 §B DDL).
- Goldness is Fizzy-specific (`Card::Golden` concern) and not part of Beads’ immutable schema.
- V1 should avoid duplicating priority semantics (“golden” vs “P0”) and pick one ranking system.

### G.2 Migration / UX note

If we want to preserve a “golden” affordance in UI:
- Make it a derived view: “Golden = P0” (display-only), not a stored field.

---

## §H — Resolved Q-S items (links back to P1)

This doc answers the P1 questions and should be referenced from `llm/notes/p1-foundational-gap-inventory.md`:

- **Q-S-003** — Board+Column projection: Board = Fizzy entity + membership label filter; Column = Fizzy entity mapping to Beads status; membership computed from Beads status. (§A, §B, §C)
- **Q-S-009** — Board survives as entity (not collapsed into Filter). (§A)
- **Q-S-010** — Column ordering stored in Fizzy `columns.position` per board. (§B.2)
- **Q-S-028** — Priority replaces Goldness (golden becomes derived, if at all). (§G)
- **Q-S-029** — `issue_type` surfaced as type pill + filter in V1 card UI. (§D)
- **Q-S-030** — Dependencies: v1 minimum = blocks/blocked_by + add/remove; recommended = surface all 10 types grouped. (§E)
- **Q-S-031** — Hierarchy: v1 minimum = parent + children panel + progress summary; optional kanban badge. (§F)
- **Q-S-039** — Board membership cardinality: V1 enforces exactly one board label per issue. (§A.4)
- **Q-S-038** — Board label namespace: V1 uses `fizzy/board/<board_uuid>` reserved prefix. (§A.5)
- **Q-S-042** — List view: V1 ships Kanban + List (List is accessibility anchor). (§B.4)

---

## §I — Open questions for downstream rounds

New or sharpened questions surfaced by this projection:

> **Q-S-040 — How do we treat `status='pinned'` if it appears (overlay vs column)?**
> Schema/views reference it; we should confirm how bd uses it in practice and define UI.

> **Q-S-041 — Do we allow per-board custom status subsets, or is status-set global?**
> If custom statuses are global but boards show subsets, “move between columns” can set status to a value not present in other boards. UX decisions needed.

---

## Convergence signal (P4)

When all three agents agree P4 is complete, each sends:

`[FROM→TO P4: agreed]`

After all signals are in `llm/LOG.md`, this file is locked, bead `fizzy-1bc` is closed, and P5 is opened (auth & identity bridging).
