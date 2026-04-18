# S5 — Labels + Assignees Spec (Beads-canonical labels mirror; assignments sidecar)

**Status**: v1 ready for peer review
**Bead**: `fizzy-h91` (epic)
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/s5-brief.md`

This spec turns the P7 multi-assignee + tags/labels doctrine into implementation-ready perfect beads, reconciling P7 with the mirror posture established by P9 + S1 + S2:

- **Labels**: Beads is source-of-truth; Fizzy `tags`/`taggings` are the MySQL mirror updated by the S9 poller. Writes go through `Fizzy::Beads::CommandClient` (S3) using `bd update --add-label/--remove-label/--set-labels`. Reserved `fizzy/` namespace enforced at controller boundary.
- **Assignees**: Fizzy `assignments` sidecar IS canonical for multi-assignee (Beads only supports single `assignee`). Primary assignee (chronologically first) mirrors to Beads via `bd update --assignee <email>` on every sidecar mutation.
- **Normalization**: every label flowing through CommandClient is downcased + leading-`#`-rejected (matches existing `Tag.title` validation).

P7 §B.2 originally suggested dropping the `taggings` join table; that decision was **superseded** by P9 (Card mirror doctrine) + S1 (`fizzy-k48` widens `taggings.card_id`) + S2 (label-based board membership queries against `taggings/tags`). S5 ratifies the mirror posture: `taggings` stays.

---

## §A — Beads-canonical label model + argv

### A.1 Source of truth

Beads `labels(issue_id, label)` is the source of truth. Every label is a normalized string. Labels are added/removed/replaced exclusively via `bd` writes; the S9 poller mirrors the resulting state into Fizzy `tags`/`taggings`.

### A.2 CLI argv table (canonical)

| Operation | `bd` argv | CommandClient method | Notes |
|---|---|---|---|
| Add one label | `bd update <id> --add-label <label>` | `add_label(id, label)` | Idempotent on Beads side |
| Remove one label | `bd update <id> --remove-label <label>` | `remove_label(id, label)` | Idempotent on Beads side |
| Replace whole set | `bd update <id> --set-labels <l1,l2,...>` | `set_labels(id, labels[])` | Comma-separated; replaces atomically |
| Add many in one call | `bd update <id> --add-label <l1> --add-label <l2>` | `add_label(id, l1); add_label(id, l2)` OR a `add_labels` helper | V1 implements one-at-a-time; bulk helper deferred (P7 Q-S-052) |

`--actor <email>` is the GLOBAL flag (per `bd --help`), placed BEFORE the subcommand. CommandClient (S3 §B.1) already prepends it on every invocation.

### A.3 Reserved namespace enforcement

Any user-typed label must NOT start with `fizzy/` (case-insensitive after downcase normalization). Enforcement is at the **controller validation** layer (rejects with a 422 + helpful error message before invoking CommandClient).

System code paths that legitimately write `fizzy/board/<uuid>` use a separate internal helper (`CommandClient#_add_system_label` or equivalent — see §C.4) which bypasses the controller validation but is callable only from internal Fizzy code (not from any user-facing controller).

### A.4 What NOT to do

- Do not write to `bd update --set-labels` from Fizzy controllers as a "convenience replace-all" — it's atomic, but it forces the controller to know the full label set, which couples the controller to the mirror state. Use `--add-label` / `--remove-label` for incremental UX (single tag toggle).
- Do not skip the Fizzy-side normalization expecting Beads to canonicalize; Beads stores labels verbatim.

## §B — `tags`/`taggings` mirror schema (the MySQL projection)

### B.1 Mirror posture (supersedes P7 §B.2)

P7 §B.2 originally proposed dropping the `taggings` join. P9 + S1 + S2 reversed that — `taggings` is required as the MySQL substrate for board projection (S2 §A.3) and search (P9 §A.2). S5 ratifies: **`tags` and `taggings` both stay** as Fizzy-side mirror tables, populated exclusively by the S9 poller.

### B.2 Schema (post-S1)

