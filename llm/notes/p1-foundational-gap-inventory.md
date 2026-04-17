# P1 — Foundational Gap Inventory: Fizzy ↔ Beads

**Status**: drafting (P1 round in flight)
**Bead**: `fizzy-08o`
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
**Brief**: see `llm/notes/p1-brief.md` for scope and AC

This is the foundational input for all S1-S10 spec rounds. Every assertion is grounded with a `path:line` reference or a quoted command output. No paraphrase.

---

## §A — Fizzy domain entities

> **Status**: drafted by `fizzy-claude`; pending Codex peer review.
>
> Sources used: `db/schema.rb` (lines 1–859), `app/models/**/*.rb` (174 files), `app/views/**/_*.json.jbuilder`, `config/initializers/tenanting/account_slug.rb`, `config/routes.rb`. Every assertion is grounded with a file path and (where material) a line number or schema column name.

Grouped by domain area. Within each area: a one-paragraph "Domain notes" intro, then a table of entities with the columns Entity / Model file / Schema table / Key fields / Associations / State semantics / JSON shape / Purpose.

### A.1 Tenancy

**Domain notes.** Accounts are root tenant containers. Multi-tenancy is enforced at middleware (`config/initializers/tenanting/account_slug.rb`) — the URL path `/{external_account_id}/...` is rewritten to `SCRIPT_NAME` and `Current.account` is set for the request. Per CEO Q3 (ii), this multi-tenancy is **retired in the fork** (single-tenant installs). All other entities are scoped to account via FK; in the fork these become singletons or are dropped.

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `Account` | `app/models/account.rb` | `accounts` (schema:63) | `id` (uuid), `name` (string), `external_account_id` (bigint, unique), `cards_count` (bigint) | `has_many :users, :boards, :cards, :webhooks, :tags, :columns, :entropies, :exports, :imports` | `active?` scope (no cancellation, not importing); concerns: `Cancellable`, `Entropic`, `Incineratable`, `Searchable` | none | Root tenant |
| `Account::JoinCode` | `app/models/account/join_code.rb` | `account_join_codes` (schema:53) | `account_id`, `code` (string), `usage_count`, `usage_limit` (default 10) | `belongs_to :account` | `active?` when `usage_count < usage_limit` | none | Team invitation token |
| `Account::Cancellation` | `app/models/account/cancellation.rb` | `account_cancellations` (schema:28) | `account_id`, `initiated_by_id` | `belongs_to :account, :initiated_by` (User) | One per account; cascade with account | none | Soft-delete audit |
| `Account::ExternalIdSequence` | `app/models/account/external_id_sequence.rb` | `account_external_id_sequences` (schema:36) | `value` (bigint, unique) | none | Counter for external_account_id generation | none | Slug counter |
| `Account::Export` (STI) | `app/models/account/export.rb` | `exports` (type column) | inherits `Export` base | `has_one_attached :file`, `belongs_to :account, :user` | Status: pending → processing → completed/failed | none | Full account ZIP export |
| `Account::Import` | `app/models/account/import.rb` | `account_imports` (schema:41) | `account_id?`, `identity_id`, `status`, `failure_reason` | `belongs_to :account, :identity`, `has_one_attached :file` | Status: pending → processing → completed/failed; `failure_reason` enum: conflict / invalid_export | none | Full account ZIP import |

### A.2 Identity & auth

**Domain notes.** `Identity` (email-keyed) is the global login credential and can be in multiple Accounts (in upstream Fizzy). `User` is the per-account membership. `Session` and `Identity::AccessToken` carry auth — sessions for the cookie path, access tokens for the JSON API path (the latter is critical to §D item 8). `MagicLink` is the passwordless sign-in / sign-up mechanism.

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `Identity` | `app/models/identity.rb` | `identities` | `email_address` (unique), `staff` (bool) | `has_many :users, :sessions, :magic_links, :access_tokens`, `has_many :accounts, through: :users`, `has_passkeys`, `has_one_attached :avatar` | `before_destroy` deactivates linked users; concerns `Joinable`, `Transferable` | `app/views/my/identities/_account.json.jbuilder` | Global login credential |
| `Identity::AccessToken` | `app/models/identity/access_token.rb` | `identity_access_tokens` | `identity_id`, `token` (secure), `permission` (enum read/write), `description` | `belongs_to :identity` | `permission` enum gates HTTP method (GET/HEAD always; mutation needs write) | `app/views/my/access_tokens/_access_token.json.jbuilder` | Bearer token for JSON API |
| `Session` | `app/models/session.rb` | `sessions` | `identity_id`, `ip_address`, `user_agent` (max 4096) | `belongs_to :identity` | None — created at login, destroyed at logout | none | Cookie session record |
| `User` | `app/models/user.rb` | `users` | `account_id`, `identity_id?`, `name`, `role` (enum: member/owner/system), `active` (bool), `verified_at?` | `belongs_to :account`, `belongs_to :identity, optional: true`, `has_many :comments, :filters, :closures, :pins`, `has_many :pinned_cards, through: :pins`; concerns `Accessor`, `Assignee`, `Notifiable`, `Watcher` | Roles drive UI permissions; `system` user auto-created per account; `verified?` checks `verified_at` presence | `app/views/users/_user.json.jbuilder` | Account-scoped membership |
| `MagicLink` | `app/models/magic_link.rb` | `magic_links` | `identity_id`, `code` (6 chars, unique), `expires_at`, `purpose` (enum sign_in/sign_up) | `belongs_to :identity` | `active` scope: `expires_at >= Time.current`; consumed (destroyed) on use | none | Passwordless sign-in/up |

### A.3 Boards & columns

**Domain notes.** Boards group cards; columns are kanban swimlanes within a board. Column position is `integer`, ordered ascending. `Board::Publication` mints a public-share key. `Access` is per-(board, user) with two involvement levels (`access_only` / `watching`). `all_access` boolean on Board grants every account user access automatically.

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `Board` | `app/models/board.rb` | `boards` (schema:171) | `account_id`, `creator_id`, `name`, `all_access` (bool, default false) | `belongs_to :account, :creator (User)`, `has_many :columns, :cards, :events, :webhooks`, `has_many :tags, through: :cards`, `has_rich_text :public_description` | Concerns `Accessible`, `AutoPostponing`, `Filterable`, `Publishable`; `all_access=true` auto-grants every account user via `Accessible` | `app/views/boards/_board.json.jbuilder` | Kanban container |
| `Column` | `app/models/column.rb` | `columns` (schema:255) | `account_id`, `board_id`, `name`, `color`, `position` (integer, default 0) | `belongs_to :account, :board (touch: true)`, `has_many :cards, dependent: :nullify` | Concerns `Colored`, `Positioned`; touches all cards if name/color changes | `app/views/columns/_column.json.jbuilder` | Kanban swimlane |
| `Board::Publication` | `app/models/board/publication.rb` | `board_publications` (schema:160) | `account_id`, `board_id`, `key` (string, unique secure token) | `belongs_to :account, :board (touch: true)` | One per board or none | none | Public share link |
| `Access` | `app/models/access.rb` | `accesses` (schema:14) | `account_id`, `board_id`, `user_id`, `involvement` (enum access_only/watching), `accessed_at?` | `belongs_to :account, :board (touch), :user (touch)` | Unique per (board_id, user_id); `accessed_at` updated on view | none | Per-board ACL + recents |

### A.4 Cards & lifecycle

**Domain notes.** `Card` is the central work item. Lifecycle state is **compositional**, not a single enum: `status` is `drafted` or `published`, but "closed", "postponed", "golden" are the *presence* of separate side-table rows (`Closure`, `Card::NotNow`, `Card::Goldness`). `Card::ActivitySpike` is a transient burst marker. `Entropy` is configurable auto-postponement. Cards have a per-account sequential `number` (the visible "Card #N" identifier). Tags are account-scoped and joined via `Tagging`. Assignees are users joined via `Assignment` (max 100 per card). The `entropies` table is polymorphic over Account/Board (the `container`).

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `Card` | `app/models/card.rb` | `cards` (schema:218) | `account_id`, `board_id`, `column_id?`, `creator_id`, `number` (bigint, unique per account), `title`, `status` (enum drafted/published, default drafted), `due_on?` (date), `last_active_at` | `belongs_to :account, :board, :creator (User)`, `has_one :closure, :goldness, :not_now, :activity_spike`, `has_many :assignments`, `has_many :assignees, through: :assignments`, `has_many :taggings`, `has_many :tags, through: :taggings`, `has_many :comments, :steps, :reactions, :watches`, `has_many :mentions, as: :source`, `has_one_attached :image`, `has_rich_text :description` | Compositional lifecycle: drafted/published × {closure?, not_now?, golden?, activity_spike?}; `before_create` assigns sequential `number` per account; concerns `Accessible, Assignable, Closeable, Golden, Postponable, Taggable, Watchable, Readable, Triageable, Searchable, Eventable, Mentions, Multistep, Pinnable, Promptable, Stallable, Colored` | `app/views/cards/_card.json.jbuilder` | Core work item |
| `Closure` | `app/models/closure.rb` | `closures` (schema:243) | `account_id`, `card_id` (unique), `user_id?` | `belongs_to :account, :card (touch), :user, optional: true` | One-per-card; presence = card is closed | none | "Closed" marker |
| `Card::NotNow` | `app/models/card/not_now.rb` | `card_not_nows` (schema:207) | `account_id`, `card_id` (unique), `user_id?` | `belongs_to :account, :card (touch), :user, optional: true` | One-per-card; presence = card is postponed | none | "Postponed" marker |
| `Card::Goldness` | `app/models/card/goldness.rb` | `card_goldnesses` (schema:198) | `account_id`, `card_id` (unique) | `belongs_to :account, :card (touch)` | One-per-card; presence = card is "golden" (priority) | none | High-priority marker |
| `Card::ActivitySpike` | `app/models/card/activity_spike.rb` | `card_activity_spikes` (schema:189) | `account_id`, `card_id` (unique) | `belongs_to :account, :card (touch)` | Transient: detector creates, auto-clears after burst | none | Activity badge |
| `Entropy` | `app/models/entropy.rb` | `entropies` (schema:285) | `account_id`, `container_id`, `container_type` (polymorphic Board/Account), `auto_postpone_period` (bigint, seconds; default 2592000 = 30d) | `belongs_to :account, :container (polymorphic)` | Unique per (container_type, container_id); board entropy overrides account entropy | none | Auto-postpone config |
| `Tag` | `app/models/tag.rb` | `tags` | `account_id`, `title` (unique per account, lowercase) | `belongs_to :account`, `has_many :taggings, :cards through :taggings` | Title normalized to lowercase, no leading `#`; `unused` scope | `app/views/tags/_tag.json.jbuilder` | Card label |
| `Tagging` | `app/models/tagging.rb` | `taggings` | `account_id`, `card_id`, `tag_id` | `belongs_to :account, :card (touch), :tag` | Unique per (card_id, tag_id) | none | Card↔Tag join |
| `Assignment` | `app/models/assignment.rb` | `assignments` (schema:148) | `account_id`, `card_id`, `assignee_id` (User), `assigner_id` (User) | `belongs_to :account, :card (touch), :assignee (User), :assigner (User)` | Unique per (assignee_id, card_id); validation caps at 100 per card | none | Card↔Assignee join (with audit) |

### A.5 Comments & rich content

