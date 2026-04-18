# S2 — Board/Column/Access Projection Spec (Beads-backed Cards)

**Status**: v1 ready for peer review
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

### A.1 What “board membership” means in the fork

Upstream Fizzy: `Card` belongs_to `Board` (`app/models/card.rb:7`) and board membership is stored as `cards.board_id` (uuid).

Fork doctrine (P4): Board remains a first-class Fizzy entity, but **membership is encoded in Beads labels** using a reserved namespace:

- Canonical membership label: `fizzy/board/<board_uuid>` (P4 §A.5).
- Single-board invariant: at most one `fizzy/board/*` label per issue (P4 §A.4).

Because all UI queries must be satisfiable from MySQL (no cross-DB joins), the Beads label state must be projected into MySQL via the Card mirror’s tag tables:

- `tags.title` is the label string (P7; `db/schema.rb:773-779`).
- `taggings(card_id, tag_id)` is the join table (S1 keeps + widens `taggings.card_id`; `db/schema.rb:762-770`).

### A.2 Board membership label generator (exact string)

Implementation must define exactly one helper that computes the membership label, and all reads/writes use it.

Proposed canonical helper:

- `Board#membership_label` → `"fizzy/board/#{id}"`

Rationale:
- Stable across renames.
- Collision-safe due to reserved `fizzy/` prefix (P7 §C).

### A.3 Board.cards query (computed, not association)

Current `Board::Cards` defines `has_many :cards` with `dependent: :destroy` (`app/models/board/cards.rb:5`), and `Board` depends on that in multiple places (controllers, accessible cleanup, tags-through-cards).

In the fork, **Board.cards must become a computed relation**:

- Membership is `taggings → tags` match on `membership_label`.
- Access restriction remains enforced by `Current.user.boards.find` (already used in `BoardsController#set_board`, `app/controllers/boards_controller.rb:68`) and by `BoardScoped` (`app/controllers/concerns/board_scoped.rb:10`).

Canonical AR relation (MySQL-only):

```ruby
Card
  .joins(taggings: :tag)
  .where(tags: { title: membership_label })
```

Note: board membership must be mirrored into `taggings` by the Beads→Fizzy poller (owned by S9), otherwise the board will appear empty until projection catches up.

### A.4 Inbox / “awaiting triage” in V1

Upstream uses triage = “active cards missing column” (`Card::Triageable.awaiting_triage` is `active.where.missing(:column)`, `app/models/card/triageable.rb:7`), and `BoardsController#show_columns` uses `@board.cards.awaiting_triage` (`app/controllers/boards_controller.rb:87`).

Fork posture:
- “Triage / Inbox” becomes **boardless**: issues with **no `fizzy/board/*` membership label**.
- Board view shows cards that *do* have the board membership label; inbox view shows boardless cards.

This spec does not define the inbox UI (that is part of S2 controller/view work), but it does define the query shape (see §C.3).

## §B — Column projection model

### B.1 Column is a mapping rule (not a Card association)

Upstream Column has `has_many :cards, dependent: :nullify` (`app/models/column.rb:6`) and touches cards on name/color changes (`app/models/column.rb:8-9`).

Fork: column membership is derived from Beads issue state, so Column cannot “own” cards via `cards.column_id`.

Primary grouping dimension (P4 §B.1): **Beads `issues.status`**, mirrored onto MySQL `cards.beads_status` (P9 §A.2; S1 F.1 bead `fizzy-m6r`).

### B.2 Default column set and crisp status mapping (Gemini prior #3)

V1 default workflow for any new board must be consistent and predictable.

Canonical default columns:

| Column (UI label) | `columns.beads_status` | Cards included |
|---|---|---|
| Todo | `open` | `cards.beads_status='open'` |
| Doing | `in_progress` | `cards.beads_status='in_progress'` |
| Blocked | `blocked` | `cards.beads_status='blocked'` |
| Not now | `deferred` | `cards.beads_status='deferred'` |
| Done | `closed` | `cards.beads_status='closed'` |

Pinned is explicitly *not* a column (P4 §C.3); it is a board overlay section (see §E/§F).

### B.3 Label-driven custom columns (optional in V1, but specified)

The S2 brief requires a design for label-driven custom columns. We specify it here, while allowing V1 to ship only default columns.

Proposed model:
- Every Column has **one required** `beads_status` value.
- Optionally, a Column can also have a `match_label` rule: only cards with that label appear in that Column.
- Column ordering (`columns.position`, P4 §B.2) determines precedence when multiple columns share the same `beads_status`:
  - Evaluate columns in `position` order and place a card into the **first** column whose rule matches.
  - Provide a final “catch-all” column per status with no `match_label` so every card is placeable.

