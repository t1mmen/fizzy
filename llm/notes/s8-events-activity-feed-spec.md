# S8 — Events + activity feed + deferred webhooks spec

Round / epic: `S8-events-activity-feed-spec` / `fizzy-n3l` (epic)  
Drafter: `fizzy-codex` • Peer: `fizzy-claude` • Third lens: `fizzy-gemini`

This spec is implementation-ready for I-S8: it defines how we mirror **canonical Beads change history** (Beads `events` + `comments`) into Fizzy’s **UI-facing cache** (`Event` rows driving Activities/timeline, outbound webhooks, and notification fanout).

Scope guard:
- Canonical: Beads (`issues`, `events`, `comments`, `issues_labels`)
- UI cache: MySQL (`cards`, `comments`, `events`, `notifications`, `webhook_deliveries`)
- Poller mechanism: **S9** owns “how to poll”. S8 specifies **what to mirror** + idempotency contracts.

Inputs:
- P8: `llm/notes/p8-events-sync.md`
- Poller doctrine: `llm/notes/p9-search-strategy.md` §A.2 (callback-bypass upsert_all + explicit sync)
- Lifecycle write paths: `llm/notes/s4-lifecycle-entropy-spec.md`
- Label/assignee write paths: `llm/notes/s5-labels-assignees-spec.md`
- Rich text/comments write paths + mention derivations: `llm/notes/s6-rich-text-comments-spec.md`
- Fizzy code anchors: `app/models/event.rb`, `app/models/concerns/notifiable.rb`, `app/models/notifier/*.rb`, `app/models/webhook.rb`, `app/jobs/event/webhook_dispatch_job.rb`, `app/controllers/activities_controller.rb`

---

## §A — Beads → Fizzy event mapping (what we mirror)

### A.1 Beads event sources (ground truth)

Beads has two canonical audit sources relevant to the Fizzy activity feed:

1) `events` table (issue-level audit events), schema:
- `id` (char(36) uuid)
- `issue_id` (varchar Beads id)
- `event_type` (varchar) — observed types include `created`, `updated`, `closed`, `label_added`
- `actor` (string) — **must be treated as opaque**, but our app-generated writes will pass email via `bd --actor <email>` (S3)
- `old_value` / `new_value` (text; for `updated` this is JSON snapshots)
- `comment` (text; for `label_added`, label text is commonly embedded in comment, e.g. `Added label: spec`)

2) `comments` table (append-only issue comments), schema:
- `id` (char(36) uuid)
- `issue_id` (varchar)
- `author` (string)
- `text` (plaintext)
- `created_at`

### A.2 Fizzy activity feed actions (what the UI renders)

The feed is currently backed by `ActivitiesController::ACTIONS` (`app/controllers/activities_controller.rb`) and queries:
`Current.user.accessible_events.preloaded.where(action: ACTIONS)...reverse_chronologically`.

Therefore S8 defines a mapping that only produces these `Event.action` values (existing allowed surface in `Webhook::PERMITTED_ACTIONS` too):
- `card_assigned`, `card_unassigned`
- `card_closed`, `card_reopened`
- `card_postponed`, `card_auto_postponed`
- `card_board_changed`
- `card_published`
- `card_sent_back_to_triage`, `card_triaged`
- `card_title_changed`
- `comment_created`

Anything else is **not mirrored into `events` rows** in V1.

### A.3 Canonical “event id” for dedup (Beads event vs Beads comment)

We introduce a single, unique “Beads-origin correlation id” stored in MySQL:

- New column: `events.beads_event_id` (varchar)
- Format:
  - For Beads `events` rows: `event:<beads_events.id>` (optionally with a suffix when **one** Beads event maps to **multiple** Fizzy Events, e.g. reassignment: `event:<id>:unassign` and `event:<id>:assign`)
  - For Beads `comments` rows: `comment:<beads_comments.id>`

This provides a single unique key for idempotency + loop avoidance across both canonical sources.

### A.4 Mapping table (Beads canonical → Fizzy Event rows)

All mirrored Fizzy `Event` rows are created with:
- `eventable` = `Card` for card_* actions; `Comment` for comment_created
- `board` = resolved board context for the card at the time of mirroring (see §C.2)
- `creator` = mapped from Beads `actor`/`author` string (see §B.3)
- `created_at` = canonical timestamp from Beads (`events.created_at` / `comments.created_at`)
- `particulars` = action-specific payload (must match existing `Event::Particulars` expectations; see §A.5)
- `beads_event_id` = §A.3 formatted key

