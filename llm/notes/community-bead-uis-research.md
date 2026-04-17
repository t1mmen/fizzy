# Community Beads UIs — Pattern Library

**Date**: 2026-04-17
**Scope**: research input for P10 (fork posture + community-bead-UI lessons), per CEO Q5b authorization to absorb query/mutation patterns (not visual language) from existing community Beads UIs.
**Method**: read-only web research via Explore subagent. No repos cloned.

---

## Executive summary

Six mature community Beads UIs investigated, plus BeadBoard (multi-agent orchestration). Three architectural categories:

- **Terminal UIs**: Mardi Gras (Go+BubbleTea), Perles (Go+custom-BQL)
- **Web UIs**: Beads UI (Node.js+CLI+file-watch), Beads-Web (Rust+Next.js+embedded), BeadBoard (Next.js+Dolt+SSE multi-agent)
- **Native apps**: Beads Task-Issue Tracker (Tauri+Vue+Rust), Beadbox (Tauri+React+SQLite hybrid)

Three core architectural patterns that converge across implementations:
1. Multi-source data access (CLI + Dolt SQL + JSONL fallback)
2. File watching for real-time sync (instead of polling)
3. Multi-view projection (same data, multiple lenses: kanban / tree / list / graph)

Query patterns stable across implementations: list/filter (with boolean logic), search across fields, dependency traversal, aggregations. Mutation patterns consistent: create, update, link, atomic claim.

Visual language varies widely; **per CEO Q5b we keep Fizzy's design language** and only absorb query/mutation semantics.

---

## Per-target findings

### 1. Mardi Gras (terminal)
- **Repo**: https://github.com/quietpublish/mardi-gras
- **Stack**: Go 99.2%, BubbleTea v2 (Elm Architecture), Lipgloss v2, single binary via GoReleaser
- **Beads access**: dual-mode. CLI primary (`bd list --json` every 5s). JSONL fallback (`.beads/issues.jsonl`, mtime poll every 1.2s, no OS watchers).
- **Read patterns**: CLI-driven; filters at CLI level
- **Write patterns**: **read-only** (deliberate; users exit to shell for mutations)
- **Schema mapping**: status → "parade" sections (Rolling/Lined Up/Stalled/Past the Stand)
- **Surface**: ID, title, status, priority (implicit), epic hierarchy
- **Useful**: graceful CLI→JSONL fallback pattern
- **Pitfall**: read-only limits workflows; 5s poll feels laggy

### 2. Perles (terminal)
- **Repo**: https://github.com/zjrosen/perles
- **Stack**: Go 97.4%, custom terminal UI, Beads v0.62+
- **Beads access**: direct Dolt SQL via custom **BQL (Beads Query Language)** compiler
- **Read patterns**: boolean logic (`is:open AND priority > 2 AND label:backend`), date filters, dep traversal, multi-view (kanban/tree/list)
- **Write patterns**: **read-only**
- **Schema mapping**: kanban (status), tree (parent_id), filtered list
- **Useful**: BQL as DSL hides SQL; multi-view coexistence; boolean filtering is expected by users
- **Pitfall**: BQL syntax not fully docs; no mutation UI

### 3. Beads UI (web)
- **Repo**: https://github.com/mantoni/beads-ui
- **Stack**: Node.js (92%) + CSS, local server daemon (`bdui start`), browser → localhost
- **Beads access**: file watching `.beads/dolt/` + CLI for mutations + push to UI clients
- **Read patterns**: Issues/Epics/Board views; multi-workspace auto-discovery (recursive `.beads/` scan)
- **Write patterns**: inline edit modal → CLI mutation; keyboard-driven (no mouse needed)
- **Schema mapping**: 3 projection views (issues flat / epics tree / board kanban)
- **Useful**: file watching + push beats polling; multi-workspace auto-discovery; keyboard-first
- **Pitfall**: local-only (no team sharing); fragile on networked filesystems

### 4. Beads-Web (web)
- **Repo**: https://github.com/weselow/beads-web
- **Stack**: Next.js 14 (React 18, TS, Tailwind, Radix, dnd-kit) embedded in Rust/Axum binary via rust-embed
- **Beads access**: dual-source. Local Dolt → direct SQL + file watcher + SSE. Remote Dolt → polling.
- **Read patterns**: kanban board, dashboard with status donuts, epic progress bars, GitOps PR browsing, search/filter/sort across projects
- **Write patterns**: drag-drop status mutations (dnd-kit) → `bd update --status`; inline field editing via CLI
- **Schema mapping**: kanban columns = status enum
- **Useful**: Rust + embedded frontend = single executable, no deploy headache; dnd-kit for drag-drop; SSE for push; GitOps integration novel
- **Pitfall**: kanban-only (no tree); polling for remote Dolt may lag