This yields “label-driven custom columns” without abandoning the status-driven backbone.

### B.4 Column ordering storage (kept)

Column ordering stays in `columns.position` per-board (P4 §B.2). The existing “move left/right” endpoints keep working:
- `Columns::LeftPositionsController#create` (`app/controllers/columns/left_positions_controller.rb:4-11`)
- `Columns::RightPositionsController#create` (`app/controllers/columns/right_positions_controller.rb:4-11`)

### B.5 Required schema additions (implementation detail; authored as beads)

To implement B.2/B.3 without abusing `columns.name`, we need explicit mapping columns. Proposed migration in I-S2:
- `columns.beads_status` string limit 32, NOT NULL (defaulted during backfill/seed)
- `columns.match_label` string (nullable) for label-driven custom columns (optional)

These are Fizzy-side projection metadata (allowed per P3/P4), not Beads schema changes.

## §C — Card placement query plan (MySQL-only)

This section is intentionally explicit about AR/SQL shapes and *forbids* cross-DB joins (Gemini prior #1).

All board/column queries MUST be computed from:
- `cards` (MySQL mirror table; `cards.id` is Beads issue id string post-S1)
- `cards.beads_status` (post-S1 F.1 `fizzy-m6r`)
- `taggings` + `tags` (MySQL mirror of Beads labels; post-S1 `fizzy-k48`)
- Fizzy-side tables: `accesses`, `columns`, `pins`

### C.1 Board membership relation (canonical)

Given `board = Board.find(...)`:

```ruby
membership_label = board.membership_label # "fizzy/board/<uuid>"

board_cards = Card
  .joins(taggings: :tag)
  .where(tags: { title: membership_label })
```

### C.2 Column placement (default columns)

Given `board_cards` and a default column:

```ruby
board_cards.where(beads_status: column.beads_status)
```

### C.3 Inbox (boardless) relation

Inbox is “cards without any membership label in the `fizzy/board/*` namespace”.

Anti-join query (works even if the card has other tags):

```ruby
board_label_tag_ids = Tag.where("title LIKE ?", "fizzy/board/%").select(:id)

inbox_cards = Card.where.not(
  id: Tagging.where(tag_id: board_label_tag_ids).select(:card_id)
)
```

### C.4 Access restriction and eager loading

Access restriction is by board-level access:
- The request already scopes to `Current.user.boards.find` (`BoardsController#set_board`, `app/controllers/boards_controller.rb:68`).
- Any cross-board listing (e.g. boards index) uses `Current.user.boards` (`app/controllers/boards_controller.rb:10`).

For board show, the computed `board_cards` relation should still preload sidecars:
- pins, watches, assignments, etc. (post-S1 FK widening).

This spec does not define the full preloading list (implementation detail), but it does require:
- No `includes(:board)` on Card (board_id no longer exists).
- No `includes(:column)` on Card (column_id no longer exists).

## §D — Controller surface for V1 (Board/Column/Access)

### D.1 BoardsController

Keep the existing REST surface for Board CRUD:
- `BoardsController#index/new/create/edit/update/destroy` (`app/controllers/boards_controller.rb`)

But rewrite `BoardsController#show` path:
- Today: `show_columns` uses `@board.cards.awaiting_triage...` (board association + column triage).
- Fork: board show uses §C query plan and groups by Column projection rules (status/label).

Concrete controller anchor points to rewire:
- `BoardsController#show_filtered_cards` uses `@filter.cards` (`app/controllers/boards_controller.rb:81-84`) which in the fork must compile to Card mirror queries (no cross-DB joins). (Search/filter compilation is owned by S9, but S2 must ensure a Board-lens filter can be applied without relying on `cards.board_id`.)
- `BoardsController#show_columns` today sets `cards = @board.cards.awaiting_triage...` (`app/controllers/boards_controller.rb:86-90`). In the fork, this becomes:
  - `cards = board_cards` from §C.1
  - grouped into columns per §B.2/§B.3 rules
  - optionally split into “Inbox/triage” (boardless) elsewhere.

### D.2 AccessesController (board permissions UI)

Keep `Boards::AccessesController#index` as-is in concept (`app/controllers/boards/accesses_controller.rb:4-6`), but ensure any helper queries that currently rely on `board.cards` are updated (see Board::Accessible notes in §G).

### D.3 Columns reorder controllers

Keep the existing column position endpoints (B.4). These mutate only `columns.position` (Fizzy-side projection metadata) and do not touch Beads.

### D.4 Cards controllers that must change behavior (board/column/tag writes)

These controllers exist today and are the natural surfaces to preserve in the fork, but their implementations must switch from mutating AR columns (`board_id`, `column_id`) to mutating Beads state (labels/status) via CommandClient.

- **Move card between boards**: `Cards::BoardsController#update` calls `@card.move_to(@board)` today (`app/controllers/cards/boards_controller.rb:12-18`). In the fork, it must call a CommandClient method that enforces the single-board label invariant:
  - remove any `fizzy/board/*` label(s)
  - add `fizzy/board/<board_uuid>`

- **Move card between columns / triage**:
  - Today: triage is implemented by setting `cards.column_id` (`Card::Triageable#triage_into`, `app/models/card/triageable.rb:19-27`) and the UI for selecting columns is `Cards::ColumnsController#edit` (`app/controllers/cards/columns_controller.rb:2-6`).
  - Fork: “triage/column placement” is Beads `issues.status` (mirrored to `cards.beads_status`), so these flows become **status update** calls via CommandClient.
  - Exact argv table (which status values, and how custom statuses map) is owned by S4; S2 specifies controller intent + plumbing points.

- **Tagging UI**: `Cards::TaggingsController#create` calls `@card.toggle_tag_with` today (`app/controllers/cards/taggings_controller.rb:10-16`). In the fork, user tag toggles must call `bd update --add-label/--remove-label` (P7 validated flags) and rely on the poller to mirror into `tags/taggings`.

### D.5 Writes that touch Beads vs writes that are Fizzy-only

Beads-touching writes (must go through `Fizzy::Beads::CommandClient` per P3/P5):
- Move card between columns → `bd update <id> --status <status>` (exact argv and status table comes from S4; S2 defines the controller intent and surfaces placeholders).
- Move card between boards → remove existing `fizzy/board/*` label(s) + add `fizzy/board/<uuid>` label (exact argv uses P7 validated label flags).

Fizzy-only writes (AR, no Beads coupling):
- Board CRUD
- Column CRUD + reorder
- Access grant/revoke
- Pin create/destroy

## §E — Pin projection

Pins stay a Fizzy-side overlay (P4 §C.3: pinned is overlay, not column).

Query posture:
- Pins are `pins(card_id, user_id)` with `card_id` widened in S1 (`fizzy-4wm`).
- For a board, pinned cards are:

```ruby
board_cards.joins(:pins).where(pins: { user_id: Current.user.id })
```

Pin create/destroy endpoints are out of scope for this spec doc to enumerate exhaustively, but S2 child beads must cover pin overlay rendering + correctness after board membership is label-based.

Concrete controller anchor:
- `Cards::PinsController` (`app/controllers/cards/pins_controller.rb`) is Fizzy-side and should continue to function after S1 widens `pins.card_id` to varchar. It currently scopes via `CardScoped`; I-S2 must ensure `CardScoped` can resolve the correct card route key (see §H.4).

## §F — Kanban + List view query patterns + AC

V1 ships Kanban + List view (P4 §B.4). Both views must be sourced from the same §C substrate.

Kanban:
- Group cards by Column (default: beads_status) and render in `columns.position` order.
- Drag-drop between columns triggers Beads status update (S4 defines mapping + argv).

List:
- Renders the same set of `board_cards` but without kanban grouping.
- Must be keyboard navigable / screen-reader friendly, aligned with CEO Q9 “match Fizzy” a11y bar.

## §G — Single-board invariant enforcement (write-time + ingestion-time)

This is the junction between controller enforcement and poller drift correction (Gemini prior #2).

### G.1 Write-time enforcement (controllers)

Any operation that assigns a card to a board must enforce:
- Remove all existing labels matching `fizzy/board/*` (if any)
- Add exactly one label: `fizzy/board/<target_board_uuid>`

This should be implemented in a single place (CommandClient helper), so all controllers share invariant enforcement.

### G.2 Ingestion-time drift correction (poller)

Even with write-time enforcement, drift can exist:
- A user runs `bd` manually and adds a second board label.
- A partial failure during two-step remove+add leaves a card temporarily with 0 board labels.

Therefore the Beads→Fizzy poller (S9) must:
- Detect >1 board membership label on a single issue id.
- Apply a deterministic correction rule (to be implemented in S9/I-S9), e.g.:
  - Prefer the most-recent board label change event if available.
  - Otherwise prefer lexicographically smallest board uuid (stable) and remove others.

S2 owns specifying the requirement + writing an implementation bead that is “blocked on S9” (see §I).

### G.3 Access cleanup query rewrites (Board::Accessible)

`Board::Accessible#mentions_for_user` and `#notifications_for_user` currently join through `cards.board_id` and `comments.card_id` (`app/models/board/accessible.rb:65-98`). In the fork:
- `cards.board_id` no longer exists (board membership is label-based).
- `comments.card_id` remains (but changes type to varchar per S1; `fizzy-0b8`).

Therefore both queries must be rewritten to:
- Resolve the board membership label (`Board#membership_label`)
- Join through `taggings/tags` (Card mirror label projection) to restrict to cards on that board
- Preserve the two paths (Card mention vs Comment mention; Event→Card vs Event→Comment→Card) without relying on `cards.board_id`.

This rewrite is required to keep “remove inaccessible data when access revoked” behavior intact in single-tenant multi-user installs.

## §H — Open questions deferred to later spec rounds

1) Status mapping details (custom statuses, pinned semantics): owned by S4 lifecycle spec.
2) Poller exact algorithms, event cursors, and drift correction implementation: owned by S9 search/poller spec (S2 supplies invariants).
3) Labels mirroring details (Tag/Tagging mirror mechanics): owned by S5.
4) Card route key: controllers today often locate cards by `number` (e.g. `Cards::BoardsController#set_card`, `app/controllers/cards/boards_controller.rb:23-24`). Post-S1, `cards.id` becomes Beads issue id string. I-S2 must decide whether:
   - (a) routes move to `cards/:id` where `id` is Beads id string, or
   - (b) keep numeric `number` and teach the poller to populate it deterministically from Beads id.