| Canonical source | Detection | Fizzy `Event.action` | `eventable` | Particulars |
|---|---|---|---|---|
| Beads `events` | `event_type=created` | `card_published` | `Card` | `{}` |
| Beads `events` | `event_type=closed` OR (updated snapshot shows status→closed) | `card_closed` | `Card` | `{}` |
| Beads `events` | updated snapshot shows status closed→open | `card_reopened` | `Card` | `{}` |
| Beads `events` | updated snapshot shows `defer_until` nil→ts | `card_postponed` OR `card_auto_postponed` | `Card` | `{}` |
| Beads `events` | updated snapshot shows `defer_until` ts→nil OR ts→different ts | (V1) no feed event; poller just updates caches | n/a | n/a |
| Beads `events` | updated snapshot shows title change | `card_title_changed` | `Card` | nested payload (`old_title`, `new_title`) |
| Beads `events` | updated snapshot shows assignee nil→value | `card_assigned` | `Card` | `assignee_ids` |
| Beads `events` | updated snapshot shows assignee value→nil | `card_unassigned` | `Card` | `assignee_ids` |
| Beads `events` | updated snapshot shows assignee value(A)→value(B) | **two** events: `card_unassigned` then `card_assigned` | `Card` | `assignee_ids` (first A then B) |
| Beads `events` | label_added/removal changes a `fizzy/board/*` label | `card_board_changed` | `Card` | nested payload (`old_board`, `new_board`) |
| Beads `events` | derived column moves nil→col | `card_triaged` | `Card` | nested payload (`column`) |
| Beads `events` | derived column moves col→nil | `card_sent_back_to_triage` | `Card` | `{}` |
| Beads `comments` | new comment row | `comment_created` | `Comment` | `{}` |

### A.5 Particulars payload shapes (must match existing code)

Existing Fizzy code expects two distinct shapes:

1) Assignment events store top-level `assignee_ids`:
- `Event::Particulars` has `store_accessor :particulars, :assignee_ids` (`app/models/event/particulars.rb`)
- Card SystemCommenter reads `event.assignees` (`app/models/card/eventable/system_commenter.rb`)

2) Board/title/triage events store nested payload under the `particulars` key:
- `Event::Particulars#api_particulars` reads `nested = particulars.dig("particulars")` for:
  - `card_board_changed` (`old_board`, `new_board`)
  - `card_title_changed` (`old_title`, `new_title`)
  - `card_triaged` (`column`)

Therefore:
- `card_assigned` / `card_unassigned`: `particulars: { assignee_ids: [user_ids...] }`
- `card_title_changed`: `particulars: { particulars: { old_title:, new_title: } }`
- `card_board_changed`: `particulars: { particulars: { old_board:, new_board: } }`
- `card_triaged`: `particulars: { particulars: { column: } }`
- everything else: `{}`.

---

## §B — Loop avoidance + dedup (hard requirements)

### B.1 What “loop avoidance” means in this fork

In V1 fork posture:
- Canonical writes (UI) go to Beads via CommandClient + `bd ...` (S3/S4/S5/S6).
- MySQL (`cards`, `comments`, `events`, `taggings`, `assignments`, ...) is a **mirror cache** rebuilt by S9 poller (P9 doctrine: callback-bypass upsert_all + explicit side effects).

Therefore the only legitimate writer of mirrored `Event` rows for cards is the **poller**.

The “loop” risk is:
- poller sees the same canonical Beads row multiple times (repeat poll; restarts; backfill), and
- accidentally creates multiple Fizzy `Event` rows → double notifications + double webhooks.

### B.2 DB-level idempotency: unique index on `events.beads_event_id`

Implementation must add:
- `events.beads_event_id` (nullable)
- unique index on it (allow nulls)

Dedup rule:
- poller **must never** `destroy` or “edit” an existing Event; it should only create missing rows and then stop.
- when one Beads event maps to multiple Fizzy Events (e.g. reassignment), the mapper must assign **distinct** `beads_event_id` values via a suffix (see §A.3) so each derived Event row can still be deduped independently.

### B.3 Actor/author mapping (creator attribution)

When mirroring, we must produce a valid `events.creator_id` (non-null FK).

Mapping rule (ordered):
1) If Beads actor/author string matches an Identity email exactly, use that `User` row.
2) Else, if it matches a `User.name` exactly and uniquely, use that user.
3) Else, fall back to Account system user (S3 install-time system user).

Attribution requirement (Gemini prior):
- creator resolution must happen **before** `Event.create!` so that:
  - `Notifiable` fanout uses correct creator (`app/models/notifier.rb`)
  - `Event::WebhookDispatchJob` payload uses correct creator (`webhooks/event` template uses `event.description_for`)

### B.4 Mirrored events must not “mutate Card via callbacks” (last_active_at risk)