- `tags(id, account_id, title varchar, color, ...)` — unchanged from upstream; `title` carries the canonical (normalized) label string.
- `taggings(id, card_id varchar(255), tag_id, ...)` — `card_id` widened in S1 bead `fizzy-k48`.

### B.3 Poller responsibilities (S9-owned; S5 specifies the contract)

The S9 poller (placeholder beads `fizzy-1iz` lifecycle + `fizzy-6iv` labels) MUST:

1. For each Beads issue change event mentioning labels:
   - Compute the diff between Beads `labels(issue_id, label)` and current Fizzy `taggings.where(card_id: issue_id)` joined to `tags.title`.
   - For added labels: `Tag.find_or_create_by!(account_id:, title: normalized_label)` then `Tagging.upsert(card_id:, tag_id:, ...)`.
   - For removed labels: delete the matching `Tagging` row; do NOT delete the Tag (Tags are account-wide and may be reused).
2. Bypass AR callbacks per P9 §A.2 (use `Tagging.upsert_all` / `Tagging.delete` direct SQL); explicit `Search::Record.upsert_for_card(card)` after.
3. Respect tag dedup by normalized title — `Tag.find_or_create_by!(title: ...)` is the only path that creates Tags during mirroring.

### B.4 Eventually consistent

Fizzy controller writes through CommandClient land in Beads immediately; the mirror catches up on the next poller tick (P9 30s). The UI MAY optimistically display the change before the mirror confirms; reconciliation on next poller tick is acceptable. S5 does not specify the optimistic UI; that's I-S5 implementation choice.

## §C — `CommandClient` label methods (extends S3 §B.1)

### C.1 Public method signatures

```ruby
module Fizzy
  module Beads
    class CommandClient
      # ... S3-locked surface (close_issue, reopen_issue, defer_issue, ...) ...
      # ... S4-locked lifecycle methods ...

      # S5 additions:
      def add_label(id, label)
        normalized = LabelNormalizer.call(label)
        raise ArgumentError, "label '#{normalized}' uses reserved namespace fizzy/" if normalized.start_with?("fizzy/")
        invoke!(["update", id, "--add-label", normalized])
      end

      def remove_label(id, label)
        normalized = LabelNormalizer.call(label)
        invoke!(["update", id, "--remove-label", normalized])
      end

      def set_labels(id, labels)
        normalized = labels.map { |l| LabelNormalizer.call(l) }
        normalized.each do |l|
          raise ArgumentError, "label '#{l}' uses reserved namespace fizzy/" if l.start_with?("fizzy/")
        end
        invoke!(["update", id, "--set-labels", normalized.join(",")])
      end

      def set_assignee(id, email_or_nil)
        # email may be empty/nil to clear
        value = email_or_nil.to_s
        invoke!(["update", id, "--assignee", value])
      end

      private

      # Internal-only: callable from system code paths (board membership) that
      # legitimately write fizzy/-prefixed labels. NOT exposed to controllers.
      def _add_system_label(id, label)
        normalized = LabelNormalizer.call(label)  # still normalize
        invoke!(["update", id, "--add-label", normalized])
      end

      def _remove_system_label(id, label)
        normalized = LabelNormalizer.call(label)
        invoke!(["update", id, "--remove-label", normalized])
      end
    end
  end
end
```

### C.2 Why fizzy/-rejection lives in `add_label` / `set_labels` (not just controllers)

Defense-in-depth. Controller validation is the primary gate (§D), but the CommandClient method also rejects so internal-but-non-system code paths cannot accidentally write reserved labels by passing through `add_label`. System code uses `_add_system_label` (private) intentionally.

### C.3 Actor enforcement

All of `add_label`, `remove_label`, `set_labels`, `set_assignee` use `invoke!` which prepends `--actor <@actor>` per S3 §B.3. CommandClient cannot be constructed without an actor (S3 §B.2).

### C.4 System-label call site

`_add_system_label` and `_remove_system_label` are called only from:
- `Board` create/destroy flow (writes `fizzy/board/<uuid>` to issues moving onto/off the board) — this is S2 §G.1 controller enforcement
- Future system label managers (registry per §D.2)