### 5. Beads Task-Issue Tracker (native, superseded by PaiR)
- **Repo**: https://github.com/w3dev33/beads-task-issue-tracker
- **Stack**: Tauri 2 + Nuxt 4 (Vue 3, TS) + shadcn-vue + Tailwind 4
- **Beads access**: native OS file watchers (no polling) + CLI for mutations
- **Read patterns**: live list, multi-field filter, attachment browse (custom `.beads/attachments/`)
- **Write patterns**: modal form → CLI invocation → JSON parsed back to UI state; synchronous
- **Useful**: Tauri 2 = excellent cross-platform desktop; native file watchers feel snappy; CLI-wrapping ensures CLI/UI consistency
- **Pitfall**: synchronous CLI invocations block UI; succession to PaiR suggests scaling/maintenance burden

### 6. Beadbox (native)
- **Repo**: https://github.com/beadbox/beadbox
- **Stack**: Next.js + React + Tauri + Rust + SQLite
- **Beads access**: file watching + hybrid (SQL for reads, CLI for writes)
- **Read patterns**: epic tree with progress bars, real-time sync ("within milliseconds"), multi-workspace tabs
- **Write patterns**: likely CLI (not docs'd in detail)
- **Useful**: epic tree + progress bars for project health; multi-workspace tabs; hybrid read/write optimizes latency while keeping consistency
- **Pitfall**: no documented conflict resolution for concurrent writes

### 7. BeadBoard (multi-agent orchestration)
- **Repo**: https://github.com/zenchantlive/beadboard
- **Stack**: Next.js 15 (App Router, React 19, TS strict) + Tailwind + Radix + Framer Motion + Dolt + Chokidar + SSE + bb-pi (Mario Zechner agent fork)
- **Architecture**: 3 layers — UI (dashboard) → Orchestration (bb CLI + bb-pi runtime) → Data (Dolt + JSONL)
- **Beads access**: multi-source — CLI for mutations, Dolt SQL for queries, JSONL for cold-start, file watcher (`.beads/last-touched` marker) → SSE
- **Read patterns**: SQL aggregations (dep graphs, ready-work), Social/Graph/Activity/Swarm dashboards, work reservations with conflict detection
- **Write patterns**: `bd create`, `bd dep add`, `bd update --claim` atomic, structured messages stored as beads with metadata, evidence requirements via labels
- **Schema mapping**: molecules (DAG of work), messaging-as-beads (threads via parent-child), work reservations as state dimensions, evidence-requirements cached in labels
- **Useful**: Dolt SQL + JSONL fallback robust; Chokidar + SSE proven; `.beads/last-touched` marker pattern clever (avoids polling); work-reservation model novel; messaging-as-beads elegant
- **Pitfall**: high complexity (orchestration-first, not lightweight); SSE can overwhelm browsers if updates burst; evidence-via-labels feels like workaround for missing gates

---

## Synthesis: patterns to absorb (query/mutation only)

Per CEO Q5b — visual language is Fizzy's domain, NOT to be copied. Below are *query/mutation* and *architecture* patterns worth considering for the Fizzy fork:

### A. Data-access patterns (informs P3)

1. **Dual-mode CLI + Dolt SQL with JSONL fallback** — robust across environments. Lean toward direct SQL for performance; CLI for write-side hooks; JSONL for offline.
2. **File watching + SSE push** — sub-second latency vs 5s polling. Marker file pattern (`.beads/last-touched`) avoids fs-event-flood when many tables change.
3. **Hybrid read/write split** (Beadbox, Beads-Web): SQL for reads (fast aggregations); CLI for writes (preserves bd hooks/audit). Strongest pattern for our use case.
4. **Multi-source fallback graceful degradation** (Mardi Gras): CLI → JSONL if CLI unavailable. Worth it for resilience.

### B. UI/UX patterns (informs P4)

5. **Multi-view projection of same data** — kanban + tree + list + graph. Users want lenses, not single views. Strong recommendation for Fizzy v1: kanban primary, list secondary; tree/graph deferred to v2.
6. **Inline editing modal pattern** — click field → modal → save → mutation → refresh. Cleaner than `contenteditable`; explicit save intent. Used by Beads UI, Beads-Web.
7. **Keyboard-driven navigation** — all ops via hotkeys; modals keyboard-navigable; Ctrl+K for search. Developer-targeted UX.
8. **Drag-drop kanban with dnd-kit** (Beads-Web) — proven library; status mutations on drop.
9. **Multi-workspace tabs / auto-discovery** (Beads UI, Beadbox) — users juggle multiple Beads projects. Even single-tenant Fizzy installs may benefit if a user runs multiple repos.
10. **Epic tree + progress bars** (Beadbox) — `parent_id` hierarchy with `(closed children) / (total children)` aggregation. Compact project-health view.

### C. Mutation / consistency patterns (informs P3+P5+P6)

11. **CLI-wrapping for write-side consistency** — every mutation through `bd` ensures audit/events fire correctly. Faster reads via direct SQL OK; writes must go through CLI (or hand-craft event emission).
12. **Atomic work claims with reservations + TTL** (BeadBoard) — `bd update --claim` already does this; useful for multi-agent. We are already using it.
13. **Batch mutations via Dolt transactions or CLI batch flags** — power-user feature; defer to v2.
14. **Messaging-as-beads** (BeadBoard) — comments / agent messages / evidence requests stored as child beads. Elegant; collapses comments into the same model. Worth considering for Q-S-019 + Q-S-021 evolution. (V1 keeps Fizzy comments table per Q4a; v2 might absorb.)

### D. Architecture patterns (informs P2+P3 + later infra rounds)

15. **Tauri + frontend (Vue or React)** — proven cross-platform desktop. Single binary. Several community implementations chose this. Relevant if Fizzy's deploy target ever pivots to desktop (CEO Q7c deferred).
16. **Rust + embedded frontend in single binary** (Beads-Web) — extreme deployment simplicity. Not directly applicable to Fizzy (we are locked Rails per Q7a), but the pattern (one-process app distribution) is interesting.
17. **Local Node.js / Rails daemon + browser** — pragmatic for local-first. This is exactly what Fizzy is today.

---

## Storage / query patterns table

| Pattern | Latency | Queryability | Offline | When to use |
|---|---|---|---|---|
| CLI shell-out (`bd list --json`) | 100-500ms | Limited (CLI filters) | Yes (JSONL) | Lightweight clients, write-side hooks |
| Direct Dolt SQL | 10-50ms | Full relational | No (needs Dolt) | Complex dashboards, aggregations |
| JSONL polling | 1-5s | None (client-side filter) | Yes | Fallback / offline / static views |
| File watch + SSE | <100ms | Depends on backend | Yes (local) | Real-time UI sync |

**Fizzy recommendation (preliminary, P3 will finalize)**: file watch + SSE for local; SQL for reads via Trilogy/Mysql2 connecting to local Dolt server; CLI for writes; JSONL fallback for resilience. Effectively the BeadBoard / Beadbox hybrid pattern, adapted to Rails.

---

## Anti-patterns / pitfalls (avoid)

1. **Polling at 5s for dynamic UIs** → use file watching
2. **Synchronous CLI blocking the UI thread** → wrap in background jobs (Solid Queue) or async controllers
3. **No conflict resolution for concurrent writes** → rely on Dolt cell-level merge OR add app-level conflict detection
4. **Single-view-only UI** → users want kanban + list + tree
5. **Mutations bypassing CLI** (raw SQL writes) → break audit/events; if doing it, hand-craft event emission
6. **Evidence-via-labels** as gates substitute (BeadBoard pattern) → ok as workaround; if v2 implements gates properly, supersede
7. **Status as the only grouping dimension** → projects vary (priority-first, assignee-first, epic-first); support multiple groupings in v1.5+
8. **No keyboard shortcuts** → developers expect hotkeys
9. **Naive remote-Dolt polling** → add backoff, pooling, query caching
10. **Ignoring offline scenarios** → keep JSONL export live as a fallback path

---

## Patterns to explicitly NOT absorb

Per CEO Q5b — visual language stays Fizzy's. Do not copy:

- Parade theme (Mardi Gras) — whimsical, not Fizzy brand
- Beads-Web color/styling
- Icon and emoji choices (Beadbox progress bar style, BeadBoard swarm visualizations)
- Component library forced choices (Radix / shadcn / Framer Motion) — Fizzy chooses its own
- BQL syntax (Perles) — interesting but introduces a learning curve

**Principle**: absorb the *semantics* (kanban-cols-mapped-to-status, tree-from-parent_id, multi-view-on-same-data), render with Fizzy's existing design language.

---

## Feed-forward (which P-rounds use which findings)

- **P3 (data-path decision)**: §A patterns 1-4 + storage table. Strong evidence for hybrid CLI-write + SQL-read + JSONL-fallback.
- **P4 (UI projection)**: §B patterns 5-10. Multi-view + inline-edit + keyboard-first + drag-drop kanban + epic-tree-progress.
- **P6 (lifecycle adapter)**: §C pattern 11. CLI for mutations preserves bd events.
- **P8 (events two-way sync)**: §C patterns 11+14. CLI write triggers bd events; Fizzy reads from `events` table for outbound webhooks.
- **P10 (fork posture)**: this whole doc; cite as research artifact in §F deliverable.