Important code path:
- `Event.after_create -> { eventable.event_was_created(self) }` (`app/models/event.rb`)
- `Card::Eventable#event_was_created` calls `touch_last_active_at` which uses `update!` (callbacks) (`app/models/card/eventable.rb`)
- `Comment::Eventable#event_was_created` calls `card.touch_last_active_at` too (`app/models/comment/eventable.rb`)

This conflicts with the mirror doctrine (poller writes bypass callbacks).

I-S8 must therefore avoid callback-driven writes when **poller-originated** Event creation triggers `touch_last_active_at`.

Decision (minimize ripple vs upstream semantics):
- Keep existing callback semantics for **normal interactive writes** (non-poller), unless and until the fork removes the upstream “activity spike” feature (which currently depends on `last_active_at_changed?` callbacks).
- Add an explicit “mirror mode” context signal (e.g. `Current.beads_mirror?`), and implement:
  - if `Current.beads_mirror?` is true: `touch_last_active_at` uses callback-bypass update (`update_columns`/`update_all`)
  - else: preserve current behavior (use `update!`) to avoid unintentional behavior changes for non-poller paths

The poller (S9) and any mirror-only code paths must set this context around `Event.create!` (and other mirror writes) so the “mirror mode” branch is taken.

### B.5 “Exactly once” side effects on retries

With B.2 uniqueness, a failed poller retry should result in “no new Event row”, and therefore:
- no re-fired webhook deliveries (since `Webhook::Delivery.after_create_commit` is on the Delivery row)
- no re-created notifications (since Notifier jobs are triggered by Notifiable after Event create)

Open question (deferred): reconciliation when an Event row exists but side-effect jobs did not enqueue (process crash between commit and job enqueue). See §H.

---

## §C — Activity feed UI contract (pagination, scoping, timestamps)

### C.1 Query surface (existing)

The activities feed uses:
- `Current.user.accessible_events` (through boards, `app/models/user/timelined.rb`)
- `.preloaded` eager-loading (`app/models/event.rb`)
- `.where(action: ACTIONS)` (`app/controllers/activities_controller.rb`)
- `.reverse_chronologically` ordering (`app/models/event.rb`)

S8 does not change this query; it ensures poller-created Events satisfy these expectations.

### C.2 Board scoping (critical for access control)

Because `accessible_events` is “events through boards”, every mirrored Event must have:
- correct `board_id` for the card at the **time of the canonical action**

For many events this is “current board”.
For board-change events (`card_board_changed`) this must be:
- board_id = *new* board (for forward progress), and
- particulars include old/new board names.

This implies the poller must:
- determine board membership label deltas over time for each issue, and
- set board_id accordingly when creating the Event row.

S8 specifies this as a requirement; S9 implements the mechanism.

### C.3 Timestamp handling

Use Beads timestamps as canonical:
- `Event.created_at` = Beads `events.created_at` / `comments.created_at`
- Timezone: store UTC in DB; Rails renders in user tz as today.

---

## §D — Outbound webhooks (V1: survive intact; mirror triggers once)

### D.1 Current pipeline (existing code)

- Every `Event` queues `Event::WebhookDispatchJob` `after_create_commit` (`app/models/event.rb`).
- Dispatch job finds relevant webhooks via:
  - `Webhook.active.triggered_by(event)` (board + action match; `app/models/webhook/triggerable.rb`)
  - `Webhook#trigger` creates `Webhook::Delivery` rows (`app/models/webhook/triggerable.rb`)
  - Delivery rows auto-enqueue `Webhook::DeliveryJob` (`app/models/webhook/delivery.rb`)

### D.2 V1 rule

- Poller-created (mirrored) Events **must** trigger outbound webhooks exactly once.
- With `events.beads_event_id` uniqueness, a Beads-origin action creates at most one Event row → at most one webhook dispatch.

No special-case “poller webhook pipeline” is introduced; we reuse existing code by creating the Event row normally.

---

## §E — Inbound webhooks (deferred)

Inbound webhooks (external → Fizzy → Beads) remain deferred to V2+ (P8 posture, Q-S-022).

S8 explicitly does **not** specify inbound webhook verification/signing or Beads write behavior.

---

## §F — Notification triggers (watch + mention behavior)

### F.1 Event notifications (card events + comment events)

`Event` includes `Notifiable` (`app/models/event.rb`), which schedules `NotifyRecipientsJob` after create commit.

Recipients are computed by the eventable-specific Notifier:
- card events: `Notifier::CardEventNotifier` (`app/models/notifier/card_event_notifier.rb`)
- comment events: `Notifier::CommentEventNotifier` (`app/models/notifier/comment_event_notifier.rb`)