**Domain notes.** `Comment` carries a `has_rich_text :body` (Action Text). `Reaction` is polymorphic over Comment **and** Card (emoji string, max 16 chars). `Mention` links a `mentioner` user to a `mentionee` user inside a polymorphic `source` (Comment or Card). `Step` is a checklist item. Action Text rich text is in its own table (`action_text_rich_texts`) with an `account_id` for multi-tenant scoping.

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `Comment` | `app/models/comment.rb` | `comments` (schema:268) | `account_id`, `card_id`, `creator_id` | `belongs_to :account, :card (touch), :creator (User)`, `has_many :reactions, as: :reactable`, `has_rich_text :body`; concerns `Searchable, Mentions, Eventable, Promptable` | After create: creator auto-watches the card | `app/views/cards/comments/_comment.json.jbuilder` | Threaded rich-text discussion |
| `Reaction` | `app/models/reaction.rb` | `reactions` | `account_id`, `reactable_id`, `reactable_type` (Comment/Card), `reacter_id` (User), `content` (string, max 16) | `belongs_to :account, :reactable (polymorphic, touch), :reacter (User)` | After create: touches reactable.card.last_active_at | none | Emoji reaction |
| `Step` | `app/models/step.rb` | `steps` | `account_id`, `card_id`, `content` (text), `completed` (bool, default false) | `belongs_to :account, :card (touch)` | `:completed` scope filters true | `app/views/cards/steps/_step.json.jbuilder` | Card checklist item |
| `Mention` | `app/models/mention.rb` | `mentions` | `account_id`, `source_id`, `source_type` (Comment/Card), `mentioner_id`, `mentionee_id` | `belongs_to :account, :source (polymorphic), :mentioner (User), :mentionee (User)`; concern `Notifiable` | After create: mentionee auto-watches source | none | User-tag inside text |
| `ActionText::RichText` | `actiontext` gem | `action_text_rich_texts` (schema:88) | `account_id`, `record_id`, `record_type`, `name` (e.g. "body"/"description"/"public_description"), `body` (longtext HTML) | Polymorphic to Card/Comment/Board | Multi-tenant via custom `account_id` column | none | HTML rich text storage |

### A.6 Events, notifications, webhooks

**Domain notes.** `Event` is the immutable audit log: every meaningful action in the domain emits one. `action` is a string ("card_created", "card_closed", "card_assigned", "comment_created", "mention_created", etc.); `particulars` is a JSON column with action-specific metadata. Events drive notifications **and** webhook deliveries. `Notification` aggregates events relevant to a specific user on a specific card (deduplicated and tracked unread). `Notification::Bundle` groups notifications into 24-hour batches for email digests. `Webhook` is the outbound HTTP callback (HMAC-signed); `Webhook::Delivery` is each attempted send (with stored request/response).

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `Event` | `app/models/event.rb` | `events` (schema:297) | `account_id`, `board_id`, `creator_id`, `action` (string), `eventable_id`, `eventable_type` (polymorphic), `particulars` (json default `{}`) | `belongs_to :account, :board, :creator (User), :eventable (polymorphic)`, `has_many :webhook_deliveries`; concern `Notifiable, Particulars` | Immutable; after_create calls `eventable.event_was_created`; after_create_commit dispatches webhooks | (delivered via `app/views/webhooks/event.json.jbuilder`) | Domain audit log |
| `Notification` | `app/models/notification.rb` | `notifications` | `account_id`, `card_id`, `user_id`, `creator_id?`, `source_id`, `source_type` (Event/Mention), `read_at?`, `unread_count` (int default 0) | `belongs_to :account, :card, :user, :creator (User), :source (polymorphic)` | Unique per (user_id, card_id); `read_at` nullable = unread | `app/views/notifications/_notification.json.jbuilder` | User inbox aggregate |
| `Notification::Bundle` | `app/models/notification_bundle.rb` | `notification_bundles` | `account_id`, `user_id`, `starts_at`, `ends_at`, `status` (enum int default 0) | `belongs_to :account, :user` | Time-bounded batch; status state machine pending → sent | none | Email digest container |
| `Webhook` | `app/models/webhook.rb` | `webhooks` | `account_id`, `board_id`, `url`, `name`, `signing_secret` (secure token), `subscribed_actions` (text JSON array), `active` (bool default true) | `belongs_to :account, :board`, `has_many :deliveries dependent: :delete_all`, `has_one :delinquency_tracker` | Active flag gates delivery; URL pattern detects Slack/Basecamp/Campfire for special-format payloads | `app/views/webhooks/_webhook.json.jbuilder` | HTTP callback subscription |
| `Webhook::Delivery` | `app/models/webhook/delivery.rb` | `webhook_deliveries` | `account_id`, `webhook_id`, `event_id`, `state` (enum pending/in_progress/completed/errored, default pending), `request` (text JSON), `response` (text JSON) | `belongs_to :account, :webhook, :event` | State machine; after_create_commit triggers async delivery | `app/views/webhooks/deliveries/_delivery.json.jbuilder` | Outbound delivery attempt |
| `Webhook::DelinquencyTracker` | `app/models/webhook/delinquency_tracker.rb` | `webhook_delinquency_trackers` | `webhook_id`, consecutive-failure counts | `belongs_to :webhook` | Threshold disables webhook | none | Auto-disable on chronic failure |

### A.7 Search

**Domain notes.** Search is **sharded MySQL FULLTEXT** across 16 tables (`search_records_0` through `search_records_15`). Shard key = `Zlib.crc32(account_id.to_s) % 16`. Each row indexes one Card or Comment with a denormalized `title` + `content` blob. Search is account-scoped via an `account_key` column. `SearchQuery` is a per-user history of recent searches.

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `Search::Record` (sharded) | `app/models/search/record.rb`, `app/models/search/record/trilogy.rb`, `app/models/search/record/sqlite.rb` | `search_records_0` … `search_records_15` (16 shards) | `account_id`, `account_key` (string), `board_id`, `card_id`, `searchable_id`, `searchable_type` (Card/Comment), `title`, `content` (text) | none (no AR association — sharded by hand) | Shard via `Zlib.crc32(account_id.to_s) % 16`; FULLTEXT index `(account_key, content, title)` | none | Sharded FTS index |
| `SearchQuery` | (implicit) | `search_queries` | `account_id`, `user_id`, `terms` (string max 2000) | implicit `belongs_to :account, :user` | Unique per (user_id, terms) | none | Search history |

### A.8 Filters & saved views

**Domain notes.** A `Filter` is a saved query composed of many dimensions: assignees, assigners, closers, creators, boards, tags, columns, status, date windows. Stored via 6 explicit join tables. `params_digest` memoizes the hash of filter params for caching.

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `Filter` | `app/models/filter.rb` | `filters` | `account_id`, `creator_id`, `fields` (json default `{}`), `params_digest` (string) | `belongs_to :account, :creator (User)`; many-to-many through `assignees_filters, assigners_filters, closers_filters, creators_filters, boards_filters, filters_tags`; `has_many :columns` | `params_digest` unique per (creator, digest); concerns `Fields, Params, Resources, Summarized`; `#cards` composes the actual query | none | Saved card query |
| join tables (×6) | — | `assignees_filters, assigners_filters, closers_filters, creators_filters, boards_filters, filters_tags` | composite (filter_id, foreign_id) | — | Many-to-many helpers | none | Filter dimensions |

### A.9 Storage / attachments

**Domain notes.** `ActiveStorage::Attachment/Blob/VariantRecord` are the standard Rails storage tables — but Fizzy adds `account_id` for tenant isolation. `StorageEntry` is an audit log of every storage mutation; `StorageTotal` is the aggregated quota usage per Account or Board.

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `ActiveStorage::Attachment` | gem | `active_storage_attachments` (schema:100) | `account_id`, `blob_id`, `record_id`, `record_type`, `name` (e.g. "image", "avatar", "file") | `belongs_to :account, :blob, :record (polymorphic)` | Unique per (record_type, record_id, name, blob_id) | none | File-attachment join |
| `ActiveStorage::Blob` | gem | `active_storage_blobs` (schema:112) | `account_id`, `key` (unique), `filename`, `content_type`, `byte_size`, `checksum`, `metadata` (text), `service_name` | `belongs_to :account` | Immutable; service_name selects backend (S3/local) | none | File metadata + S3 key |
| `ActiveStorage::VariantRecord` | gem | `active_storage_variant_records` (schema:126) | `account_id`, `blob_id`, `variation_digest` (unique per blob) | `belongs_to :account, :blob` | Cached variant (thumbnail) | none | Image variant cache |
| `StorageEntry` | (custom) | `storage_entries` | `account_id`, `blob_id?`, `board_id?`, `recordable_id?`, `recordable_type`, `user_id?`, `operation` (string create/delete), `delta` (bigint bytes), `request_id` (string) | none (audit) | Immutable; `delta` positive=add, negative=delete | none | Storage mutation audit |
| `StorageTotal` | (custom) | `storage_totals` | `owner_id`, `owner_type` (Account/Board), `bytes_stored`, `last_entry_id` | `belongs_to :owner (polymorphic)` | Unique per (owner_type, owner_id); updated via StorageEntry callbacks | none | Quota aggregate |

### A.10 Imports / exports infrastructure

**Domain notes.** Account export/import is full-account ZIP serialization via `Account::DataTransfer::Manifest` — an ordered list of "record sets" each describing how one model serializes. Files larger than memory are streamed (`app/models/zip_file.rb` uses S3 multipart upload with 100 MB parts).

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `Export` (base) | `app/models/export.rb` | `exports` | `account_id`, `user_id`, `type` (STI), `status` (enum pending/processing/completed/failed), `completed_at?` | `belongs_to :account, :user`, `has_one_attached :file` | Status state machine; `:current` scope last 24h; `:expired` >24h | none | Export job record |
| `Account::DataTransfer::Manifest` | `app/models/account/data_transfer/manifest.rb` | none (PORO with class methods) | record-set ordering | none | Defines export/import order: Account, User, Tag, Board, Column, Entropy, Board::Publication, Webhook, Access, Card, Comment, Step, Assignment, Tagging, Closure, Card::Goldness, Card::NotNow, Card::ActivitySpike, Watch, Pin, Reaction, Mention, Filter, Webhook::DelinquencyTracker, Event, Notification, Notification::Bundle, Webhook::Delivery, ActiveStorage::Blob/VariantRecord/Attachment, ActionText::RichText | none | Export/import sequencing |
| `Account::DataTransfer::RecordSet` (×N) | `app/models/account/data_transfer/*_record_set.rb` | per-model | per-model | per-model | Each subclass implements `.export` (write to ZIP) and `.import` (read from ZIP, conflict-check, `insert_all!`) | none | Per-model serializer |
| `ZipFile` | `app/models/zip_file.rb` | none | none | none | S3: multipart upload with 100 MB parts; disk: tempfile | none | Streaming ZIP wrapper |

### A.11 Misc — pins, watches, push, settings

**Domain notes.** `Pin` is a per-user "favorite" marker on a card. `Watch` is a per-user notification subscription on a card (with a boolean toggle). `PushSubscription` holds Web Push API credentials per-device.

| Entity | Model file | Schema table | Key fields | Associations | State semantics | JSON shape | Purpose |
|---|---|---|---|---|---|---|---|
| `Pin` | `app/models/pin.rb` | `pins` | `account_id`, `card_id`, `user_id` | `belongs_to :account, :card, :user` | Unique per (card_id, user_id) | none | Per-user favorite |
| `Watch` | `app/models/watch.rb` | `watches` | `account_id`, `card_id`, `user_id`, `watching` (bool default true) | `belongs_to :account, :card (touch), :user` | Unique per (card_id, user_id); toggleable without delete | none | Notification subscription |
| `PushSubscription` | (implicit) | `push_subscriptions` | `account_id`, `user_id`, `endpoint` (text), `auth_key`, `p256dh_key`, `user_agent` (max 4096) | `belongs_to :account, :user` | Unique per (user_id, endpoint) | none | Browser push credentials |
| `User::Settings` | `app/models/user/settings.rb` | `user_settings` (if present) | per-user prefs | `belongs_to :user` | per-feature booleans/integers | none | User preferences |

### A.12 Background jobs (schema-relevant)

**Domain notes.** Solid Queue is the job backend (database-backed, no Redis). `FizzyActiveJobExtensions` is prepended to ActiveJob to capture/restore `Current.account` across enqueue/perform. Recurring jobs in `config/recurring.yml` include: deliver bundled notifications (every 30m), auto-postpone all due (hourly), cleanup webhook deliveries (every 15m), cleanup magic links (every 4h), cleanup exports/imports (hourly), incineration (every 8h), `clear_solid_queue_finished_jobs` (hourly :12).