These call sites construct CommandClient with the system actor: `CommandClient.for(SystemActor.identity)`. They are NOT routed through `Cards::TaggingsController` (which is user-facing).

## §D — Reserved label namespace registry

### D.1 Registry

| Prefix | Owner | Purpose | Writer |
|---|---|---|---|
| `fizzy/board/<board_uuid>` | P4 / S2 | Board membership | System (S2 board create/move handlers) |
| `fizzy/system/*` | reserved | Internal system labels (TBD use cases) | System |
| `fizzy/test/*` | reserved | Test fixtures' temp labels | Test setup |

Future S- or P-rounds may add prefixes; ALL system labels MUST use `fizzy/`.

### D.2 Controller-side validation

`Tag` model already validates: `validates :title, format: { without: /\A#/ }` + `normalizes :title, with: ->(s) { s.downcase }`.

S5 adds:
```ruby
class Tag < ApplicationRecord
  RESERVED_NAMESPACE = %r{\Afizzy/}i
  validates :title, format: { without: /\A#/ }
  validates :title, format: { without: RESERVED_NAMESPACE, message: "cannot use reserved fizzy/ namespace" }
  normalizes :title, with: ->(s) { s.downcase }
  # ...
end
```

This validation fires on `Tag.find_or_create_by!(title: ...)` in `Cards::TaggingsController#create`. The user gets a 422 before any Beads write happens.

### D.3 Server-side (poller) honoring

The S9 poller mirrors Beads → Fizzy. If Beads contains a `fizzy/board/<uuid>` label (legitimately written by S2 system code), the poller mirrors it into `tags`+`taggings` like any other label — it does NOT special-case the namespace. Board projection queries (S2 §C.1) JOIN against the membership label by exact string match, so the projection works regardless of how the label landed in `taggings`.

What about user-typed labels that bypass Fizzy validation (i.e., direct `bd update --add-label fizzy/something`)? Mitigations deferred to v2+ per P7 §D.4. V1 documents the convention; the poller mirrors as-is.

## §E — Tag normalization (boundary contract)

### E.1 LabelNormalizer

New file `lib/fizzy/beads/label_normalizer.rb`:

```ruby
module Fizzy
  module Beads
    module LabelNormalizer
      class InvalidLabelError < StandardError; end

      def self.call(raw)
        s = raw.to_s.strip.downcase
        raise InvalidLabelError, "label cannot start with #" if s.start_with?("#")
        raise InvalidLabelError, "label cannot be empty" if s.empty?
        s
      end
    end
  end
end
```

### E.2 Where it runs

Every `add_label`/`remove_label`/`set_labels` call in CommandClient runs through `LabelNormalizer.call`. This is the single chokepoint that ensures consistency between user input → controller validation → Beads write.

### E.3 Why strict reject (not silent strip)