Therefore, mirrored Events (created via `Event.create!`) automatically produce:
- `Notification` rows (idempotent per user+card, with source updated on repeat) and
- bundling side effects (Notification#bundle + recurring bundle delivery).

### F.2 Mention notifications (comments + descriptions)

Mentions are derived from Beads plaintext by S6 (poller/controller path):
- After comment mirror write, schedule mention parsing job (S6 §F.4).
- Mention notifier emits notifications separate from Event notifier.

S8 only requires that poller preserves ordering:
- Upsert comment mirror row (S6 contract)
- Run mention derivation (S6 contract)
- Create comment_created Event row (S8 contract)

### F.3 Bundled email delivery (Gemini prior)

To ensure CLI-origin writes generate bundled email deliveries promptly, poller may enqueue:
- `Notification::Bundle.deliver_all_later` (`app/models/notification/bundle.rb`)

This is optional in V1 (recurring delivery already exists), but S8 recommends it as a low-risk “make it prompt” improvement.

---

## §G — Test strategy (S8-owned vs S9-owned)

S8 tests focus on:
- mapping correctness
- dedup behavior
- webhook + notification side effects from mirrored Events

Poller mechanics tests belong to S9, but S8 defines contracts to make them testable.

### G.1 Unit tests (I-S8)

- `Fizzy::Beads::EventMapper` (pure function):
  - input: beads event row + (optional) prior snapshot
  - output: `{ action:, eventable_type:, particulars:, created_at:, beads_event_id: }` or nil
- `Fizzy::Beads::ActorMapper`:
  - email match → user
  - name match → user (unique only)
  - fallback → system user

### G.2 Integration tests (I-S8)

- Given a mirrored Beads comment and a mirrored comment_created Event:
  - a Notification is created for watchers (excluding author + mentionees)
- Given a mirrored Event and a Webhook subscribed to its action:
  - one Webhook::Delivery row is created (and enqueues job)
- Dedup:
  - mirroring same beads_event_id twice does not create a second Event

---

## §H — Open questions deferred (Q-S-S8-*)

1) Reconciliation when `Event` exists but side-effect jobs were not enqueued (crash window).  
2) Backfill strategy for historical Beads events (initial import; S9 might do “create events for last N days”).  
3) Actor string fidelity: do we store raw Beads actor/author on the Event row for UI display when creator_id falls back?  
4) Board-at-time-of-event correctness vs “current board”: required by access control, but may need per-issue event replay.

---

## §I — Child bead inventory (I-S8 implementation tasks)

Child beads are minted under epic `fizzy-n3l` and cover:
- schema changes (`events.beads_event_id` + unique index)
- mapping + attribution logic
- “callback-safe” last_active_at update
- integration tests for notifications/webhooks/dedup
- S9 dependencies for poller hook points

Beads (children of `fizzy-n3l`):
- `fizzy-n3l.1` — S8 F.1 — Add events.beads_event_id + unique index (dedup key)
- `fizzy-n3l.2` — S8 F.2 — Map Beads actor/author string → User (creator attribution)
- `fizzy-n3l.3` — S8 F.3 — Implement Beads events→Fizzy Event mapper (card_* actions)
- `fizzy-n3l.4` — S8 F.4 — Mirror Beads comments into comment_created Event rows
- `fizzy-n3l.5` — S8 F.5 — Make Card#touch_last_active_at callback-safe for poller-created Events
- `fizzy-n3l.6` — S8 F.6 — S9 poller hook: mirror Beads events/comments into Events + enqueue side effects
- `fizzy-n3l.7` — S8 F.7 — Integration test: mirrored Events trigger outbound webhooks once
- `fizzy-n3l.8` — S8 F.8 — Integration test: mirrored Events create Notifications + bundle window
- `fizzy-n3l.9` — S8 F.9 — Unit+integration tests: Event dedup via beads_event_id
- `fizzy-n3l.10` — S8 F.10 — Activities feed: ensure mirrored Events are visible (board scoping + preloads)

---

## §J — Validation checklist

- [x] §A mapping table covers ActivitiesController actions; particulars shapes match `Event::Particulars`.
- [x] §B dedup strategy is DB-backed and works for both Beads events and Beads comments.
- [x] §C board scoping requirement stated clearly (access control depends on it).
- [x] §D outbound webhooks posture reuses existing pipeline; no double-fire.
- [x] §E inbound webhooks explicitly deferred.
- [x] §F notifications + mentions cross-linked and ordering constraints stated.
- [x] §G tests cover mapping + dedup + side effects.
- [x] Child beads (8–12) minted under `fizzy-n3l` with correct deps (S3/S4/S5/S6/S9).