## §I — Child bead inventory

Child beads (I-S2 implementation tasks) are minted under epic `fizzy-eq4` and must cover every §A–§G requirement.

All beads below are created and wired as:
- parent-child to `fizzy-eq4`
- intra-S2 `blocks` edges reflecting the intended implementation ordering
- cross-spec `blocks` edges to S1 migration beads where required (especially `fizzy-05q`, `fizzy-k48`, `fizzy-m6r`, `fizzy-4wm`)

| Bead | Title | Satisfies | Key dependencies |
|---|---|---|---|
| `fizzy-eq4.1` | Add `columns.beads_status` + `columns.match_label` | §B.5 | none (additive) |
| `fizzy-eq4.2` | Seed default columns on board create | §B.2 | `fizzy-eq4.1` |
| `fizzy-eq4.3` | `Board#membership_label` + reserved namespace | §A.2 | none |
| `fizzy-eq4.4` | Rewire `Board.cards` to label-based membership | §A.3, §C.1 | `fizzy-eq4.3`, `fizzy-05q`, `fizzy-k48` |
| `fizzy-eq4.5` | Rewire Column projection model (status+label rules) | §B.1–§B.4 | `fizzy-eq4.1` |
| `fizzy-eq4.6` | Board show projector/query object (Kanban+List substrate) | §C, §E, §F | `fizzy-eq4.4`, `fizzy-eq4.5`, `fizzy-05q`, `fizzy-k48`, `fizzy-m6r` |
| `fizzy-eq4.7` | Rewrite `BoardsController#show` to use projector | §D.1 | `fizzy-eq4.6` |
| `fizzy-eq4.8` | Rewrite `Cards::BoardsController` to move boards via bd label writes | §D.4, §G.1 | `fizzy-eq4.3` |
| `fizzy-eq4.9` | Rewrite `Cards::TaggingsController` to mutate Beads labels | §D.4 | (blocked on S5 label projection; TODO wire once S5 exists) |
| `fizzy-eq4.10` | Rewrite board access cleanup queries (`Board::Accessible`) | §G.3 | `fizzy-eq4.3`, `fizzy-eq4.4` |
| `fizzy-eq4.11` | Pins overlay remains functional after label membership | §E | `fizzy-eq4.6`, `fizzy-05q`, `fizzy-4wm` |
| `fizzy-eq4.12` | Specify + implement drift correction for single-board invariant | §G.2 | `fizzy-eq4.3` (implementation blocked on S9 poller) |
| `fizzy-eq4.13` | System tests for board projection + access + moves | §J | blocks on all other S2 children |

## §J — Validation checklist

Pre-lock checklist for S2:
- [x] §A–§H fully drafted (no TODO stubs)
- [x] §C query plan is MySQL-only and executable (no cross-DB joins)
- [x] §B default column ↔ status mapping is explicit
- [x] §G includes both write-time + ingestion-time halves
- [x] Child beads minted under `fizzy-eq4` and inventory table populated
- [x] Cross-spec blockedBy deps to S1 beads where required (`fizzy-05q`, `fizzy-k48`, `fizzy-m6r`, `fizzy-4wm`)
- [ ] `[CODEX→CLAUDE S2 v1 ready]` sent + peer review complete
- [ ] `[FROM→TO S2: agreed]` 3-of-3 lock