Per P7 §D.2: matches existing upstream `Tag.title` validation (which rejects via `format: { without: /\A#/ }`, doesn't strip). User gets a clear error rather than seeing their input silently mutated. Easier to relax later than tighten.

### E.4 What about labels added via `bd` CLI directly?

If a user runs `bd update <id> --add-label "#Backend"` from the command line, that label lands in Beads as-is (no normalization on Beads side). Fizzy displays it as-is on read; the S9 poller mirrors it as-is into a `Tag` row with `title="#Backend"` — but wait, that violates the Tag validation `format: { without: /\A#/ }`!

**Mitigation in S5**: the S9 poller MUST `find_or_create_by!` with the normalized form, not the raw form. So a Beads label `#Backend` would be normalized to `backend` on the mirror side, and the Tag row would be `backend`. The user's `#` and `B` are lost in the mirror but Beads still has the original. This is acceptable — the canonical user-facing form is the normalized form.

S9 owns the exact poller behavior; S5 just specifies that normalization MUST run on the poller side too. (Captured in `fizzy-6iv` placeholder description / will be reaffirmed when S9 spec drafts.)

## §F — Assignment sidecar (multi-assignee preserved)

### F.1 Schema (post-S1)

`assignments(id, account_id, card_id varchar(255), assignee_id, assigner_id, ...)` — `card_id` widened in S1 bead `fizzy-h6i`. `account_id` becomes constant per P5/§C.1.

`Card.has_many :assignments, dependent: :destroy` and `has_many :assignees, through: :assignments`. Validation caps at 100 assignees per card.

### F.2 Multi-assignee canonical, primary mirrors to Beads

Per P7 §A.2:
- The `assignments` table is the **canonical** state of multi-assignee.
- "Primary assignee" = first `Assignment` row by `created_at` ASC.
- The primary's email mirrors to Beads `issues.assignee` via `bd update <id> --assignee <email>` whenever the primary changes.
- Other assignees are Fizzy-only (visible in UI, queryable, but invisible to `bd ready` / Beads CLI).

### F.3 Sync mechanism

`Assignment` AR callbacks:

```ruby
class Assignment < ApplicationRecord
  belongs_to :account, default: -> { card.account }
  belongs_to :card, touch: true
  belongs_to :assignee, class_name: "User"
  belongs_to :assigner, class_name: "User"

  after_create_commit :sync_primary_assignee_to_beads
  after_destroy_commit :sync_primary_assignee_to_beads

  validate :within_limit, on: :create

  private

  def sync_primary_assignee_to_beads
    primary = card.reload.assignments.order(:created_at).first
    primary_email = primary&.assignee&.identity&.email_address || ""
    Fizzy::Beads::CommandClient.current.set_assignee(card.id, primary_email)
  end

  def within_limit
    if card.assignments.count >= LIMIT
      errors.add(:base, "Card already has the maximum of #{LIMIT} assignees")
    end
  end
end
```

### F.4 Reassignment edge cases

- **Original primary removed**: next-oldest by `created_at` becomes primary; `set_assignee` mirrors. (Default; per P7 Q-S-051 leaning, future spec may add manual override UI.)
- **All assignees removed**: `set_assignee(card.id, "")` clears Beads `assignee`.
- **Concurrent assignment writes**: Rails after_commit callbacks fire after the DB transaction; `card.reload` ensures the latest count. Race conditions are possible if two assignments commit in the same instant — acceptable for V1 (eventually consistent; next callback reconciles).

### F.5 What about Beads-side direct assignee writes?

Per P7 §F.1: if a user runs `bd update <id> --assignee user@example.com` directly, that sets Beads `assignee` but does NOT create a Fizzy `Assignment` row. The next time any Fizzy assignment callback fires, it overwrites Beads back to the chronologically-first sidecar assignee. **Documented expected behavior**; users who write Beads directly accept Fizzy is authoritative for assignee state.

The S9 poller does NOT mirror Beads assignee → Fizzy assignments (that would create infinite re-mirror loops). The mirror is one-way: Fizzy → Beads.

## §G — `Cards::TaggingsController` rewire (closes S2 cross-spec dep `fizzy-eq4.9`)

### G.1 Current behavior (upstream)

`app/controllers/cards/taggings_controller.rb`:
- `#create` calls `@card.toggle_tag_with(params[:title])` which:
  - normalizes the title via `Tag` (downcase + reject `#`)
  - finds or creates the Tag
  - creates a `Tagging` row

### G.2 Fork behavior (post-S5)

- `#create` validates the user-typed title against Tag validations (downcase, reject `#`, reject `^fizzy/`).
- On validation pass: `Fizzy::Beads::CommandClient.current.add_label(card.id, title)`.
- Does NOT directly create Tag/Tagging — that's the poller's job (eventually consistent on next tick).
- Returns the (optimistic) Tag/Tagging shape for the UI to render immediately.

```ruby
class Cards::TaggingsController < ApplicationController
  before_action :set_card

  def create
    title = Fizzy::Beads::LabelNormalizer.call(params[:title])
    raise ArgumentError, "reserved namespace" if title.start_with?("fizzy/")

    Fizzy::Beads::CommandClient.current.add_label(@card.id, title)

    # Optimistic UI: render the tag as if it were already mirrored.
    # Poller will reconcile within ~30s.
    @tag = Tag.find_or_initialize_by(title: title) # for view rendering only; not persisted
    render :create, status: :created
  end

  def destroy
    title = Fizzy::Beads::LabelNormalizer.call(params[:title])
    Fizzy::Beads::CommandClient.current.remove_label(@card.id, title)
    head :no_content
  end

  private
  def set_card
    @card = Current.account.cards.find(params[:card_id])
  end
end
```

### G.3 Closing the S2 cross-spec dep

This rewrite IS the implementation of `fizzy-eq4.9` (S2 F.9). When S5 locks 3-of-3 and `fizzy-6iv` placeholder closes, `fizzy-eq4.9` becomes implementation-ready (still depends on S3 `fizzy-5jt`/`fizzy-r4v`, both already shipped post-S3 lock). I-S2 implementation can then unblock `fizzy-eq4.9`.

## §H — `Cards::AssignmentsController` rewire

### H.1 Current behavior (upstream)

`app/controllers/cards/assignments_controller.rb` (verify exact file):
- `#create` creates an `Assignment` row with `assignee` + `assigner: Current.user`.
- `#destroy` deletes the row.
- Validation cap of 100 enforced by `Assignment#within_limit`.

### H.2 Fork behavior (post-S5)

NO controller changes from upstream. The Beads sync happens via `Assignment` AR callbacks per §F.3 — `after_create_commit` and `after_destroy_commit` invoke `CommandClient.current.set_assignee(...)`.

This is intentional: assignments are Fizzy-canonical; the controller is pure AR. Only the Assignment model gains the sync callback.

### H.3 Validation order

Existing `within_limit` (capped at 100) stays. The Beads sync runs only after the AR row commits — so if the validation rejects the assignment, no Beads write occurs.

## §I — Test strategy

### I.1 Unit tests

`test/lib/fizzy/beads/label_normalizer_test.rb`:
- Downcases input.
- Strips surrounding whitespace.
- Raises `InvalidLabelError` on leading `#`.
- Raises `InvalidLabelError` on empty/whitespace-only input.

`test/models/fizzy/beads/command_client_test.rb` (extends S3 tests):
- `add_label("ID-1", "Backend")` → argv `["bd", "--actor", "x@y.com", "update", "ID-1", "--add-label", "backend"]`.
- `add_label("ID-1", "fizzy/board/abc")` → raises `ArgumentError` (reserved namespace).
- `remove_label`, `set_labels` argv composition.
- `set_assignee("ID-1", "")` → empty value passed correctly.

`test/models/tag_test.rb`:
- Existing `format: { without: /\A#/ }` validation continues to reject `#tag`.
- New `RESERVED_NAMESPACE` validation rejects `fizzy/anything`.

### I.2 Integration tests

`test/integration/cards/taggings_flow_test.rb`:
- POST `/cards/:id/taggings` with `title=backend` → CommandClient stub asserts `update ID --add-label backend`.
- POST with `title=#Backend` → 422 (normalizer rejects).
- POST with `title=fizzy/board/abc` → 422 (reserved namespace).
- DELETE `/cards/:id/taggings/<title>` → CommandClient stub asserts `update ID --remove-label backend`.

`test/integration/cards/assignments_flow_test.rb`:
- POST `/cards/:id/assignments` with `assignee_id=...` → AR row created + CommandClient stub asserts `update ID --assignee user@example.com`.
- DELETE → AR row destroyed + CommandClient stub asserts `update ID --assignee <next-oldest-email>` (or `""` if last).

### I.3 Mirror tests (out of scope for S5; S9 owns)

The poller's tag/tagging mirror behavior is tested under S9. S5 specifies the contract; S9 validates the mechanism.

## §J — Open questions deferred to later spec rounds

1) **Q-S-051 — Primary assignee promotion rules when original primary removed**: V1 default = next-oldest by `created_at`. Future S-assignee-primary may add manual override UI. (P7 §H.)
2) **Q-S-052 — Bulk-tag rate limiting**: bulk tagging (1000 issues × ~100ms shell-out = 100s) may need batching. V1 defers; if UX requires, add a job-queue wrapper. (P7 §H.)
3) **`fizzy/` divergence cleanup**: Beads-side direct writes that introduce non-canonical or reserved-namespace labels — V2 linter or auto-rewrite. (P7 §D.4.)
4) **Optimistic UI for tagging**: §G.2 mentions optimistic render; exact JS / Hotwire pattern is implementation detail for I-S5.
5) **Tag deletion UX**: deleting a Fizzy `Tag` (admin operation) requires removing the label from EVERY Beads issue that has it (P7 §B.4 admin-delete-tag flow). S5 specifies this happens via a job that iterates issues and calls `remove_label` for each; exact job design is I-S5.