(Solid Queue tables — `solid_queue_jobs`, `solid_queue_ready_executions`, `solid_queue_scheduled_executions`, `solid_queue_recurring_executions`, etc. — are infrastructure, not domain entities; not enumerated here. They survive the fork unchanged.)

### A.13 HTTP API surface (verified)

`config/routes.rb` does **not** define a `/api` namespace and there is no OpenAPI spec. JSON delivery is via existing controllers + Jbuilder partials, gated by `Authentication#bearer_token_authenticatable_request?` (which returns true only for `request.format.json?`) and `RequestForgeryProtection#allowed_api_request?` (true when `Sec-Fetch-Site` is absent and format is JSON). Concrete JSON-aware endpoints (non-exhaustive):

- `[POST]   /boards` → `format.json { render :show }`
- `[DELETE] /boards/:id` → `format.json { head :no_content }`
- `[POST]   /boards/:board_id/cards/:id/publish` → `format.json`
- `[POST]   /boards/:board_id/cards/:id/board` (move card) → `format.json { head :no_content }`
- `[POST]   /boards/:board_id/cards/:id/triage` → `format.json { head :no_content }`
- `[POST]   /boards/:board_id/cards/:id/closure` (close/reopen) → `format.json`
- `[POST]   /cards/:id/comments/:id/reactions` → `format.json { render "reactions/show" }`
- `[POST]   /boards/:board_id/webhooks/:id/deliveries` (list deliveries) → `format.json`

Jbuilder partials enumerated above (`A.x` columns "JSON shape") define the wire shapes.

### A.14 Counts (cross-check)

- AR model files in `app/models/`: ~174 (includes concerns, mixins, STI subclasses)
- Primary table-backed entities: ~50 model classes
- Polymorphic tables: `events.eventable`, `mentions.source`, `reactions.reactable`, `notifications.source`, `entropies.container`, `active_storage_attachments.record`, `storage_totals.owner`
- Explicit join tables: 7 (`assignees_filters`, `assigners_filters`, `closers_filters`, `creators_filters`, `boards_filters`, `filters_tags`, `taggings`)
- Sharded tables: `search_records_0` … `search_records_15` (16 shards, one logical FTS index)
- JSON columns: `events.particulars`, `filters.fields`, `webhooks.subscribed_actions`, `active_storage_blobs.metadata`
- Rich-text fields (Action Text): `Card.description`, `Comment.body`, `Board.public_description`
- Attached files: `Card.image`, `Identity.avatar`, `Account::Import.file`, `Export.file`

---

## §B — Beads schema (verified from Dolt)

> **Status**: in progress — Codex to populate from Dolt (`.beads/dolt/fizzy/`).

### Canonical DB location (verified)

Beads task data lives in Dolt at:

- `.beads/dolt/fizzy` (Dolt repo; DB name `fizzy`)

### Tables (verbatim)

Command + output:

```text
$ cd .beads/dolt/fizzy
$ dolt sql -q "show full tables"
+----------------------+------------+
| Tables_in_fizzy      | Table_type |
+----------------------+------------+
| blocked_issues       | VIEW       |
| child_counters       | BASE TABLE |
| comments             | BASE TABLE |
| compaction_snapshots | BASE TABLE |
| config               | BASE TABLE |
| custom_statuses      | BASE TABLE |
| custom_types         | BASE TABLE |
| dependencies         | BASE TABLE |
| events               | BASE TABLE |
| federation_peers     | BASE TABLE |
| interactions         | BASE TABLE |
| issue_counter        | BASE TABLE |
| issue_snapshots      | BASE TABLE |
| issues               | BASE TABLE |
| labels               | BASE TABLE |
| local_metadata       | BASE TABLE |
| metadata             | BASE TABLE |
| ready_issues         | VIEW       |
| repo_mtimes          | BASE TABLE |
| routes               | BASE TABLE |
| schema_migrations    | BASE TABLE |
| wisp_comments        | BASE TABLE |
| wisp_dependencies    | BASE TABLE |
| wisp_events          | BASE TABLE |
| wisp_labels          | BASE TABLE |
| wisps                | BASE TABLE |
+----------------------+------------+
```

### Table purposes (one-line; inferred from schema names/columns)

These are “best effort” inferences. The DDL immediately below is the source of truth.

- `blocked_issues` (VIEW): issues currently blocked (adds `blocked_by_count`) based on `dependencies` + `issues` status.
- `child_counters`: tracks per-parent child numbering (`last_child`) for parent/child relationships.
- `comments`: issue comments (author + text) attached to an `issues.id`.
- `compaction_snapshots`: stores compacted issue JSON blobs per compaction level (audit/restore).
- `config`: key/value config for beads runtime.
- `custom_statuses`: defines custom statuses with a `category` (used by views like `blocked_issues` / `ready_issues`).
- `custom_types`: defines custom `issue_type` values.
- `dependencies`: dependency edges between issues (10 dependency types live in the `type` column).
- `events`: event log for issue changes (field/value changes + comments).
- `federation_peers`: federation peer definitions (cross-repo / cross-project peer config).
- `interactions`: stores tool/LLM interaction logs (prompt/response/errors + issue linkage).
- `issue_counter`: per-prefix monotonically increasing issue id counter (id generation).
- `issue_snapshots`: stores compaction snapshots including `original_content` + archived events.
- `issues`: primary issue/task table (title/description/design/AC/notes/status/type/priority/etc).
- `labels`: join table mapping issue → label strings.
- `local_metadata`: key/value metadata scoped locally (machine/workspace; distinct from `metadata`).
- `metadata`: global key/value metadata (workspace-level).
- `ready_issues` (VIEW): issues “ready to work” (not blocked + not deferred + active/open statuses).
- `repo_mtimes`: caches repo JSONL mtimes (incremental import/export bookkeeping).
- `routes`: prefix → path mapping (routing/integration table; used by beads CLI).
- `schema_migrations`: schema versioning for beads (Dolt SQL migrations).
- `wisp_comments`: comments on `wisps` (wisp analog of `comments`).
- `wisp_dependencies`: dependencies on `wisps` (wisp analog of `dependencies`).
- `wisp_events`: events on `wisps` (wisp analog of `events`).
- `wisp_labels`: labels on `wisps` (wisp analog of `labels`).
- `wisps`: “wisp” issues (infrastructure/agent/molecule/gate/etc; parallel schema to `issues`).

### Schema definitions (verbatim)

Each block below is verbatim output from either:
- `dolt schema show <table>` (BASE TABLE), or
- `dolt sql -q "show create view <view>"` (VIEW).

### `blocked_issues`

```sql
+----------------+---------------------------------------------------------------------------+----------------------+----------------------+
| View           | Create View                                                               | character_set_client | collation_connection |
+----------------+---------------------------------------------------------------------------+----------------------+----------------------+
| blocked_issues | CREATE VIEW `blocked_issues` AS WITH done_frozen AS (                     | utf8mb4              | utf8mb4_0900_bin     |
|                |     SELECT name FROM custom_statuses WHERE category IN ('done', 'frozen') |                      |                      |
|                | )                                                                         |                      |                      |
|                | SELECT                                                                    |                      |                      |
|                |     i.*,                                                                  |                      |                      |
|                |     (SELECT COUNT(*)                                                      |                      |                      |
|                |      FROM dependencies d                                                  |                      |                      |
|                |      WHERE d.issue_id = i.id                                              |                      |                      |
|                |        AND d.type = 'blocks'                                              |                      |                      |
|                |        AND EXISTS (                                                       |                      |                      |
|                |          SELECT 1 FROM issues blocker                                     |                      |                      |
|                |          WHERE blocker.id = d.depends_on_id                               |                      |                      |
|                |            AND blocker.status NOT IN ('closed', 'pinned')                 |                      |                      |
|                |            AND blocker.status NOT IN (SELECT name FROM done_frozen)       |                      |                      |
|                |        )                                                                  |                      |                      |
|                |     ) as blocked_by_count                                                 |                      |                      |
|                | FROM issues i                                                             |                      |                      |
|                | WHERE i.status NOT IN ('closed', 'pinned')                                |                      |                      |
|                |   AND i.status NOT IN (SELECT name FROM done_frozen)                      |                      |                      |
|                |   AND EXISTS (                                                            |                      |                      |
|                |     SELECT 1 FROM dependencies d                                          |                      |                      |
|                |     WHERE d.issue_id = i.id                                               |                      |                      |
|                |       AND d.type = 'blocks'                                               |                      |                      |
|                |       AND EXISTS (                                                        |                      |                      |
|                |         SELECT 1 FROM issues blocker                                      |                      |                      |
|                |         WHERE blocker.id = d.depends_on_id                                |                      |                      |
|                |           AND blocker.status NOT IN ('closed', 'pinned')                  |                      |                      |
|                |           AND blocker.status NOT IN (SELECT name FROM done_frozen)        |                      |                      |
|                |       )                                                                   |                      |                      |
|                |   )                                                                       |                      |                      |
+----------------+---------------------------------------------------------------------------+----------------------+----------------------+
```

### `child_counters`

```sql
child_counters @ working
CREATE TABLE `child_counters` (
  `parent_id` varchar(255) NOT NULL,
  `last_child` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `comments`

```sql
comments @ working
CREATE TABLE `comments` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `author` varchar(255) NOT NULL,
  `text` text NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_comments_created_at` (`created_at`),
  KEY `idx_comments_issue` (`issue_id`),
  CONSTRAINT `fk_comments_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `compaction_snapshots`

