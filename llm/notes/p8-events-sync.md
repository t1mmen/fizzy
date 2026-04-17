# P8 — Events two-way sync (Fizzy ↔ Beads)

**Status**: drafting (P8 round in flight)  
**Bead**: `fizzy-bcr`  
**Drafter**: `fizzy-codex`  
**Reviewers**: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)  
**Brief**: `llm/notes/p8-brief.md`

This decision doc closes Q-S-005 (webhook triggers for bd CLI changes), Q-S-021 (canonical events log), and Q-S-022 (webhook V1 survival posture). It builds on P3 (hybrid data path: SQL reads + bd CLI writes), P5 (actor attribution via `bd --actor`), and P6 (lifecycle adapter emits bd mutations).

---

## §A — Ground truth: current event systems (Fizzy + Beads)

### A.1 Fizzy `Event` model + usage (confirmed from code)

Core model: `app/models/event.rb`
- Schema shape: polymorphic `eventable`, plus `board`, `creator`, `action`, and `particulars` JSON.
- `Eventable#track_event` is the main constructor (`app/models/concerns/eventable.rb`):
  - `board.events.create!(action: "#{eventable_prefix}_#{action}", creator:, board:, eventable: self, particulars:)`
  - `eventable_prefix` is the demodulized underscored class name (e.g. `Card` → `card`).

Critical side effects:
- `Event` runs `after_create -> { eventable.event_was_created(self) }`.
  - `Card::Eventable#event_was_created` (`app/models/card/eventable.rb`) creates a system comment and touches `last_active_at` (unless just published).
  - `Comment::Eventable#event_was_created` (`app/models/comment/eventable.rb`) touches the card’s `last_active_at`.
- `Event` runs `after_create_commit :dispatch_webhooks` which enqueues `Event::WebhookDispatchJob`.

`particulars` shape:
- `Event::Particulars#api_particulars` (`app/models/event/particulars.rb`) special-cases a few actions:
  - `card_assigned` / `card_unassigned` → `assignee_ids`
  - `card_board_changed` / `card_title_changed` / `card_triaged` → nested old/new fields
  - everything else → `{}`.

### A.2 Fizzy `Webhook` model + delivery pipeline (confirmed from code)

Subscription model: `app/models/webhook.rb`
- Board-scoped: `belongs_to :board`, and `Webhook::Triggerable` scopes to `where(board: event.board)` + `subscribed_actions LIKE "%\"#{action}\"%"`.
- Permitted action strings (currently hard-coded) include: `card_assigned`, `card_closed`, `card_postponed`, `card_auto_postponed`, `card_board_changed`, `card_published`, `card_reopened`, `card_sent_back_to_triage`, `card_triaged`, `card_unassigned`, `comment_created`.

Dispatch:
- `Event::WebhookDispatchJob` (`app/jobs/event/webhook_dispatch_job.rb`) iterates `Webhook.active.triggered_by(event)` and calls `webhook.trigger(event)`.
- `Webhook::Triggerable#trigger` (`app/models/webhook/triggerable.rb`) creates a `Webhook::Delivery` row.

Delivery execution:
- `Webhook::Delivery` (`app/models/webhook/delivery.rb`) is an async state machine (pending → in_progress → completed/errored), with stored request/response JSON.
- It signs payloads using HMAC SHA256 and includes `X-Webhook-Signature` and `X-Webhook-Timestamp` headers.
- `after_create_commit` enqueues `Webhook::DeliveryJob` which calls `delivery.deliver`.

### A.3 Beads `events` + `comments` tables (confirmed empirically via bd sql)

Beads `events` table shape (`bd sql 'DESCRIBE events'`):
- `id` char(36) primary key (uuid)
- `issue_id` varchar(255)
- `event_type` varchar(32)
- `actor` varchar(255)
- `old_value` text (nullable)
- `new_value` text (nullable)
- `comment` text (nullable)
- `created_at` datetime default current_timestamp

Beads `comments` table shape (`bd sql 'DESCRIBE comments'`):
- `id` char(36) primary key (uuid)
- `issue_id` varchar(255)
- `author` varchar(255)
- `text` text
- `created_at` datetime default current_timestamp

Observed `events.event_type` values (probe issue created and mutated locally):
- `created` on `bd create`
- `updated` on `bd update` field changes (including assignee updates)
- `status_changed` on `bd defer` / `bd undefer`
- `closed` on `bd close`
- `reopened` on `bd reopen`
- `label_added` / `label_removed` on `bd tag` and `bd update --add-label/--remove-label`
The probe issues used to collect these examples were deleted afterward via `bd delete --force` to keep the workspace database clean.