## §K — Child bead inventory

Child beads (I-S5 implementation tasks) are minted under epic `fizzy-h91`.

Cross-spec placeholder closed on S5 lock:
- `fizzy-6iv` — S5 lock placeholder created during S2 dispatch; closed when S5 ratifies.

| F.N | Bead | Title | Satisfies | Key dependencies |
|---|---|---|---|---|
| F.1 | `fizzy-h91.1` | Implement `LabelNormalizer` + unit tests | §E | none |
| F.2 | `fizzy-h91.2` | Add `RESERVED_NAMESPACE` validation to `Tag` model | §D.2 | none |
| F.3 | `fizzy-h91.3` | Add label methods to CommandClient (`add_label`, `remove_label`, `set_labels`) | §A.2, §C.1 | `fizzy-5jt`, `fizzy-r4v`, `fizzy-h91.1` |
| F.4 | `fizzy-h91.4` | Add `set_assignee` method to CommandClient | §C.1, §F.3 | `fizzy-5jt`, `fizzy-r4v` |
| F.5 | `fizzy-h91.5` | Add `_add_system_label` / `_remove_system_label` private methods | §C.4 | `fizzy-h91.3` |
| F.6 | `fizzy-h91.6` | Rewire `Cards::TaggingsController#create/destroy` to use CommandClient | §G | `fizzy-h91.2`, `fizzy-h91.3`, `fizzy-3ad` |
| F.7 | `fizzy-h91.7` | Add `Assignment` AR callbacks to mirror primary assignee to Beads | §F.3 | `fizzy-h91.4`, `fizzy-h6i` (S1 widening) |
| F.8 | `fizzy-h91.8` | Tag deletion job: iterate issues + remove label + delete Tag | §J.5 | `fizzy-h91.3` |
| F.9 | `fizzy-h91.9` | Integration tests: TaggingsController flow (create/destroy + 422 paths) | §I.2 | `fizzy-h91.6` |
| F.10 | `fizzy-h91.10` | Integration tests: AssignmentsController flow + Beads sync | §I.2 | `fizzy-h91.7` |
| F.11 | `fizzy-h91.11` | Close `fizzy-6iv` placeholder on S5 lock (one-line bd close) | §K, brief DoD | locks (manual on lock commit) |