```sql
compaction_snapshots @ working
CREATE TABLE `compaction_snapshots` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `compaction_level` int NOT NULL,
  `snapshot_json` blob NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_comp_snap_issue` (`issue_id`,`compaction_level`,`created_at`),
  CONSTRAINT `fk_comp_snap_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `config`

```sql
config @ working
CREATE TABLE `config` (
  `key` varchar(255) NOT NULL,
  `value` text NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `custom_statuses`

```sql
custom_statuses @ working
CREATE TABLE `custom_statuses` (
  `name` varchar(64) NOT NULL,
  `category` varchar(32) NOT NULL DEFAULT 'unspecified',
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `custom_types`

```sql
custom_types @ working
CREATE TABLE `custom_types` (
  `name` varchar(64) NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `dependencies`

```sql
dependencies @ working
CREATE TABLE `dependencies` (
  `issue_id` varchar(255) NOT NULL,
  `depends_on_id` varchar(255) NOT NULL,
  `type` varchar(32) NOT NULL DEFAULT 'blocks',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(255) NOT NULL,
  `metadata` json DEFAULT (json_object()),
  `thread_id` varchar(255) DEFAULT '',
  PRIMARY KEY (`issue_id`,`depends_on_id`),
  KEY `idx_dependencies_depends_on` (`depends_on_id`),
  KEY `idx_dependencies_depends_on_type` (`depends_on_id`,`type`),
  KEY `idx_dependencies_issue` (`issue_id`),
  KEY `idx_dependencies_thread` (`thread_id`),
  CONSTRAINT `fk_dep_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `events`

```sql
events @ working
CREATE TABLE `events` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `event_type` varchar(32) NOT NULL,
  `actor` varchar(255) NOT NULL,
  `old_value` text,
  `new_value` text,
  `comment` text,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_events_created_at` (`created_at`),
  KEY `idx_events_issue` (`issue_id`),
  CONSTRAINT `fk_events_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `federation_peers`

```sql
federation_peers @ working
CREATE TABLE `federation_peers` (
  `name` varchar(255) NOT NULL,
  `repo` varchar(512) NOT NULL,
  `branch` varchar(255) NOT NULL DEFAULT 'main',
  `remote` varchar(255) NOT NULL DEFAULT 'origin',
  `enabled` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`name`),
  KEY `idx_fed_enabled` (`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `interactions`

```sql
interactions @ working
CREATE TABLE `interactions` (
  `id` varchar(32) NOT NULL,
  `kind` varchar(64) NOT NULL,
  `created_at` datetime NOT NULL,
  `actor` varchar(255),
  `issue_id` varchar(255),
  `model` varchar(255),
  `prompt` text,
  `response` text,
  `error` text,
  `tool_name` varchar(255),
  `exit_code` int,
  `parent_id` varchar(32),
  `label` varchar(64),
  `reason` text,
  `extra` json,
  PRIMARY KEY (`id`),
  KEY `idx_interactions_created_at` (`created_at`),
  KEY `idx_interactions_issue_id` (`issue_id`),
  KEY `idx_interactions_kind` (`kind`),
  KEY `idx_interactions_parent_id` (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `issue_counter`

```sql
issue_counter @ working
CREATE TABLE `issue_counter` (
  `prefix` varchar(255) NOT NULL,
  `last_id` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`prefix`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `issue_snapshots`

```sql
issue_snapshots @ working
CREATE TABLE `issue_snapshots` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `snapshot_time` datetime NOT NULL,
  `compaction_level` int NOT NULL,
  `original_size` int NOT NULL,
  `compressed_size` int NOT NULL,
  `original_content` text NOT NULL,
  `archived_events` text,
  PRIMARY KEY (`id`),
  KEY `idx_snapshots_issue` (`issue_id`),
  KEY `idx_snapshots_level` (`compaction_level`),
  CONSTRAINT `fk_snapshots_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `issues`

```sql
issues @ working
CREATE TABLE `issues` (
  `id` varchar(255) NOT NULL,
  `content_hash` varchar(64),
  `title` varchar(500) NOT NULL,
  `description` text NOT NULL,
  `design` text NOT NULL,
  `acceptance_criteria` text NOT NULL,
  `notes` text NOT NULL,
  `status` varchar(32) NOT NULL DEFAULT 'open',
  `priority` int NOT NULL DEFAULT '2',
  `issue_type` varchar(32) NOT NULL DEFAULT 'task',
  `assignee` varchar(255),
  `estimated_minutes` int,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(255) DEFAULT '',
  `owner` varchar(255) DEFAULT '',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `closed_at` datetime,
  `closed_by_session` varchar(255) DEFAULT '',
  `external_ref` varchar(255),
  `spec_id` varchar(1024),
  `compaction_level` int DEFAULT '0',
  `compacted_at` datetime,
  `compacted_at_commit` varchar(64),
  `original_size` int,
  `sender` varchar(255) DEFAULT '',
  `ephemeral` tinyint(1) DEFAULT '0',
  `no_history` tinyint(1) DEFAULT '0',
  `wisp_type` varchar(32) DEFAULT '',
  `pinned` tinyint(1) DEFAULT '0',
  `is_template` tinyint(1) DEFAULT '0',
  `mol_type` varchar(32) DEFAULT '',
  `work_type` varchar(32) DEFAULT 'mutex',
  `source_system` varchar(255) DEFAULT '',
  `metadata` json DEFAULT (json_object()),
  `source_repo` varchar(512) DEFAULT '',
  `close_reason` text DEFAULT '',
  `event_kind` varchar(32) DEFAULT '',
  `actor` varchar(255) DEFAULT '',
  `target` varchar(255) DEFAULT '',
  `payload` text DEFAULT '',
  `await_type` varchar(32) DEFAULT '',
  `await_id` varchar(255) DEFAULT '',
  `timeout_ns` bigint DEFAULT '0',
  `waiters` text DEFAULT '',
  `due_at` datetime,
  `defer_until` datetime,
  `started_at` datetime,
  PRIMARY KEY (`id`),
  KEY `idx_issues_assignee` (`assignee`),
  KEY `idx_issues_created_at` (`created_at`),
  KEY `idx_issues_external_ref` (`external_ref`),
  KEY `idx_issues_issue_type` (`issue_type`),
  KEY `idx_issues_priority` (`priority`),
  KEY `idx_issues_spec_id` (`spec_id`),
  KEY `idx_issues_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `labels`

```sql
labels @ working
CREATE TABLE `labels` (
  `issue_id` varchar(255) NOT NULL,
  `label` varchar(255) NOT NULL,
  PRIMARY KEY (`issue_id`,`label`),
  KEY `idx_labels_label` (`label`),
  CONSTRAINT `fk_labels_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `local_metadata`

```sql
local_metadata @ working
CREATE TABLE `local_metadata` (
  `key` varchar(255) NOT NULL,
  `value` text NOT NULL DEFAULT '',
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `metadata`

```sql
metadata @ working
CREATE TABLE `metadata` (
  `key` varchar(255) NOT NULL,
  `value` text NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `ready_issues`

```sql
+--------------+---------------------------------------------------------------------------------+----------------------+----------------------+
| View         | Create View                                                                     | character_set_client | collation_connection |
+--------------+---------------------------------------------------------------------------------+----------------------+----------------------+
| ready_issues | CREATE VIEW `ready_issues` AS WITH RECURSIVE                                    | utf8mb4              | utf8mb4_0900_bin     |
|              |   blocked_directly AS (                                                         |                      |                      |
|              |     SELECT DISTINCT d.issue_id                                                  |                      |                      |
|              |     FROM dependencies d                                                         |                      |                      |
|              |     WHERE d.type = 'blocks'                                                     |                      |                      |
|              |       AND EXISTS (                                                              |                      |                      |
|              |         SELECT 1 FROM issues blocker                                            |                      |                      |
|              |         WHERE blocker.id = d.depends_on_id                                      |                      |                      |
|              |           AND blocker.status NOT IN ('closed', 'pinned')                        |                      |                      |
|              |       )                                                                         |                      |                      |
|              |   ),                                                                            |                      |                      |
|              |   blocked_transitively AS (                                                     |                      |                      |
|              |     SELECT issue_id, 0 as depth                                                 |                      |                      |
|              |     FROM blocked_directly                                                       |                      |                      |
|              |     UNION ALL                                                                   |                      |                      |
|              |     SELECT d.issue_id, bt.depth + 1                                             |                      |                      |
|              |     FROM blocked_transitively bt                                                |                      |                      |
|              |     JOIN dependencies d ON d.depends_on_id = bt.issue_id                        |                      |                      |
|              |     WHERE d.type = 'parent-child'                                               |                      |                      |
|              |       AND bt.depth < 50                                                         |                      |                      |
|              |   )                                                                             |                      |                      |
|              | SELECT i.*                                                                      |                      |                      |
|              | FROM issues i                                                                   |                      |                      |
|              | LEFT JOIN blocked_transitively bt ON bt.issue_id = i.id                         |                      |                      |
|              | WHERE (                                                                         |                      |                      |
|              |     i.status = 'open'                                                           |                      |                      |
|              |     OR i.status IN (SELECT name FROM custom_statuses WHERE category = 'active') |                      |                      |
|              |   )                                                                             |                      |                      |
|              |   AND (i.ephemeral = 0 OR i.ephemeral IS NULL)                                  |                      |                      |
|              |   AND bt.issue_id IS NULL                                                       |                      |                      |
|              |   AND (i.defer_until IS NULL OR i.defer_until <= UTC_TIMESTAMP())               |                      |                      |
|              |   AND NOT EXISTS (                                                              |                      |                      |
|              |     SELECT 1 FROM dependencies d_parent                                         |                      |                      |
|              |     JOIN issues parent ON parent.id = d_parent.depends_on_id                    |                      |                      |
|              |     WHERE d_parent.issue_id = i.id                                              |                      |                      |
|              |       AND d_parent.type = 'parent-child'                                        |                      |                      |
|              |       AND parent.defer_until IS NOT NULL                                        |                      |                      |
|              |       AND parent.defer_until > UTC_TIMESTAMP()                                  |                      |                      |
|              |   )                                                                             |                      |                      |
+--------------+---------------------------------------------------------------------------------+----------------------+----------------------+
```

### `repo_mtimes`

```sql
repo_mtimes @ working
CREATE TABLE `repo_mtimes` (
  `repo_path` varchar(512) NOT NULL,
  `jsonl_path` varchar(512) NOT NULL,
  `mtime_ns` bigint NOT NULL,
  `last_checked` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`repo_path`),
  KEY `idx_repo_mtimes_checked` (`last_checked`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `routes`

```sql
routes @ working
CREATE TABLE `routes` (
  `prefix` varchar(32) NOT NULL,
  `path` varchar(512) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`prefix`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `schema_migrations`

```sql
schema_migrations @ working
CREATE TABLE `schema_migrations` (
  `version` varchar(255) NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `wisp_comments`

```sql
wisp_comments @ working
CREATE TABLE `wisp_comments` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `author` varchar(255) NOT NULL DEFAULT '',
  `text` text NOT NULL DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_wisp_comments_created_at` (`created_at`),
  KEY `idx_wisp_comments_issue` (`issue_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `wisp_dependencies`

```sql
wisp_dependencies @ working
CREATE TABLE `wisp_dependencies` (
  `issue_id` varchar(255) NOT NULL,
  `depends_on_id` varchar(255) NOT NULL,
  `type` varchar(32) NOT NULL DEFAULT 'blocks',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(255) NOT NULL DEFAULT '',
  `metadata` json DEFAULT (json_object()),
  PRIMARY KEY (`issue_id`,`depends_on_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `wisp_events`

```sql
wisp_events @ working
CREATE TABLE `wisp_events` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `event_type` varchar(32) NOT NULL,
  `actor` varchar(255) DEFAULT '',
  `old_value` text DEFAULT '',
  `new_value` text DEFAULT '',
  `comment` text DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_wisp_events_created_at` (`created_at`),
  KEY `idx_wisp_events_issue` (`issue_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `wisp_labels`

```sql
wisp_labels @ working
CREATE TABLE `wisp_labels` (
  `issue_id` varchar(255) NOT NULL,
  `label` varchar(255) NOT NULL,
  PRIMARY KEY (`issue_id`,`label`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `wisps`

```sql
wisps @ working
CREATE TABLE `wisps` (
  `id` varchar(255) NOT NULL,
  `content_hash` varchar(64),
  `title` varchar(500) NOT NULL,
  `description` text NOT NULL DEFAULT '',
  `design` text NOT NULL DEFAULT '',
  `acceptance_criteria` text NOT NULL DEFAULT '',
  `notes` text NOT NULL DEFAULT '',
  `status` varchar(32) NOT NULL DEFAULT 'open',
  `priority` int NOT NULL DEFAULT '2',
  `issue_type` varchar(32) NOT NULL DEFAULT 'task',
  `assignee` varchar(255),
  `estimated_minutes` int,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(255) DEFAULT '',
  `owner` varchar(255) DEFAULT '',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `closed_at` datetime,
  `closed_by_session` varchar(255) DEFAULT '',
  `external_ref` varchar(255),
  `spec_id` varchar(1024),
  `compaction_level` int DEFAULT '0',
  `compacted_at` datetime,
  `compacted_at_commit` varchar(64),
  `original_size` int,
  `sender` varchar(255) DEFAULT '',
  `ephemeral` tinyint(1) DEFAULT '0',
  `no_history` tinyint(1) DEFAULT '0',
  `wisp_type` varchar(32) DEFAULT '',
  `pinned` tinyint(1) DEFAULT '0',
  `is_template` tinyint(1) DEFAULT '0',
  `mol_type` varchar(32) DEFAULT '',
  `work_type` varchar(32) DEFAULT 'mutex',
  `source_system` varchar(255) DEFAULT '',
  `metadata` json DEFAULT (json_object()),
  `source_repo` varchar(512) DEFAULT '',
  `close_reason` text DEFAULT '',
  `event_kind` varchar(32) DEFAULT '',
  `actor` varchar(255) DEFAULT '',
  `target` varchar(255) DEFAULT '',
  `payload` text DEFAULT '',
  `await_type` varchar(32) DEFAULT '',
  `await_id` varchar(255) DEFAULT '',
  `timeout_ns` bigint DEFAULT '0',
  `waiters` text DEFAULT '',
  `hook_bead` varchar(255) DEFAULT '',
  `role_bead` varchar(255) DEFAULT '',
  `agent_state` varchar(32) DEFAULT '',
  `last_activity` datetime,
  `role_type` varchar(32) DEFAULT '',
  `rig` varchar(255) DEFAULT '',
  `due_at` datetime,
  `defer_until` datetime,
  `started_at` datetime,
  PRIMARY KEY (`id`),
  KEY `idx_wisps_assignee` (`assignee`),
  KEY `idx_wisps_created_at` (`created_at`),
  KEY `idx_wisps_external_ref` (`external_ref`),
  KEY `idx_wisps_issue_type` (`issue_type`),
  KEY `idx_wisps_priority` (`priority`),
  KEY `idx_wisps_spec_id` (`spec_id`),
  KEY `idx_wisps_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

---

## §C — Mapping table (Fizzy ↔ Beads)

> **Status**: drafted by `fizzy-claude`. Built row-by-row from §A entities + §B Beads schema + §D verdicts. Surprises and unresolved choices surface as Q-S-NNN questions in §E.

**Mapping legend.** Every row tagged with exactly one:

- `[Beads-native]` — direct field-for-field mapping; no adapter logic needed.
- `[Beads-equivalent (adapter)]` — beads concept exists but the shape/cardinality differs; an adapter layer translates.
- `[Hybrid]` — split: beads owns the canonical primitive, Fizzy holds richer/UI-only data joined by `issues.id`.
- `[Fizzy-only]` — no beads equivalent; stays as a Fizzy table FK'd to `issues.id`. Fork keeps it.
- `[Drop in fork]` — feature retires (per CEO Q3 ii or Q4a). Fork removes or stubs it.

### C.1 Tenancy → mostly `[Fizzy-only]` (singleton); only the path-prefix machinery `[Drop in fork]`

Per CEO Q3 (ii), single-tenant installs. **Important distinction**: single-tenant ≠ single-user. The fork still supports a multi-user team within one install (roles, board access, watches, pins, notifications, invites all survive). What retires is the *path-prefix multi-tenancy machinery* and the *external account id sequencing* — not the team layer.

The `Account` collapses to a **singleton row** (auto-created on install), and `account_id` columns across the schema become a constant FK to that singleton (no-op scoping rather than dead schema). A future plumbing round may drop the columns; until then they remain valid FKs.

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `Account` | (none) | `[Fizzy-only]` (singleton) | Auto-created singleton row; anchors users / boards / permissions / config. Not dropped. **Q-S-006**. |
| `Account::JoinCode` | (none) | `[Fizzy-only]` | Team-invite token to join the install. Survives — single-tenant still has a team. |
| `Account::Cancellation` | (none) | `[Fizzy-only]` | Uninstall / wipe flow; may simplify but conceptually survives. **Q-S-006a**. |
| `Account::ExternalIdSequence` | (none) | `[Drop in fork]` | The slug counter for `external_account_id` retires with the path-prefix middleware. |
| `Account::Export` (STI) | (none) | `[Drop in fork]` | Multi-account ZIP export retires; data motion is `bd export` JSONL + Fizzy-side backup. **Q-S-007**. |
| `Account::Import` | (none) | `[Drop in fork]` | Same as export. |
| `AccountSlug::Extractor` middleware | (none) | `[Drop in fork]` | The `/{external_account_id}/...` URL prefix machinery + `Current.with_account` set-up. |
| `external_account_id` column on `accounts` | (none) | `[Drop in fork]` | The user-visible tenant slug is gone. |
| `account_id` column (on every other table) | (none) | `[Fizzy-only]` (constant) | Becomes a constant FK to the singleton account; not dead schema, just no-op scoping. Future plumbing round may drop. |

### C.2 Identity & auth → all `[Fizzy-only]` (multi-user team survives)

Fizzy keeps its auth stack — magic links, sessions, identity, access tokens — because beads has no auth model (its `actor` is just a git identity string per commit). Bearer-token JSON API survives intact (D-7). The `User` model survives as the per-install team-member entity (with role / name / Identity FK); only the per-tenant variation goes away.

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `Identity` (email, passkeys, avatar) | (none) | `[Fizzy-only]` | Global login credential. Stays. |
| `Identity::AccessToken` | (loose) `issues.created_by` / `events.actor` (Beads `actor` string) | `[Hybrid]` | Token authenticates Fizzy → bd; bd-side commits attribute via `BD_ACTOR=<identity-email>`. **Q-S-004**. |
| `Session` | (none) | `[Fizzy-only]` | Cookie session record. |
| `User` (per-install team member) | (none) | `[Fizzy-only]` | Multi-user team in a single-tenant install. Roles (member/owner/system), name, Identity FK all stay. Account membership simplifies (always the singleton account). **Q-S-008**. |
| `MagicLink` | (none) | `[Fizzy-only]` | Sign-in path. |

### C.3 Boards & columns → `[Fizzy-only]` (kanban surface)

Beads has no native "board" or "column" primitive. A "board" in our fork becomes a Fizzy-side saved query or labels-set; a "column" becomes a Fizzy-side ordered grouping over issue `status` or a label. This is **the** big UX-vs-data design call for the spec phase.

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `Board` | (none) | `[Fizzy-only]` | Per-board entity stays, but its `cards` association becomes "issues matching this board's filter". **Q-S-003**, **Q-S-009**. |
| `Column` | (none) | `[Fizzy-only]` | Kanban swimlane stays Fizzy-side; mapping to issue state TBD. **Q-S-010**. |
| `Board::Publication` | (none) | `[Fizzy-only]` | Public-share key stays. |
| `Access` | (none) | `[Fizzy-only]` | Per-board ACL stays Fizzy-side (beads has no ACL primitive). |

### C.4 Cards & lifecycle → `[Beads-equivalent (adapter)]` for `Card`; `[Beads-equivalent]` for state markers

This is the **core of the fork**: a Fizzy `Card` becomes a Beads `issues` row, with the fields below mapping accordingly. State semantics differ (Fizzy uses presence-of-side-table-row; beads uses a single `status` enum), so an adapter handles the translation.

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `Card` (model class + table) | `issues` row | `[Beads-equivalent (adapter)]` | The single most important mapping. Adapter handles every field below. |
| `Card.id` (uuid) | `issues.id` (`fizzy-<suffix>` string) | `[Beads-equivalent (adapter)]` | Shape changes from UUID to prefix-suffix string. Fizzy schema's existing UUID FKs become string FKs. **Q-S-011** — schema migration cost. |
| `Card.number` (per-account sequential) | (none) | `[Drop in fork]` | Beads `id` itself is the visible identifier. Drop the sequential-number concept. |
| `Card.title` | `issues.title` | `[Beads-native]` | 1:1. |
| `Card.description` (rich text via `has_rich_text`) | `issues.description` (plain `text`) + Fizzy ActionText sidecar | `[Hybrid]` | Beads description is plaintext (D-1). Fizzy retains its HTML sidecar in `action_text_rich_texts`, joined via `record_id = issues.id` (after FK type change). Spec must decide rendering source-of-truth. **Q-S-012**. |
| `Card.status` (drafted/published) | `issues.status` (open/in_progress/blocked/deferred/closed + custom) | `[Beads-equivalent (adapter)]` | Adapter maps draft ↔ (special) and published ↔ open. **Q-S-013**. |
| `Card.due_on` | `issues.due_at` | `[Beads-native]` (date vs datetime — adapter coerces) | 1:1 with type coercion. |
| `Card.last_active_at` | `issues.updated_at` | `[Beads-native]` | Map to Dolt-managed timestamp. |
| `Card.creator_id` | `issues.created_by` (Beads `actor` string) | `[Beads-equivalent (adapter)]` | Fizzy uses User UUID; Beads uses identity string. Adapter resolves. |
| `Closure` (presence row) | `issues.status = closed` | `[Beads-equivalent (adapter)]` | "Card closed" = beads issue closed. Adapter maps. The `closed_by` data lives in Beads `events` history. **Q-S-014**. |
| `Card::NotNow` (presence row) | `issues.status = deferred` (with `defer_until`?) | `[Beads-equivalent (adapter)]` | "Card postponed" = beads `deferred`. **Q-S-015**. |
| `Card::Goldness` (presence row) | (none) | `[Fizzy-only]` | Beads has no "starred"/"golden" primitive; a Fizzy table FK'd to `issues.id` retains it. |
| `Card::ActivitySpike` (transient) | (none) | `[Fizzy-only]` | UI badge; computed or stored Fizzy-side. |
| `Entropy` (auto-postpone config) | `issues.defer_until` (per-issue) | `[Hybrid]` | Beads has per-issue `defer_until` but no group/board-level entropy config. Fizzy-side keeps the entropy row; the auto-postpone job sets per-issue `defer_until` via bd. **Q-S-016**. |
| `Tag` | `labels` (Beads table) | `[Beads-equivalent (adapter)]` | Beads labels are strings; Fizzy `Tag` is a model. Adapter syncs. **Q-S-017**. |
| `Tagging` (Card↔Tag join) | (Beads `labels` row per issue) | `[Beads-equivalent (adapter)]` | Fizzy `Tagging` row maps to a Beads label entry on the issue. |
| `Assignment` (Card↔User many-to-many, max 100) | `issues.assignee` (single string) | `[Beads-equivalent (adapter)]` (lossy) | **Major gap**: beads has ONE assignee per issue; Fizzy supports many. Either (a) Fizzy retains a Fizzy-only `assignments` table FK'd to `issues.id` and beads `assignee` mirrors the "primary" assignee, or (b) we serialize multi-assignee into beads `metadata` JSON. **Q-S-018**. |

### C.5 Comments & rich content

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `Comment` | Beads `comments` table | `[Beads-equivalent (adapter)]` | Beads has `comments` table (verified §B). Cardinality 1:1 per comment. Body shape differs (rich text vs plain). **Q-S-019**. |
| `Comment.body` (rich text) | Beads `comments.<text-column>` (plaintext) | `[Hybrid]` | Same pattern as `Card.description`: beads holds plaintext, Fizzy ActionText sidecar holds HTML. **Q-S-019** (same). |
| `Reaction` | (none) | `[Fizzy-only]` | Beads has no reactions. Fizzy table FK'd to `issues.id` (or `comments.id` once we figure out beads comment ids). |
| `Step` (card checklist) | (none) | `[Fizzy-only]` | Beads has no native checklist. Could be inferred from comments or kept Fizzy-only. **Q-S-020**. |
| `Mention` | (none) | `[Fizzy-only]` | Beads has no mention primitive. Fizzy keeps its mention table; render-time lookup. |
| `ActionText::RichText` (sidecar) | (none) | `[Fizzy-only]` | HTML sidecar table FK'd to issue/comment ids. |

### C.6 Events, notifications, webhooks

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `Event` (Fizzy) | Beads `events` table | `[Beads-equivalent (adapter)]` | Beads has its own events log. Two-way: Fizzy domain actions emit Fizzy events AND must keep beads events in sync (or vice versa). **Q-S-021**. |
| `Event.particulars` (json) | Beads `events.<json>` (if any) | `[Beads-equivalent (adapter)]` or `[Hybrid]` | Spec must decide whether to store action-specific JSON on the beads event or keep it Fizzy-side. **Q-S-021**. |
| `Notification` | (none) | `[Fizzy-only]` | UI inbox concern. |
| `Notification::Bundle` | (none) | `[Fizzy-only]` | Email digest concern. |
| `Webhook` | (Beads has `routes` table + integration prefixes) | `[Fizzy-only]` (likely) | Beads has integrations (jira/linear/github sync) but no per-event outbound HTTP webhook. Fizzy keeps its webhooks. **Q-S-022**. |
| `Webhook::Delivery` | (none) | `[Fizzy-only]` | Same as Webhook. |
| `Webhook::DelinquencyTracker` | (none) | `[Fizzy-only]` | Same. |

### C.7 Search

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `Search::Record` (16 shards FTS) | Beads has `bd search` over title/text + maybe metadata (D-4) | `[Hybrid]` (likely) | Spec must decide: (a) Fizzy keeps its 16-shard FTS over beads-mirrored data; (b) Fizzy delegates search to `bd search`; (c) hybrid (Fizzy FTS for cards, bd for native beads queries). **Q-S-023**. |
| `SearchQuery` (per-user history) | (none) | `[Fizzy-only]` | Per-user UI concern. |

### C.8 Filters & saved views → `[Fizzy-only]`

Beads has `bd query` and label filters, but Fizzy `Filter` objects are richer (assignees + assigners + closers + creators + boards + columns + tags + status + dates). Fizzy keeps its Filter model.

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `Filter` + 6 join tables | `bd query` (different shape) | `[Fizzy-only]` (with adapter calls) | Filter execution adapter calls `bd query` with composed expression. **Q-S-024**. |

### C.9 Storage / attachments → all `[Fizzy-only]` (FK to beads issue id)

Beads has no native attachment table (D-2 verdict: REFUTED native; PARTIAL via `metadata`). Fizzy ActiveStorage stays.

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `ActiveStorage::Attachment` | (none) | `[Fizzy-only]` | Polymorphic `record` becomes string (beads `issues.id`) instead of UUID. **Q-S-025**. |
| `ActiveStorage::Blob` | (none) | `[Fizzy-only]` | Unchanged. |
| `ActiveStorage::VariantRecord` | (none) | `[Fizzy-only]` | Unchanged. |
| `StorageEntry` / `StorageTotal` | (none) | `[Fizzy-only]` (or `[Drop in fork]` if quota retires with multi-tenancy) | Account-scoped quotas die with multi-tenancy. **Q-S-026**. |

### C.10 Imports / exports infrastructure → `[Drop in fork]`

Per Q3 (ii), single-tenant installs. Bulk account ZIP import/export retires. For data motion in/out, use `bd export` / `bd import` JSONL (beads-native).

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `Export` (base) | `bd export` JSONL | `[Drop in fork]` | Beads-native export covers task data. Fizzy-side data (rich text, attachments, etc.) needs its own backup; deferred. **Q-S-027**. |
| `Account::DataTransfer::Manifest` + record sets | (none) | `[Drop in fork]` | Replaced by per-table backups if needed. |
| `ZipFile` | (none) | `[Drop in fork]` | Specific to ZIP import flow. |

### C.11 Misc

| Fizzy | Beads target | Mapping | Notes / questions |
|---|---|---|---|
| `Pin` | (none) | `[Fizzy-only]` | Per-user favorite. |
| `Watch` | (none) | `[Fizzy-only]` | Per-user notification subscription. |
| `PushSubscription` | (none) | `[Fizzy-only]` | Web Push credentials. |
| `User::Settings` | (none) | `[Fizzy-only]` | UI preferences. |

### C.12 Background jobs → `[Fizzy-only]` (Solid Queue stays)

Solid Queue tables and recurring jobs (deliver bundled notifications, auto-postpone all due, cleanup webhook deliveries, magic links, exports/imports, incineration, FTS reindex) all stay Fizzy-side. Auto-postpone retargets to set beads `defer_until`; bundled notifications and incineration retire (no multi-tenancy).

### C.13 Beads-native concepts the fork inherits

These are beads primitives Fizzy does **not** currently model but receives "for free" from Beads:

| Beads primitive | Fizzy v1 surface decision | Mapping | Notes / questions |
|---|---|---|---|
| `issues.priority` (0-4) | `[Beads-native]` — surface in UI | New Fizzy UI field | **Q-S-028**: how does Card `Goldness` interact with bead `priority`? |
| `issues.issue_type` (task/bug/feature/epic/chore/decision) | `[Beads-native]` — surface in UI | New Fizzy UI field | **Q-S-029**: how does this interact with Fizzy boards/columns? |
| `issues.estimated_minutes` | `[Beads-native]` — surface in UI | New Fizzy UI field | Trivial. |
| `issues.acceptance_criteria` | `[Beads-native]` — surface in UI | New Fizzy UI field | Major UI add. |
| `issues.design` | `[Beads-native]` — surface in UI | New Fizzy UI field | Major UI add. |
| `issues.notes` | `[Beads-native]` — surface in UI | New Fizzy UI field | Major UI add. |
| `dependencies` (10 types) | `[Beads-native]` — surface in UI | New Fizzy UI surface | **Q-S-030**: which dep types are visible in v1? Recommend all 10 with grouping. |
| `issues.parent_id` (hierarchy) | `[Beads-native]` — surface in UI | New Fizzy UI surface | **Q-S-031**: tree view? collapsing children? |
| `issues.defer_until` | `[Beads-native]` — replaces Card::NotNow | (handled in C.4) | |
| `issues.external_ref` | `[Beads-native]` — surface optionally | New Fizzy UI field (read-only display likely) | |
| `issues.metadata` (JSON) | `[Beads-native]` — extension point | Used by adapters where Fizzy needs to bolt on (e.g., multi-assignee) | **Q-S-032**: what gets a metadata-key vs a Fizzy sidecar table? |
| `wisps`, `wisp_*` (gates/molecules/swarms infrastructure) | `[Drop in fork]` for v1 (per Q4a) | Acknowledged in §B; no UI surface in v1 | Defer to v2+. |
| `federation_peers` | `[Drop in fork]` for v1 (per Q4a) | No federation. | Defer to v2+. |
| `events` (Beads native) | (handled in C.6) | Two-way sync with Fizzy events. | |
| `interactions` (LLM tool log) | `[Beads-native]` — passively populated | No UI surface in v1; useful for debugging. | |
| `routes` (integration prefixes) | `[Beads-native]` — leave alone | Beads-internal, no Fizzy surface. | |

---

## §D — Verified assumptions (CEO-flagged + emergent)

> **Status**: in progress — Beads-side verification populated (items 1–7, 10). Fizzy-side items (8–9) to be populated by Claude with `path:line` evidence.

### Evidence (verbatim command outputs)

**D-1 — `issues.description` is a plain `text` column (storage is not “rich text typed”).**

```sql
$ cd .beads/dolt/fizzy
$ dolt schema show issues
issues @ working
CREATE TABLE `issues` (
  `id` varchar(255) NOT NULL,
  `content_hash` varchar(64),
  `title` varchar(500) NOT NULL,
  `description` text NOT NULL,
  `design` text NOT NULL,
  `acceptance_criteria` text NOT NULL,
  `notes` text NOT NULL,
  `status` varchar(32) NOT NULL DEFAULT 'open',
  `priority` int NOT NULL DEFAULT '2',
  `issue_type` varchar(32) NOT NULL DEFAULT 'task',
  `assignee` varchar(255),
  `estimated_minutes` int,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(255) DEFAULT '',
  `owner` varchar(255) DEFAULT '',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `closed_at` datetime,
  `closed_by_session` varchar(255) DEFAULT '',
  `external_ref` varchar(255),
  `spec_id` varchar(1024),
  `compaction_level` int DEFAULT '0',
  `compacted_at` datetime,
  `compacted_at_commit` varchar(64),
  `original_size` int,
  `sender` varchar(255) DEFAULT '',
  `ephemeral` tinyint(1) DEFAULT '0',
  `no_history` tinyint(1) DEFAULT '0',
  `wisp_type` varchar(32) DEFAULT '',
  `pinned` tinyint(1) DEFAULT '0',
  `is_template` tinyint(1) DEFAULT '0',
  `mol_type` varchar(32) DEFAULT '',
  `work_type` varchar(32) DEFAULT 'mutex',
  `source_system` varchar(255) DEFAULT '',
  `metadata` json DEFAULT (json_object()),
  `source_repo` varchar(512) DEFAULT '',
  `close_reason` text DEFAULT '',
  `event_kind` varchar(32) DEFAULT '',
  `actor` varchar(255) DEFAULT '',
  `target` varchar(255) DEFAULT '',
  `payload` text DEFAULT '',
  `await_type` varchar(32) DEFAULT '',
  `await_id` varchar(255) DEFAULT '',
  `timeout_ns` bigint DEFAULT '0',
  `waiters` text DEFAULT '',
  `due_at` datetime,
  `defer_until` datetime,
  `started_at` datetime,
  PRIMARY KEY (`id`),
  KEY `idx_issues_assignee` (`assignee`),
  KEY `idx_issues_created_at` (`created_at`),
  KEY `idx_issues_external_ref` (`external_ref`),
  KEY `idx_issues_issue_type` (`issue_type`),
  KEY `idx_issues_priority` (`priority`),
  KEY `idx_issues_spec_id` (`spec_id`),
  KEY `idx_issues_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

**D-2 — Current issues in this repo have empty JSON metadata.**

```sql
$ cd .beads/dolt/fizzy
$ dolt sql -q "select id, JSON_LENGTH(metadata) as metadata_len, metadata from issues"
+-----------+--------------+----------+
| id        | metadata_len | metadata |
+-----------+--------------+----------+
| fizzy-08o | 0            | {}       |
| fizzy-0zx | 0            | {}       |
| fizzy-jul | 0            | {}       |
+-----------+--------------+----------+
```

**D-3 — Beads export is JSONL; the exported “issue object” shape is not 1:1 with raw Dolt columns.**

```json
$ bd export --no-memories | head -n 2
{"id":"fizzy-08o","title":"P1: Foundational Gap Inventory — Fizzy ↔ Beads","description":"First Planning round of the 20-round program. Produces a comprehensive single source of truth at llm/notes/p1-foundational-gap-inventory.md covering five sections: A) every Fizzy domain entity + field with file:line refs; B) every beads schema field; C) mapping table (Fizzy → beads OR Fizzy-only OR hybrid); D) verified-assumption table for CEO-flagged items (rich text, attachments, mentions, reactions, search, deps); E) numbered architectural questions surfaced for S* rounds. This is the foundational input for all S1-S10 spec rounds.","acceptance_criteria":"Five sections (A-E) populated; quoted command outputs / file:line refs throughout; no vague AC; ratified by Claude+Codex+Gemini via [P1: agreed] signals.","status":"open","priority":1,"issue_type":"task","assignee":"fizzy-claude","owner":"timm@stokke.me","created_at":"2026-04-17T20:41:13Z","created_by":"Timm Stokke","updated_at":"2026-04-17T20:41:13Z","labels":["foundational","gap-analysis","planning"],"dependency_count":0,"dependent_count":0,"comment_count":0}
{"id":"fizzy-0zx","title":"Sample comprehensive issue","description":"This is a detailed description to test the data model","design":"Using MVC pattern","acceptance_criteria":"All tests pass","status":"open","priority":1,"issue_type":"task","assignee":"timm@stokke.me","owner":"timm@stokke.me","estimated_minutes":480,"created_at":"2026-04-17T18:16:54Z","created_by":"Timm Stokke","updated_at":"2026-04-17T18:16:54Z","labels":["data-model","test"],"dependency_count":0,"dependent_count":0,"comment_count":0}
```

**D-4 — Beads search exists, but the help describes title/ID search + substring filters; no dedicated FTS schema is visible in Dolt.**

```text
$ bd search --help | sed -n '1,12p'
Search issues across title and ID (excludes closed issues by default).

ID-like queries (e.g., "bd-123", "hq-319") use fast exact/prefix matching.
Text queries search titles. Use --desc-contains for description search.
Use --status all to include closed issues.
```

**D-5 — 10 dependency types are supported by `bd dep add --type`.**

```text
$ bd dep add --help | grep -F "Dependency type"
  -t, --type string         Dependency type (blocks|tracks|related|parent-child|discovered-from|until|caused-by|validates|relates-to|supersedes) (default "blocks")
```

**D-6 — `bd link` is a shorthand that supports only 5 dependency types.**

```text
$ bd link --help | grep -F "Dependency type"
  -t, --type string   Dependency type (blocks|tracks|related|parent-child|discovered-from) (default "blocks")
```

**D-7 — Fizzy bearer-token JSON API is real (Fizzy-side evidence).**

Three load-bearing files together implement the bearer-token JSON API path:

`app/controllers/concerns/authentication.rb:60–72`:
```ruby
if bearer_token_authenticatable_request?
  if token = request.headers["Authorization"]&.split(" ", 2)&.last
    if identity = Identity.find_by_permissable_access_token(token, method: request.method)
      ...
    end
  end
end

def bearer_token_authenticatable_request?
  request.format.json?
end
```

`app/controllers/concerns/request_forgery_protection.rb:10–14`:
```ruby
super || allowed_api_request?

def allowed_api_request?
  sec_fetch_site_value.nil? && request.format.json?
end
```

`app/models/identity/access_token.rb:5–7`:
```ruby
enum :permission, %w[ read write ].index_by(&:itself), default: :read

def allows?(method)
  ...
end
```

So the surface is: any controller endpoint that responds to `format.json` becomes API-callable when a non-browser client sends `Authorization: Bearer <token>` (no `Sec-Fetch-Site` header). The `Identity::AccessToken#permission` enum gates write access — `GET`/`HEAD` are always allowed; mutation requires the `write` permission. Schema for `identity_access_tokens` is in `db/schema.rb` (see §A.2).

**D-8 — Fizzy multi-tenancy is path-prefix middleware (Fizzy-side evidence).**

`config/initializers/tenanting/account_slug.rb:3–32` (excerpt):
```ruby
PATH_INFO_MATCH = /\A(\/#{AccountSlug::PATTERN})/
...
if request.script_name && request.script_name =~ PATH_INFO_MATCH
  ...
elsif request.path_info =~ PATH_INFO_MATCH
  request.engine_script_name = request.script_name = $1
  request.path_info = $'.empty? ? "/" : $'
  env["fizzy.external_account_id"] = AccountSlug.decode($2)
end

if env["fizzy.external_account_id"]
  account = Account.find_by(external_account_id: env["fizzy.external_account_id"])
  Current.with_account(account) do
    @app.call env
  end
end
```

The middleware extracts a `/{external_account_id}` path prefix, moves it into `SCRIPT_NAME` (so Rails routes behave as if mounted there), and sets `Current.account` for the request. `Current.account` is then used implicitly by every account-scoped query throughout the app and by background jobs via the `AccountTenanted` concern that captures it at enqueue and restores it at perform.

Per CEO Q3 (ii), this entire mechanism is **retired in the fork** — single-tenant installs only. Implication: the middleware itself becomes dead code, and `account_id` columns across the schema (which are otherwise on essentially every table) become either always-`NULL` (drop), always-default-singleton (no-op), or fully removed via migration. The exact teardown is itself a future plumbing round; the gap inventory just flags the surface.

### Verdict table

| Assumption | Verdict | Evidence | Implication for §C mapping |
|---|---|---|---|
| 1) Beads description supports rich text / markdown | `PARTIAL` | D-1 (storage is `text`); D-3 (export shows plain strings) | Any “markdown” is a rendering convention. If Fizzy needs rich text (attachments/mentions), it likely lives in Fizzy tables keyed by `issues.id`, or in `issues.metadata` as a convention. |
| 2) Beads supports attachments | `REFUTED` (native) / `PARTIAL` (possible via `metadata`) | §B shows no attachment/blob tables; D-1 shows only `metadata json` as an extension point; D-2 shows `{}` currently | Attachments likely remain Fizzy-side (ActiveStorage) with FK to beads `issues.id`. If we ever store attachment refs in beads, it’s via `issues.metadata` (convention) not a first-class schema. |
| 3) Beads supports mentions | `REFUTED` (native) | §B: no mentions table; D-1 shows only `description`/`notes` text and `metadata json` | Mentions are Fizzy-side behavior (parse + render) and likely stored in Fizzy-only tables or computed at render time. |
| 4) Beads supports reactions | `REFUTED` (native) | §B: no reactions table; comments are plain `text` (see §B `comments`) | Reactions are Fizzy-only unless we invent a convention in `issues.metadata` (not recommended without spec). |
| 5) Beads has search / FTS | `CONFIRMED` (basic), `REFUTED` (schema-level FTS) | D-4; §B has no obvious FTS index/tables beyond normal secondary indexes | Expect basic search (title/ID) and filters. Anything like Fizzy’s 16-shard MySQL FTS is not present in beads schema. |
| 6) Beads has 10 dependency types | `CONFIRMED` | D-5 | Dependency semantics are beads-native; Fizzy UI should map its relationships onto this set rather than invent new ones. |
| 7) Beads `bd link` supports 5 dependency types | `CONFIRMED` | D-6 | Documentation/templates should use `bd link` only for the five simple types; all others must use `bd dep add --type`. |
| 8) Fizzy has bearer-token JSON API | `CONFIRMED` | See evidence block D-7 (below) | Mapping decision: in the fork, the bearer-token JSON API stays as the natural surface for any external integration. New beads-backed endpoints go through the same auth gates. |
| 9) Fizzy multi-tenancy via path prefix middleware | `CONFIRMED` (current behavior); `[Drop in fork]` (per CEO Q3 ii) | See evidence block D-8 (below) | Mapping: the middleware + every `account_id` column become dead code in the fork. A future plumbing round will rip the middleware + reduce all per-account scopes to no-ops or removals. |
| 10) Beads schema is immutable | `CONFIRMED` (operating constraint) | CEO ground truth; RoE-4 §1 | All feature gaps get handled in adapter + Fizzy-side tables; never by altering Dolt schema. |

---

## §E — Architectural questions for spec phase (S1-S10)

> **Status**: drafted by `fizzy-claude` from §C mapping work; expects Codex contributions and Gemini third-lens additions.
>
> **Note (post-Planning)**: Many Q-S items below have been answered in Planning rounds P3–P10. P10 is the final synthesis and contains the definitive “answered vs open vs deferred” registry: `llm/notes/p10-fork-posture-summary.md` §G.

Each question follows this format:

> **Q-S-NNN — One-line question**
> Affected entities (from §A/§B/§C). Why it matters (one sentence). Candidate options (when any are obvious).

The Spec rounds (S1–S10) must answer **every** question below before implementation can begin. Some questions group naturally (data path, UI projection, auth bridging) and may consume one Spec round each.

### E.1 Data path (how Fizzy talks to Beads at runtime)

> **Q-S-001 — How does Fizzy read Beads issues at runtime?**
> All Beads-backed entities (Card and beyond). Defines the connection model and per-request cost.
> Candidates:
> - (a) Shell out to `bd` CLI per query (simple but per-request fork cost; CLI output parsing).
> - (b) Connect to the embedded Dolt SQL server (port 54309 today) via `Trilogy/Mysql2` adapter (reuses Rails AR; no fork overhead).
> - (c) Hybrid: read via Dolt SQL, write via `bd` CLI (preserves bd hooks/audit).

> **Q-S-001a — How does Fizzy *write* to Beads?**
> Same scope as Q-S-001 but write side. Beads has hooks/audit/events that fire only on `bd` CLI writes (not raw SQL writes). Candidates: (a) always via `bd` CLI; (b) raw SQL with handcrafted event-emission; (c) `bd` CLI for mutations + SQL for reads.

> **Q-S-002 — Where do Fizzy-side concerns physically live?**
> Rich text, attachments, mentions, reactions, steps, pins, watches, push subscriptions, search records, filters, notifications, webhooks. Defines the storage boundary.
> Candidates:
> - (a) Separate MySQL tables FK'd to `issues.id` (string FK).
> - (b) Stuffed into `issues.metadata` JSON (extension point).
> - (c) Hybrid: small structured fields in metadata, large/queryable in MySQL sidecar tables.
> - Recommendation: (a) for everything beyond a few key-value extensions, with §F adapter spec.

> **Q-S-002a — Schema migration cost: changing UUID FKs to string?**
> Every Fizzy table that references `cards.id` (Comment, Closure, Tagging, Assignment, Reaction, Step, Mention, Pin, Watch, Notification, ActionText::RichText, ActiveStorage::Attachment via polymorphic, etc.) must change `card_id uuid` → `card_id varchar(255)` (Beads id format). Spec round must enumerate every column.

### E.2 UI projection (how the kanban shows beads)

> **Q-S-003 — How does the kanban "board" + "column" concept project onto Beads?**
> ANSWERED in P4: `llm/notes/p4-ui-projection-deep-dive.md` §H.
> Board, Column, Card. Defines the v1 UI mapping.
> Candidates:
> - (a) Board = saved Filter (a Fizzy `Filter` row); Column = group-by Beads `status` value within that filter.
> - (b) Board = a Beads label (e.g., `board:engineering`); Column = group-by Beads `labels` matching `column:*`.
> - (c) Hybrid: Board is Fizzy entity, Column is Fizzy entity, but each Card's column-membership is computed from Beads labels.

> **Q-S-009 — Does "Board" survive as a first-class entity, or collapse into a saved Filter?**
> ANSWERED in P4: `llm/notes/p4-ui-projection-deep-dive.md` §H.
> Affects all Board/Column/Access tables. UX impact: how users discover and switch context.

> **Q-S-010 — How does column position (drag-and-drop reorder) get stored?**
> ANSWERED in P4: `llm/notes/p4-ui-projection-deep-dive.md` §H.
> Beads has no per-card column-position. Candidates: (a) Fizzy keeps `cards.position` Fizzy-side; (b) Stuff position into `issues.metadata.fizzy_column_position`; (c) Compute from labels (lossy).

> **Q-S-028 — How does Fizzy `Card::Goldness` interact with Beads `priority` (0-4)?**
> ANSWERED in P4: `llm/notes/p4-ui-projection-deep-dive.md` §H.
> Card, Card::Goldness, issues.priority. UX: do we surface beads priority as a UI field, hide goldness, or merge them?
> Candidates: (a) Surface beads priority, drop goldness (cleaner); (b) Keep goldness as Fizzy-only badge, surface priority separately; (c) Map `golden=true` ↔ `priority=0` (P0).

> **Q-S-029 — How does Fizzy surface Beads `issue_type` (task/bug/feature/epic/chore/decision)?**
> ANSWERED in P4: `llm/notes/p4-ui-projection-deep-dive.md` §H.
> Beads-native field new to Fizzy UI. Affects card-creation UI and filtering.

> **Q-S-030 — Which of the 10 dependency types are visible in v1 UI?**
> ANSWERED in P4: `llm/notes/p4-ui-projection-deep-dive.md` §H.
> All of `dependencies` table. Recommendation: surface all 10 with grouping (hierarchy: blocks/parent-child; relations: tracks/related/relates-to; lifecycle: discovered-from/until/caused-by/validates/supersedes), but spec round confirms grouping.

> **Q-S-031 — How does `issues.parent_id` (hierarchy) render in the kanban?**
> ANSWERED in P4: `llm/notes/p4-ui-projection-deep-dive.md` §H.
> Tree view? Indented children in a column? Collapsing parent? V1 may pick a minimal "show parent ↔ child link in detail view" without full tree UI; spec decides.

### E.3 Auth & identity bridging

> **Q-S-004 — How does Fizzy's `Identity::AccessToken` coexist with Beads' git-identity `actor`?**
> Identity, Identity::AccessToken, all Beads writes (which require `BD_ACTOR`).
> Candidates: (a) Fizzy resolves bearer token → identity email → exports `BD_ACTOR=<email>` for the `bd` subprocess; (b) Beads writes always use a fixed `BD_ACTOR=fizzy-rails` and the actual user is recorded only in Fizzy's Event log; (c) Hybrid.

> **Q-S-008 — How does `User` simplify in single-tenant?**
> User, Identity, all `creator_id`/`assignee_id`/`user_id` FKs. Multi-tenancy is gone but multi-user team is intact (per Q-S-006a). User-as-team-member persists; account_id collapses to constant.
> Candidates: (a) Keep `User` model intact; account_id becomes constant; identity-to-user is still 1:N (one identity could be the same User across reinstalls if we allow re-import) (recommendation). (b) Inline `name` + `role` into `Identity` and drop `User` (lossier; conflicts with role-per-team-member intent if we ever re-introduce multi-tenancy). (c) Keep User but treat `User.identity_id` as the only stable reference (deprecate `user_id` everywhere in favor of `identity_id`).

### E.4 Lifecycle adapter (status, postpone, close)

> **Q-S-013 — How do Fizzy `drafted` / `published` map to Beads status?**
> ANSWERED in P6: `llm/notes/p6-lifecycle-adapter.md` §I (draft/publish collapses to inbox vs on-board via board-membership labels).
> Card, issues.status. Beads default statuses: open / in_progress / blocked / deferred / closed (+ custom). "Drafted" has no clean beads equivalent.
> Candidates: (a) Fizzy `drafted` maps to a custom Beads status `draft` added to `custom_statuses`; (b) Drafted is Fizzy-only flag (issues.metadata.draft=true) until first publish, then issue is created in beads; (c) Drop `drafted` (cards always exist as beads issues from creation).

> **Q-S-014 — How does the `Closure` row's `closed_by_user_id` survive the move to beads `status=closed`?**
> ANSWERED in P6: `llm/notes/p6-lifecycle-adapter.md` §I (derive close attribution from Beads `issues.closed_at` + `events.actor`; no Fizzy `closures` source-of-truth).
> Closure model, beads events history.
> Candidates: (a) Read closing actor from Beads `events` history (where bd records who closed); (b) Keep Fizzy `closures` table FK'd to `issues.id` for the closer info; (c) Stuff in metadata.

> **Q-S-015 — What does "postpone" become — `status=deferred` only, or `status=deferred + defer_until`?**
> ANSWERED in P6: `llm/notes/p6-lifecycle-adapter.md` §I (manual postpone = deferred + optional defer_until; entropy postpone = deferred + required defer_until).
> Card::NotNow, issues.status, issues.defer_until.
> Candidates: (a) Status only (manual reopen); (b) Status + defer_until from entropy config (auto-reopen at expiry).

> **Q-S-016 — How does Board-level entropy translate to per-issue `defer_until`?**
> ANSWERED in P6: `llm/notes/p6-lifecycle-adapter.md` §I (keep entropy config Fizzy-side; recurring job writes Beads defer_until via CLI with system actor).
> Entropy, Board, issues.defer_until.
> Candidates: (a) Auto-postpone job iterates board's issues, sets `defer_until` per-issue based on board entropy + last_active_at; (b) Entropy retires (per-issue defer becomes manual); (c) Hybrid.

### E.5 Identity, IDs, FKs

> **Q-S-011 — Schema migration cost: every Card FK changes from UUID to string.**
> Every model with `card_id`. Migration is non-trivial and must be tested.
> Candidates: (a) New columns `card_beads_id varchar(255)` alongside existing UUID, dual-write during cutover; (b) Big-bang migration changes types in one go.
>
> Tombstone / superseded: this is the same work item as Q-S-002a and was effectively answered in P3 (posture + impacted tables list): `llm/notes/p3-data-path-decision.md` §E.

> **Q-S-018 — How is Fizzy's many-assignee model preserved when Beads has single `assignee`?**
> Assignment (max 100), issues.assignee.
> Candidates: (a) Beads `assignee` mirrors "primary" assignee; Fizzy keeps a `assignments` sidecar table FK'd to `issues.id` for the rest. (b) All assignees serialize into `issues.metadata.assignees: [...]`. (c) One assignee per card (lossy; reduces feature). **Recommendation**: (a).
>
> ANSWERED in P7: `llm/notes/p7-multi-assignee-tags-labels.md` §G.

### E.6 Tags / labels

> **Q-S-017 — How do Fizzy `Tag` records sync with Beads `labels`?**
> Tag, Tagging, Beads `labels` table.
> Candidates: (a) Tag is a Fizzy-only display object whose name == Beads label string; tagging a card adds the label to the issue; deleting tag deletes the label. (b) Drop the Fizzy Tag table; labels are first-class strings only (loses Fizzy `Tag.title` normalization rules).
>
> ANSWERED in P7: `llm/notes/p7-multi-assignee-tags-labels.md` §G.

### E.7 Comments, mentions, reactions, steps

> **Q-S-019 — How does Fizzy's `Comment.body` (rich text) map to Beads `comments.<text>` (plain)?**
> Comment, ActionText::RichText, Beads `comments` table.
> Candidates: (a) Beads holds plaintext, Fizzy ActionText sidecar holds HTML, joined by Beads comment id; (b) Render HTML on demand from markdown stored in beads (lossy if user used HTML-only features).

> **Q-S-020 — Does `Step` (card checklist) survive in v1?**
> Step model.
> Candidates: (a) Yes, Fizzy-only sidecar table FK'd to issue; (b) Drop in v1 (no UI for checklists); (c) Use beads `acceptance_criteria` as a single-text-field checklist.

### E.8 Events, notifications, webhooks

> **Q-S-005 — How do Fizzy webhook events get triggered when state changes happen via `bd` CLI?**
> Webhook, Webhook::Delivery, Beads `events`.
> Candidates: (a) Beads `bd` post-commit hook calls back into Fizzy via internal HTTP to fire webhooks; (b) Fizzy polls Beads `events` table on a recurring job and emits webhooks for unseen entries; (c) Fizzy is the only writer to Beads (Q-S-001a option a), so webhooks fire from the Fizzy controller as today.
>
> ANSWERED in P8 (posture + requirements; bridging implementation deferred): `llm/notes/p8-events-sync.md` §H.

> **Q-S-021 — Two-way Event log (Fizzy `events` ↔ Beads `events`): which is canonical?**
> Event, Beads events table.
> Candidates: (a) Beads is canonical for any task-data event; Fizzy events table is dropped or becomes a UI-only projection; (b) Fizzy events table mirrors Beads events for fast UI reads; (c) Fizzy keeps its own events for non-task domain actions (auth, account-lifecycle) and Beads owns task events.
>
> ANSWERED in P8: canonical = Beads events+comments: `llm/notes/p8-events-sync.md` §C.

> **Q-S-022 — Do outbound HTTP webhooks survive in v1?**
> Webhook, Webhook::Delivery. CEO Q6 deferred webhooks; this question confirms / re-confirms.
> Recommendation: Drop in V1 (already deferred); pull from §C.
>
> DECIDED in P8/P10: webhooks as a concept remain, but **Beads-driven webhook bridging is deferred to v2+**. See `llm/notes/p8-events-sync.md` §E and `llm/notes/p10-fork-posture-summary.md` §E.

### E.9 Search

> **Q-S-023 — How does search work — Fizzy 16-shard FTS, `bd search`, or hybrid?**
> Search::Record, bd search, Filter.
> Candidates: (a) Fizzy keeps the 16-shard FTS over a Fizzy projection table populated from Beads writes; (b) Fizzy delegates all search to `bd search` (and adds Fizzy-side terms via JOINs); (c) Hybrid by entity type.
>
> ANSWERED in P9: `llm/notes/p9-search-strategy.md` §A.

> **Q-S-024 — How do Fizzy `Filter` queries execute against Beads?**
> Filter and 6 join tables.
> Candidates: (a) Adapter translates Filter to a `bd query` expression; (b) Adapter translates Filter to a Dolt SQL query (assumes Q-S-001 chose SQL access).
>
> ANSWERED in P9: filter executes against Fizzy Card mirror (no cross-DB joins): `llm/notes/p9-search-strategy.md` §B.

### E.10 Storage / attachments

> **Q-S-025 — How does ActiveStorage attach to a Beads issue id (string, not UUID)?**
> ActiveStorage::Attachment polymorphic columns.
> Candidates: (a) Polymorphic `record_type='Card'`, `record_id=<beads-issue-id-string>` (requires schema migration of `record_id` from uuid to string); (b) New polymorphic-to-string columns alongside; (c) New Fizzy-side `card_attachments` join table that bridges.

> **Q-S-026 — Do `StorageEntry` / `StorageTotal` (per-account quotas) survive single-tenant?**
> Storage tracking models.
> Candidates: (a) Drop entirely (no quota in single-tenant); (b) Keep aggregate per-install quota; (c) Keep per-board quota only.

### E.11 Other open architecture questions

> **Q-S-006 — What does the `Account` model collapse to in single-tenant?**
> Account model, every account_id column.
> Candidates: (a) Singleton row auto-created on install; `account_id` columns become a constant FK (no-op scoping, schema preserved). **Recommendation**. (b) Drop Account model entirely, migrate-drop account_id columns. (c) Soft-keep (Account::Singleton convention) with no actual table.

> **Q-S-006a — Does multi-user team / invites / roles / per-board access survive in V1?**
> Account, Account::JoinCode, User (with `role` enum), Access (per-board ACL), Watch, Pin, Notification.
> Distinction: single-tenant (one install) ≠ single-user (one human). The fork can still support a team within one install. CEO Q4a is silent on team — defaulting to "yes, team survives" until told otherwise.
>
> ANSWERED in P5: **YES**; User model intact: `llm/notes/p5-auth-bridging.md` §G.
> Candidates: (a) Yes, team survives intact (recommendation); roles, invites, per-board access, notifications all in V1. (b) Drop multi-user — single-user single-install only (radical simplification; UX impact significant). (c) Hybrid: keep User+roles, drop per-board Access (everyone sees everything in v1).
> **Recommendation**: (a). Surface to CEO if Codex/Gemini disagree.

> **Q-S-007 — What is the export/import story for the fork?**
> ANSWERED in P10 (posture): `llm/notes/p10-fork-posture-summary.md` §B.
> Account::Export, Account::Import, ZipFile.
> Candidates: (a) Use `bd export` / `bd import` JSONL only (Fizzy-side data is not exported); (b) Build a parallel Fizzy-side ZIP that bundles ActionText, ActiveStorage, etc.; (c) Defer to v2.

> **Q-S-012 — How does rich-text rendering source-of-truth work for `Card.description`?**
> Card.description rich text, beads `issues.description` plain text.
> Candidates: (a) Beads holds plaintext (input), Fizzy ActionText holds HTML (rendering); when user edits in UI, both update; (b) Beads holds markdown (which renders both via Fizzy and via `bd`); (c) Beads holds plain text, Fizzy renders to HTML on read using a known transform.

> **Q-S-027 — Backup strategy for the fork?**
> ANSWERED in P10 (posture): `llm/notes/p10-fork-posture-summary.md` §C.
> All Fizzy + all Beads.
> Candidates: (a) `bd dolt push` for Beads + Git push for Fizzy code/skills/notes (current pattern, but `bd dolt push` is broken — needs plumbing fix); (b) Single tarball script that grabs both; (c) Defer.

> **Q-S-032 — What gets stored in `issues.metadata` JSON vs a Fizzy sidecar table?**
> issues.metadata, all Fizzy-only entities considered for "metadata" storage.
> Recommendation: anything queryable or relationally linked → sidecar; small flag/key-value scalars → metadata.

### E.12 Beads features deferred to v2

Out of scope for V1 (per CEO Q4a) — captured here for completeness so spec rounds remember to leave them alone:

- `wisps` + `wisp_*` tables (gates, molecules, swarms infrastructure)
- `federation_peers` (multi-repo / multi-workspace sync)
- External integrations (jira/linear/github sync via `bd jira sync`, etc.)

### E.13 Questions Codex / Gemini may add

Codex and Gemini are explicitly invited to add additional Q-S-NNN entries during review. Numbering is reserved up to **Q-S-099** for this round; if we exceed, P2 will continue numbering from Q-S-100.

---

## Convergence signal (P1)

When all three agents agree P1 is complete, each sends:

`[FROM→TO P1: agreed]`

After all signals land in `llm/LOG.md`, this file is locked, the bead `fizzy-08o` is closed, and we open P2 with a handoff entry.
