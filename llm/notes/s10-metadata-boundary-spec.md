# S10 — Metadata boundary spec (FINAL S-round)

Round / epic: `S10-metadata-boundary-spec` / `fizzy-e5m` (epic)  
Drafter: `fizzy-codex` • Peer: `fizzy-claude` • Third lens: `fizzy-gemini`

This is the **rulebook + audit** for where state lives in the fork:

- **Beads is canonical for task data** (schema immutable): `issues`, `events`, `comments`, `issues_labels`, plus Beads `issues.metadata` JSON.
- **Fizzy MySQL is a sidecar cache + UI substrate**: mirror tables (`cards`, `comments`, `tags`/`taggings`, `events`, `search_records_*`) and Fizzy-only tables (boards/columns/access, watches, pins, ActiveStorage, etc).

S10 does **not** re-litigate S1–S9 decisions; it codifies decision criteria and audits consistency. Any mismatch becomes an **open question** (future round), not a change here.

Inputs:
- P1 inventory: `llm/notes/p1-foundational-gap-inventory.md`
- Data-path: `llm/notes/p3-data-path-decision.md`
- Labels namespaces: `llm/notes/p7-multi-assignee-tags-labels.md` §C, `llm/notes/s5-labels-assignees-spec.md`
- Mirror doctrine: `llm/notes/p9-search-strategy.md` §A.2 and S9 poller spec `llm/notes/s9-search-filter-poller-spec.md`
- S4 reopen metadata precedent: `llm/notes/s4-lifecycle-entropy-spec.md` (metadata.fizzy.prior_status)
- S2 board/column projection: `llm/notes/s2-board-column-access-projection-spec.md` (reserved `fizzy/board/*` labels)
- S8 event dedup: `llm/notes/s8-events-activity-feed-spec.md`

---

## §A — Decision rulebook: Beads metadata vs Fizzy sidecar

### A.1 Terms (three buckets)

S10 classifies every concern into exactly one of:

1) **Beads canonical (non-metadata columns)**  
   Example: `issues.title`, `issues.status`, `issues.acceptance_criteria`.

2) **Beads canonical (metadata)**: `issues.metadata.fizzy.*`  
   Example: `metadata.fizzy.prior_status` (S4 reopen / restore).

3) **Fizzy sidecar-canonical** (MySQL-only)  
   Example: Boards/columns/access control; watches; pins; ActiveStorage.

Separately, Fizzy has **mirror caches** (MySQL tables that are rebuildable from Beads):
- `cards`, `comments`, `events` (activity feed), `tags`/`taggings`, `search_records_*`, `action_text_rich_texts` (derived HTML cache).

### A.2 Decision criteria (ordered, default-safe)

Given a new concern, decide in this order:

1) **Is it “task truth” that must be visible in Beads/CLI?**  
   If yes → Beads canonical (columns or metadata).  
   If no → Fizzy sidecar-canonical.

2) **Does it need to be indexed / queried frequently in the UI?**  
   If yes → prefer **mirror columns/tables** in MySQL (rebuildable) rather than Beads metadata-only.  
   If no → metadata is acceptable.
   - **Invariant**: any field used in a Fizzy `Filter` predicate MUST be sidecar-indexable in MySQL (S9). Beads metadata is not a request-time substrate for filters.

3) **Cardinality and shape**  
   - single scalar value (rarely queried) → metadata is usually best
   - many values / joins (tags, multi-assignee, watches) → sidecar table (or mirror table) is best

4) **Atomicity requirements**  
   - if multiple related values must change atomically for UI correctness, prefer a MySQL table/columns (single transaction), fed by poller.
   - if eventual consistency is acceptable, metadata is fine.

5) **Ownership / mutability**  
   - per-user state → never in Beads metadata; use sidecar (watches, pins, read/unread).
   - global system state → either metadata or sidecar depending on visibility/index needs.

### A.3 Default posture (V1 fork)

- **Beads is canonical** for: lifecycle/status, title, description/design/AC/notes, labels, events, comments.
- **Fizzy is canonical** for: boards/columns/access, watches, pins, ActiveStorage/storage quotas, search shards (cache), notifications (derived), webhooks (delivery config).
- Any concern that would cause “Fizzy-only noise” in Beads (e.g., per-user read markers) is prohibited in metadata.