## §L — Validation checklist

Pre-lock checklist for S5:
- [x] §A CLI argv table complete and matches P7 §B.4 verified flags
- [x] §A.3 reserved namespace controller-side enforcement specified
- [x] §B explicitly supersedes P7 §B.2 with mirror posture (taggings stays)
- [x] §B.3 poller contract for label mirror specified (S9-owned mechanism)
- [x] §C CommandClient method signatures + actor enforcement + system-label private split
- [x] §D namespace registry + Tag validation (defense-in-depth)
- [x] §E LabelNormalizer rules + applied at every CommandClient call
- [x] §F assignment sidecar canonical for multi-assignee + primary mirrors to Beads
- [x] §G TaggingsController rewire closes S2 fizzy-eq4.9 cross-spec dep
- [x] §H AssignmentsController stays AR-shaped; sync via model callback
- [x] §I test strategy covers normalizer + CommandClient + controller flows
- [x] §K bead inventory complete + cross-spec deps to S3 (5jt, r4v, 3ad) + S1 (h6i) wired
- [x] §K F.11 explicitly closes `fizzy-6iv` placeholder on lock
- [ ] `[CLAUDE→CODEX S5 v1 ready]` sent + peer review complete
- [ ] `[FROM→TO S5: agreed]` 3-of-3 lock
