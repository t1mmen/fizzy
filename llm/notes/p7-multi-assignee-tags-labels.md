# P7 — Multi-Assignee + Tags/Labels Gap (Fizzy ↔ Beads)

**Status**: drafting (P7 round in flight)
**Bead**: `fizzy-47p`
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/p7-brief.md`

This decision doc closes Q-S-017 (Tag↔Beads label sync) and Q-S-018 (multi-assignee preservation). Builds on P3 (CommandClient writes), P4 (`fizzy/board/<uuid>` reserved label namespace), P5 (`bd --actor` on every write), P6 (lifecycle adapter + `Beads::IssueRepository` mutations).

---

## §A — Multi-assignee strategy (Q-S-018)

### A.1 Ground truth

**Fizzy** (`app/models/assignment.rb`): each `Assignment` row links one Card to one User (assignee) with a separate `assigner_id` for audit. `card.assignees` returns many users via `has_many :assignees, through: :assignments`. Validation caps at 100 assignees per card.

**Beads** (P1 §B `issues` schema): `assignee` is a single `varchar(255)` column. No native multi-assignee primitive.

This is a real cardinality gap: 1:N (Fizzy) vs 1:1 (Beads).

### A.2 Decision

**Adopt option (a) from P1 §E.5 — Fizzy retains an `assignments` sidecar table FK'd to `issues.id`; Beads `assignee` mirrors the "primary" assignee.**

Concretely:
- The `assignments` MySQL table survives the fork (FK column type changes from `card_id uuid` → `card_id varchar(255)` per P3 §E migration).
- "Primary assignee" = first `Assignment` row by `created_at` ASC (or explicitly designated; spec round S-assignee-primary picks the rule). The Fizzy adapter writes that primary's email to `bd update <id> --assignee <email>` whenever the primary changes.
- Other assignees are Fizzy-only — visible in UI, queryable, but invisible to `bd ready` / `bd query` over Beads alone.

### A.3 Rationale (vs (b) metadata.assignees + vs (c) lossy single)

| Strategy | Pro | Con |
|---|---|---|
| (a) **sidecar + primary mirror** (recommended) | Preserves Fizzy's many-assignee UX; fast SQL query for "my issues"; clean audit (assigner_id stays); doesn't pollute Beads metadata | Requires consistent FK type migration; "my issues" via `bd ready` only shows your primary-assigned issues |
| (b) `issues.metadata.assignees: [...]` JSON | Beads-side has full assignee list (visible to `bd query`) | Mutating JSON requires read-modify-write per assignment add/remove (atomicity headache); Beads `--assignee` flag still single, so write semantics are awkward; metadata becomes a queryable schema-without-schema |
| (c) Lossy single assignee | Simplest schema | Loses Fizzy feature parity; teams that actively use multi-assign break |

(a) wins on UX preservation + clean schema separation. The "primary mirror" caveat (`bd ready` only shows primary) is acceptable because Fizzy UI always shows the full list and is the primary surface.

### A.4 Reassignment semantics

When primary assignee changes (because the primary user was removed, or admin promoted a different assignee):
1. Fizzy writes the new primary to `assignments` (or marks the new primary).
2. Adapter calls `Beads::IssueRepository.set_assignee(issue_id, new_primary_email, actor:)`.
3. Repository invokes `bd --actor <writer_email> update <issue_id> --assignee <email>`. **Note**: `--actor` is a GLOBAL bd flag (per `bd --help`), placed BEFORE the subcommand, not after.
4. Beads `events.actor` records the writer (per P5).

When all assignees removed:
- Beads `assignee` cleared: `bd --actor <writer_email> update <id> --assignee ""`.

### A.5 "My issues" query semantics

- Fizzy UI "My Issues" SHOULD show the union of (issues where I'm any assignee, via Fizzy `assignments`) + (issues where Beads `assignee = my-email`, just to be safe). Dedupe.
- `bd ready` (CLI) only returns Beads `assignee = me`. CLI users see only their primary-assigned issues. That's expected, not a bug.

### A.6 Migration of existing data

Per P3 §E.1, V1 hard fork with no existing Fizzy data. Future v2 import (Q-S-007) decides whether to import existing assignments — recommend (I-b mapping table) preserves them all with primary = first chronologically.

---

## §B — Tag↔Label sync (Q-S-017)

### B.1 Ground truth

**Fizzy** (`app/models/tag.rb`): `Tag` is a normalized title string (lowercase, no leading `#`); unique per account. `Tagging` is the join. `Tag` survives fork (per P1 §C.4 mapping).