Important nuance for adapter semantics:
- `bd update --add-label/--remove-label` and `bd tag` create `label_added`/`label_removed` events.
- `bd label add/remove` did NOT create an `events` row in our probe (it does mutate labels, but the audit trail differs). For consistent auditing, prefer the `bd update` flags (as already chosen in P7).
- `bd create --ephemeral` created an issue but did not create a `created` event row (ephemeral issue behavior). This matters if we ever ingest events for ephemeral/wisp entities.

---

## §B — The problem statement (why events sync matters)

### B.1 The asymmetry introduced by P3 (bd CLI writes)

In the fork, writes to task state happen by shelling out to `bd` CLI. That means:
- Beads `events` records the change, but Fizzy may not.
- Fizzy webhooks/notifications/activity feed may not fire if they depend on Fizzy `Event` creation hooks.

### B.2 What “two-way sync” means in v1

Define explicitly:
- Fizzy → Beads: every state mutation initiated in Fizzy produces a Beads event (already true via `bd`)
- Beads → Fizzy: changes that happen outside Fizzy (direct `bd` use, integrations) should appear in Fizzy UI and trigger any configured “activity/webhook” mechanisms we keep in v1

---

## §C — Canonical events log decision (Q-S-021)

### C.1 Options

- (a) Canonical = Beads `events` (+ `comments`); Fizzy `events` becomes an optional projection for UI/webhooks.
- (b) Canonical = Fizzy `events`; Beads `events` treated as internal (in tension with “Dolt/Beads is source-of-truth”).
- (c) Hybrid canonical: Beads canonical for issue/task state; Fizzy canonical for non-task domain events (e.g. auth/session/account admin).

### C.2 Decision

**Decision: Canonical change/audit log for beads-backed task state is Beads (`events` + `comments`). Fizzy `events` is a derived projection (when we need it for UI/webhooks), not the source of truth.**

Rationale:
- CEO ground truth: Dolt-backed beads schema is immutable and the source of truth for task data.
- All task mutations in the fork are executed via `bd` (P3), so Beads `events` is the only log that is guaranteed to exist for every write path.
- Fizzy `Event` rows are not “pure logs”: they carry side effects (`eventable.event_was_created`) and they enqueue webhooks. That makes them a poor canonical log to replay/ingest from.
- A canonical log must be safe to ingest/replay; Beads `events` is closer to that.

Consequence:
- If we need Fizzy’s existing webhook/notification pipeline for beads-backed changes, we must implement a safe projection/ingestion layer from Beads → Fizzy (see §D), and we must make it idempotent and side-effect controlled.

---

## §D — Beads → Fizzy ingestion strategy (fix Q-S-005)

### D.1 Requirements

TODO:
- No missed events (idempotent)
- Resilient to restarts
- Low operational complexity for single-tenant
- Does not require beads schema changes

### D.2 Candidate mechanisms

- (a) **Poller job in Rails (recommended)**: periodically query Beads `events` and `comments` since the last cursor; for each unseen record, create a *projection* record (either a Fizzy `Event`, or a new `BeadsEvent` projection table) and trigger any downstream side effects (webhooks, notifications) intentionally.
- (b) `bd` hook → Rails endpoint: configure beads hooks to POST into the Rails app after each mutation (higher coupling; needs hook install discipline and secure ingress).
- (c) Dolt commit tailing: treat Dolt commits as change batches and diff tables between commits (more complex than needed for single-tenant v1).

### D.3 Decision

**Decision: Define an ingestion design now (poller job), but do NOT ship webhook-trigger ingestion in V1 (webhooks deferred).**

This closes the core ambiguity (what we would do) without taking on v2 scope (operational webhooks for all external writes).

When/if we implement ingestion (v2+), the minimal safe shape is:
- Cursor storage: a singleton row in a Fizzy table (e.g. `beads_ingestion_cursors`) storing:
  - last_seen_beads_event_created_at
  - last_run_at
  - optionally: lookback window seconds (for re-scan safety)
- Idempotency key: store `beads_event_id` (and `beads_comment_id`) on the projection record with a unique index.
  - This allows re-scanning with a lookback window without duplicating work.
- Ordering: process by `(created_at ASC)` and accept that UUID `id` does not provide reliable intra-timestamp ordering.
  - Use “created_at lookback + idempotency” rather than “strict cursor by id”.
- Backfill: on first enablement, scan all Beads events since “system start date” (or since last Dolt compact boundary) and project only the subset we care about (see §F/§E).