---

## §B — Reserved namespaces registry

### B.1 `metadata.fizzy.*` JSON namespace (Beads)

`issues.metadata.fizzy` is reserved for Fizzy integration metadata stored in Beads (canonical, CLI-visible).

Rules:
- Only keys under `fizzy` are reserved by this project; do not write to arbitrary top-level metadata keys.
- Keys must be **stable** and **migration-friendly** (treat as public API for the fork).
- Values should be JSON scalars/objects (no large blobs).

Initial registry (from S1–S9):

| Key | Meaning | Written by | Read by | Notes |
|---|---|---|---|---|
| `metadata.fizzy.prior_status` | prior Beads status used to reopen/restore (S4) | CommandClient in UI restore/close flows | poller + any admin/debug | Rarely queried; ideal for metadata |

### B.2 `fizzy/*` label namespace (Beads)

Beads labels beginning with `fizzy/` are reserved system labels.

Rules:
- UI must reject users attempting to create/update/delete labels in reserved namespace (S5).
- Poller must still mirror reserved labels into MySQL Tag/Tagging to support UI projections (boards/columns) even though UI cannot create them.

Initial registry:

| Prefix / pattern | Meaning | Written by | Mirrored to MySQL? | Notes |
|---|---|---:|---:|---|
| `fizzy/board/<uuid>` | board membership label (S2) | system-only | yes (Tag/Tagging) | single-board invariant enforced by S9 |
| `fizzy/system/*` (reserved) | future system labels | system-only | yes | placeholder for expansion |

---

## §C — Audit of S1–S9 decisions vs rulebook

Legend:
- **PASS** = matches rulebook
- **OK (explicit exception)** = violates a criterion, but is documented and intentional
- **OPEN** = inconsistent / unspecified; needs a future decision (do not change in S10)

### C.1 High-frequency task truth (must be mirrored)

| Concern | Canonical | Fizzy MySQL role | Audit | Rationale |
|---|---|---|---|---|
| Issue title / status / close fields | Beads columns | `cards` mirror columns (S4/S9) | PASS | frequent UI query/filter/sort |
| Description / design / acceptance / notes | Beads columns | ActionText derived HTML cache + Search::Record content | PASS | canonical plaintext + rebuildable caches (S6/S9) |
| Comments | Beads canonical | `comments` mirror + ActionText cache + mentions/watch derivations | PASS | frequent UI + notifications |
| Labels | Beads canonical | `tags`/`taggings` mirror | PASS | filter + autocomplete |
| Events / audit | Beads canonical | `events` mirror for activity feed + dedup key | PASS | feed/webhooks/notifications require MySQL artifacts |

### C.2 Sidecar-canonical (Fizzy-only) concerns

| Concern | Canonical | Audit | Notes |
|---|---|---|---|
| Boards / columns / access control | Fizzy-only | PASS | projected into Beads via `fizzy/board/*` labels; board entities remain Fizzy |
| Watches (watchers) | Fizzy-only | PASS | per-user; never in Beads metadata |
| Pins | Fizzy-only | PASS | per-user; never in Beads metadata |
| ActiveStorage / storage quota / storage entries | Fizzy-only | PASS | Beads has no attachment model; quota enforcement in Fizzy (S7) |
| Notifications | derived | PASS | created via Notifier on mirrored Events/Mentions |
| Webhooks config + deliveries | Fizzy-only | PASS | outbound survives; inbound deferred |

### C.3 Hybrid / exceptions

| Concern | Canonical | Audit | Why |
|---|---|---|---|
| Multi-assignee | Fizzy sidecar-canonical + Beads mirrors primary | PASS | cardinality (many) favors sidecar; CLI sees primary |
| Board membership | Beads label canonical + Fizzy board entity canonical | PASS | label provides a canonical join key; board definition remains Fizzy-only |

### C.4 Unspecified or potentially inconsistent (OPEN)