**Beads** (P1 §B `labels` schema): `labels(issue_id, label)` join table — labels are free strings per issue.

### B.2 Decision

**Adopt option (a) from P1 §E.6 — `Tag` is a Fizzy display object whose `title` IS the Beads label string. Tagging an issue adds the label to Beads `labels`; deleting a Fizzy Tag removes that label from every issue it touches.**

The Fizzy `Tag` table provides:
- Account-scoped uniqueness + normalization (lowercase, no leading `#`)
- Color/display metadata (Tag has `color` etc. — Fizzy-only attributes)
- A canonical list of "all tags in this install" for autocomplete / picker UI

The Fizzy `Tagging` table can be dropped in favor of reading from Beads `labels` directly, OR retained as a sidecar for Fizzy-only metadata (e.g., who tagged it, when). Recommendation: **drop `Tagging` for V1**; Beads `labels` is the source of truth for "which issues have which labels". Spec round S-tag-tagging confirms.

### B.3 Why not (b) drop Tag entirely

- Loses Tag normalization rules (lowercase, strip-leading-#) — without a Fizzy-side validation, users would create `#Foo`, `foo`, `FOO`, `Foo ` as separate Beads labels. Garbage.
- Loses tag display metadata (color, etc.) which is part of Fizzy UX.
- Tag picker autocomplete becomes a `SELECT DISTINCT label FROM labels` over potentially-large datasets vs a fast `Tag.all`.

### B.4 Sync mechanics

`bd` CLI flag verification (Codex empirically checked via `bd update --help` + `bd label --help` + `bd tag --help`):
- `bd update <id> --add-label <label>` — add a label
- `bd update <id> --remove-label <label>` — remove a label
- `bd update <id> --set-labels <l1,l2,...>` — replace whole label set
- Shorthands: `bd tag <id> <label>` and `bd label add <id> <label>` / `bd label remove <id> <label>`

**`--actor <email>` is a GLOBAL flag (placed before the subcommand)** per `bd --help`.

```
User adds tag "backend" to card X:
  1. Fizzy validates: "backend" (already lowercase, no leading #) — passes Tag.title rules
  2. Find or create Tag(title: "backend")
  3. Adapter: Beads::IssueRepository.add_label(card_x.beads_id, "backend", actor:)
  4. CommandClient: bd --actor <writer_email> update <issue_id> --add-label backend

User removes tag "backend" from card X:
  1. Adapter: Beads::IssueRepository.remove_label(card_x.beads_id, "backend", actor:)
  2. CommandClient: bd --actor <writer_email> update <issue_id> --remove-label backend

Admin deletes Tag "backend" entirely:
  1. Find every issue with this label via Beads SQL: SELECT issue_id FROM labels WHERE label = 'backend'
  2. For each: adapter removes the label.
  3. Delete the Fizzy Tag row.
```

### B.5 Read-side query patterns

- "Issues tagged X": `Beads::Issue.joins(:labels).where(labels: { label: 'X' })` (via the `Beads::Label` model from P3 §D).
- "All tags in this install": `Tag.all.order(:title)` (Fizzy-side, fast).
- "Most-used tags": `SELECT label, COUNT(*) FROM labels GROUP BY label ORDER BY 2 DESC` (Beads SQL).

---

## §C — Label namespace conflict prevention

P4 §A.5 reserved `fizzy/board/<board_uuid>` as the system board-membership label namespace. P7 must prevent user labels from colliding.

### C.1 Decision

**Forbid user-created labels matching the regex `^fizzy/`** at Fizzy validation time.

Specifically:
- `Tag.title` validation: reject titles starting with `fizzy/` (case-insensitive after lowercase normalization).
- Adapter never writes a label starting with `fizzy/` from user input.
- The system writes `fizzy/board/<uuid>` labels only via internal code paths (board membership transitions), not via the public Tag interface.

### C.2 Reserved system label prefixes (registry)

| Prefix | Owner | Purpose |
|---|---|---|
| `fizzy/board/<uuid>` | P4 | Board membership |
| `fizzy/system/` | reserved future | Internal system labels |
| `fizzy/test/` | reserved future | Test fixtures' temp labels |

Future P-rounds or spec rounds may add to this registry. Any new system label MUST use the `fizzy/` prefix.

### C.3 Migration safety

If existing Beads data (e.g., from a hard-fork starting state) contains labels that look like system labels but are user-data, the adapter must not silently treat them as system labels. Recommendation: a one-time migration scan at install setup that flags any non-conforming `fizzy/*` labels; Spec round S-label-migration owns it.

---

## §D — Tag normalization (apply to Beads writes)

### D.1 Ground truth

`Tag` model normalizes:
- Lowercase
- Strip leading `#`
- (Probably also strip whitespace — Spec round verifies the exact rules)

### D.2 Decision

**Apply the same Tag normalization rules to every Beads label write that flows through the Fizzy adapter.**

```ruby
# In Fizzy::Beads::CommandClient or helper:
def normalize_label(raw)
  raw.to_s.strip.downcase.sub(/\A#/, "")
end
```

Every `add_label` / `remove_label` call passes the normalized form. This prevents `#Foo` / `Foo` / `foo` from becoming three separate Beads labels.

### D.3 Why this is non-negotiable

Beads `labels` is a flat string column. There is no DB-level uniqueness or canonicalization. The only protection against label garbage is application-level normalization. Fizzy's existing rules apply unchanged; the adapter just enforces them on the boundary to bd.

### D.4 What about labels added via `bd` CLI directly (bypassing Fizzy)?

If a user runs `bd update <id> --add-label "#Backend"` directly, that label lands in Beads as-is. Fizzy will display it as-is on read (no auto-canonicalize on read).

Mitigation options (all deferred to v2+):
- (a) Periodic linter job that flags non-canonical labels.
- (b) Auto-rewrite on read (lossy if multiple variants exist).
- (c) Beads-side hook (would require beads schema change — out of scope).

For V1, document the convention and trust the team.

---

## §E — Adapter shape sketch

```ruby
# app/models/beads/issue_repository.rb (extends P3 sketch + P6 lifecycle methods)
module Beads
  class IssueRepository
    # ... existing P3/P6 methods ...

    # P7 additions:
    def self.set_assignee(id, email, actor:)
      # email may be nil/empty to clear
      # CommandClient: bd update <id> --assignee <email or ""> --actor <actor>
    end

    def self.add_label(id, label, actor:)
      normalized = Fizzy::Beads::LabelNormalizer.call(label)
      raise ArgumentError, "system label" if normalized.start_with?("fizzy/")
      # CommandClient: bd update <id> --add-label <normalized> --actor <actor>
    end

    def self.remove_label(id, label, actor:)
      normalized = Fizzy::Beads::LabelNormalizer.call(label)
      # CommandClient: bd update <id> --remove-label <normalized> --actor <actor>
    end

    def self._add_system_label(id, label, actor:)
      # Internal-only, used by board-membership and system code paths.
      # Bypasses the fizzy/-prefix guard but logs the call.
    end
  end
end

# app/models/assignment.rb (existing — sidecar table; add adapter callbacks)
class Assignment < ApplicationRecord
  belongs_to :card  # FK column changes uuid → varchar(255) per P3 §E
  belongs_to :assignee, class_name: "User"
  belongs_to :assigner, class_name: "User"

  after_create_commit :sync_primary_assignee_to_beads
  after_destroy_commit :sync_primary_assignee_to_beads

  private

  def sync_primary_assignee_to_beads
    primary = card.assignments.order(:created_at).first
    primary_email = primary&.assignee&.email_address  # via Identity
    Beads::IssueRepository.set_assignee(card.beads_id, primary_email, actor: ...)
  end
end

# lib/fizzy/beads/label_normalizer.rb
module Fizzy
  module Beads
    module LabelNormalizer
      def self.call(raw)
        raw.to_s.strip.downcase.sub(/\A#/, "")
      end
    end
  end
end
```

---

## §F — Resolved Q-S items (links back to P1)

- **Q-S-017 — How do Fizzy `Tag` records sync with Beads `labels`?** → ANSWERED. Tag is a Fizzy display object whose normalized `title` IS the Beads label string. Tagging adds label via CLI; deleting tag removes from every tagged issue. Tagging join table dropped in favor of Beads `labels` as source of truth. See §B.
- **Q-S-018 — Multi-assignee preservation?** → ANSWERED. Option (a) — Fizzy `assignments` sidecar (FK type changes per P3 §E migration); Beads `assignee` mirrors the chronologically-first primary; CLI users see only primary; Fizzy UI shows full list. See §A.

A subsequent edit to `p1-foundational-gap-inventory.md` will mark these ANSWERED with a backlink.

---

## §H — Open questions for downstream rounds

> **Q-S-051 — How is "primary assignee" defined when the chronologically-first assignment is removed?**
> §A.2 says "first by `created_at` ASC". If the original primary is removed, does the next-oldest become primary? Or does the system prompt the admin? Spec round S-assignee-primary owns this; recommendation: auto-promote next-oldest, but allow manual override.

> **Q-S-052 — Should the adapter rate-limit Beads writes for bulk-tag operations?**
> Bulk tagging (e.g., admin re-tags 1000 issues from "old-label" to "new-label") would invoke `bd` 1000 times. Each shell-out is ~100ms. That's a 100-second job. Spec round considers (a) bd batch flag (per P3 §C row 4), (b) job-queue wrapper, (c) acceptable as-is.

> **Q-S-053 — Spec the exact `bd update --add-label` / `--remove-label` flag names.**
> §B.4 sketches usage. Need empirical verification via `bd update --help` (Spec round S-label-cli).

---

## §I — Validation checklist (pre-lock)

- [ ] §A picks (a) sidecar + primary mirror; rationale vs (b)/(c) is concrete.
- [ ] §A.4 specifies reassignment semantics (re-mirror to beads, attribution via P5).
- [ ] §A.5 explains the asymmetry between Fizzy "My Issues" and `bd ready`.
- [ ] §B picks (a) Tag-as-display-object; reasoning vs (b) drop-Tag is concrete.
- [ ] §B.4 sync mechanics include: add, remove, admin-delete-tag.
- [ ] §C reserved namespace registry exists; user-label validator forbids `fizzy/` prefix.
- [ ] §D normalization rules (lowercase, strip leading `#`) are mandated for every Beads label write.
- [ ] §E adapter sketch is signature-only.
- [ ] §F marks Q-S-017/018 ANSWERED.
- [ ] §H surfaces 3 follow-up questions with clear ownership.

---

## Convergence signal (P7)

3-of-3 lock: `[FROM→TO P7: agreed]` from all three agents.

After lock + commit + close `fizzy-47p`, P8 (events two-way sync, brief at p8-brief.md to be drafted by Codex per alternation) opens.