Open design constraint (v1 consequence to surface, v2 must solve):
- Fizzy `Webhook` is board-scoped and `Event` requires `board_id`.
- Our fork has an “Inbox” state where an issue has **no** `fizzy/board/*` label yet (P6). Board cannot be derived for those events.
  - Recommendation: if/when webhook ingestion ships, only project/trigger webhooks for events where board membership is known; inbox events do not trigger board webhooks.

---

## §E — Webhooks posture (Q-S-022)

### E.1 V1 posture choice

- (a) **Deferred in V1 (recommended)**: webhooks remain as an upstream concept (tables + UI can exist), but we do not guarantee correct delivery for beads-backed state changes and we do not design “external bd writes trigger webhooks” yet.
- (b) Partial V1: webhooks work only for changes initiated by Fizzy UI (because those create Fizzy `Event` rows and dispatch).
- (c) Full V1: webhooks work for all changes (requires ingestion job from §D).

### E.2 Recommendation + rationale

**Recommendation: (a)/(b) hybrid — treat webhooks as v2 scope, but keep existing behavior for Fizzy-initiated actions as a non-goal-compatible “free carry”.**

Rationale:
- CEO direction: webhooks deferred to v2+.
- The safe ingestion design (idempotent, board-aware, callback-safe) is tractable but non-trivial; shipping it prematurely increases risk.
- Keeping existing webhook codepaths intact for Fizzy-initiated events keeps the fork closer to upstream and provides a ready-to-enable path later.

---

## §F — Activity feed / timeline posture (UI impact)

The existing Fizzy activity feed is built on `Event` rows and their `Event::Description` rendering.

Constraints:
- Creating Fizzy `Event` rows as a projection of Beads changes will, by default, trigger:
  - `eventable.event_was_created` (system comments, last_active touches)
  - webhook dispatch (`after_create_commit`)
- That means naive mirroring is unsafe; we must either:
  - bypass callbacks (e.g. `insert_all`-style projection + explicit dispatch decisions), OR
  - avoid using Fizzy `Event` as the primary timeline for beads-backed changes and instead read directly from Beads `events` + `comments`.

V1 posture recommendation:
- For beads-backed cards, continue to show timeline entries for actions initiated via Fizzy UI (since we already create the local `Event` row in-process).
- Do not attempt to mirror external `bd` actions into the Fizzy timeline in V1.
- Spec round should decide whether to build a Beads-native activity panel (reads Beads `events` + `comments`) as the long-term direction.

---

## §G — Failure modes + mitigations

TODO list:
- polling lag
- duplicate events
- cursor corruption
- bd history compaction / restore
- actor missing / ambiguous identity mapping

---

## §H — Resolved Q-S items (links back to P1)

- **Q-S-021 — Canonical events log (Fizzy `events` vs Beads `events`): which is canonical?** → ANSWERED. Canonical for beads-backed task state is Beads (`events` + `comments`). Fizzy `events` is a derived projection when needed for UX/webhooks. See §C.
- **Q-S-022 — Webhook V1 survival?** → ANSWERED. Deferred to v2+; existing webhooks may continue to function for Fizzy-initiated events, but we do not promise “external bd writes trigger webhooks” in V1. See §E.
- **Q-S-005 — Webhook trigger when state changes via bd CLI (not Fizzy controller)?** → ANSWERED. Not supported in V1 (webhooks deferred). When webhooks are reintroduced, we must implement Beads→Fizzy ingestion or a Beads-native webhook emitter. See §D.

---

## §I — New questions for spec rounds (if any)

> **Q-S-054 — If/when we project Beads events into Fizzy, how do we avoid `Event` callbacks (system comments, last_active, webhook dispatch) from firing twice or creating loops?**
> Options: (a) projection table + new UI; (b) `insert_all` into `events` + explicit dispatch; (c) add an explicit “projected” flag to bypass callbacks. Spec round owns.

> **Q-S-055 — Board attribution for inbox events: should an issue be required to have a board label at creation time (no boardless inbox), or do we accept boardless events that cannot trigger board webhooks?**
> This impacts webhook semantics and event rendering; spec round owns.

> **Q-S-056 — Should Beads comments generate Beads events, or do we treat comments as a second canonical log stream and merge in UI?**
> Current bead behavior observed: `bd comment` writes to `comments` but did not create an `events` row. Spec round decides merge strategy.

---

## §J — Validation checklist (pre-lock)

- [ ] Ground truth extracted from Fizzy code for Event/Webhook models + delivery
- [ ] Beads `events` DDL captured with example rows for common mutations
- [ ] Canonical log decision made; consequences stated
- [ ] Ingestion strategy concrete (cursor/idempotency/ordering)
- [ ] Webhook V1 posture explicit; no “silent missing triggers”
- [ ] Q-S-005/021/022 marked ANSWERED with pointers