| Concern | Current stance | Audit | What’s missing |
|---|---|---|---|
| Reactions | Fizzy-only sidecar-canonical | PASS | per-user and high-churn; storing in Beads metadata would create event noise with low CLI value (Gemini prior) |
| “Activity spike” / stall detection | upstream exists | OPEN | if still desired, mirror-mode guards need to preserve semantics; otherwise drop in fork |

---

## §D — Migration / write rules for metadata + reserved labels

### D.1 Metadata writes

All writes to Beads metadata must go through CommandClient with `bd --actor <email> ...` (S3), never via raw SQL.

Preferred mechanism (nested metadata safe):
- `bd update <id> --metadata '<json>'` where json is a full metadata object update.

Example (conceptual):
```bash
bd --actor user@example.com update fizzy-123 \
  --metadata '{"fizzy":{"prior_status":"open"}}'
```

Notes:
- `bd update --set-metadata key=value` exists, but does not document dotted/nested semantics; avoid for nested `metadata.fizzy.*` until proven.

### D.2 Reserved label writes

Reserved labels (`fizzy/*`) are written only by system code paths (controllers + poller drift correction) using CommandClient label methods, never user input.

---

## §E — Read rules (controllers + filters)

### E.1 Controllers / views

- Sidecar-canonical: AR reads directly.
- Mirrors: AR reads from MySQL mirror rows (cards/comments/events/tags/taggings).
- Metadata: read from Beads only if needed for rare display/debug; otherwise, if metadata is needed for filtering, it must be mirrored into a MySQL column explicitly in a future round (rulebook guardrail).

**Mirror-cache rule (Gemini prior)**: to avoid ad-hoc Beads SQL in UI views/controllers, S9 poller should mirror the entire `metadata.fizzy` bucket into a single MySQL JSON column on `cards` (e.g. `cards.beads_metadata` or `cards.beads_metadata_json`). This column is for UI display/debug only and is not used for indexed filtering; any filterable metadata must be promoted to a dedicated MySQL column/index.

### E.2 Filter/search

Filters and search must compile entirely to MySQL (P9 + S9); never query Beads at request time.

---

## §F — Deprecated / prohibited patterns

Do not:
- store per-user state in Beads metadata (pins/watches/read/unread)
- create a Fizzy sidecar table for a single scalar that is only rarely referenced (prefer metadata)
- write to `issues.metadata` outside `metadata.fizzy.*` namespace
- allow user-created labels under `fizzy/*`
- depend on Beads metadata at request time for UI filtering/sorting (mirror it if needed)

---

## §G — Test strategy

S10 itself is mostly docs. Any I-S10 code should have:
- unit tests for reserved namespace checks (labels + metadata key guards)
- CommandClient tests for metadata JSON write
- poller tests ensuring metadata writes do not break mirror idempotency (if metadata affects mirrors)

---

## §H — Open questions (S10-owned)

1) Should “activity spike” detection remain in the fork? If yes, mirror-mode guards must preserve semantics; if no, we should deprecate it explicitly.
2) Confirm best-practice for nested metadata updates (`--metadata` JSON merge vs replace semantics).
3) Decide the exact `cards` JSON column name and mirroring semantics for `metadata.fizzy` (replace vs deep-merge) and document it in S9/I-S9.

---

## §I — Child bead inventory

Child beads minted under epic `fizzy-e5m` (see `bd children fizzy-e5m` after minting).

---

## §J — Validation checklist

- [x] §A rulebook criteria defined
- [x] §B reserved namespaces registry covers `metadata.fizzy.*` and `fizzy/*` labels
- [x] §C audit covers S1–S9 major concerns and flags OPEN items without re-litigating
- [x] §D write protocol defined (CommandClient + --actor; metadata JSON posture)
- [x] §E read protocol defined (no request-time Beads queries)
- [x] §F prohibited patterns listed
- [x] §G test strategy described (for any I-S10 code)
- [x] §H open questions enumerated
- [ ] child beads minted under `fizzy-e5m` (~6–10)
- [ ] `[CODEX→CLAUDE S10 v1 ready]` dispatched + peer review complete
- [ ] `[FROM→TO S10: agreed]` 3-of-3 lock
