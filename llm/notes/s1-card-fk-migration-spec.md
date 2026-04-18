# S1 — Card id + FK Migration Spec

**Status**: drafting (S1 round in flight)
**Bead**: `fizzy-669` (epic)
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/s1-brief.md`

This spec defines the per-table migration sequence for converting Fizzy FK columns from `uuid` to `varchar(255)` to accommodate Beads issue ids (`fizzy-<suffix>` format), plus adding `cards.beads_status` per P9. Output is a parent epic bead + child task perfect-beads + this design doc.

This is the first Spec round; it sets the precedent for spec-bead authoring + dependency wiring.

---

## §A — Migration approach + ordering + safety strategy

### A.1 Approach

Per P3 §E (M-a widen-all): every Fizzy table that references `cards.id` or polymorphically to `Card` gets its FK column type changed from `uuid` to `varchar(255)`. No backfill is needed because per P3 §E.1 V1 is hard-fork fresh-installs; existing Fizzy data is disposable.

`cards.id` itself ALSO becomes `varchar(255)` so Card mirror rows can use Beads issue ids directly (per P9 §A.2 Card-as-mirror doctrine).

### A.2 Ordering principle

Migrations run in this dependency order to preserve FK integrity:

1. **Add `cards.beads_status` column** (additive — no FK change; safe first step)
2. **Drop FK constraints** from all child tables that reference `cards.id` (we're about to widen the parent's PK type)
3. **Widen child FK columns** to `varchar(255)` (data lost is OK per A.1)
4. **Widen `cards.id` PK** to `varchar(255)` (then drop+recreate any indexes that depend on the column type)
5. **Re-add FK constraints** with the new column types
6. **Verify** schema integrity

Each step is its own perfect-bead and depends on the prior via `bd dep add ... --type blocks`.

### A.3 Safety

- No backfill needed (V1 fresh installs only) → eliminates the highest-risk class of bugs.
- Each migration is reversible via paired `down` migration files (see §D rollback).
- `bin/ci` must pass after each step.
- The implementation round (I-S1) MUST run on a clean install (or `bin/rails db:reset` first) to avoid data drift; document this in each child bead.

---

## §B — Per-table migration plan

Every Fizzy table that needs an FK type change. Sourced from P1 §A (entity inventory) cross-referenced with `db/schema.rb`.

### B.1 Direct-FK tables (one-per-table beads)

> **v2 corrections per Codex S1 review**: closures + taggings KEPT (not dropped) per P9 mirror doctrine. comments.id NOT widened (S6 territory; only card_id widens). search_records widens BOTH card_id AND searchable_id.

| # | Table | FK column | Type change | Beads-side fact mirrored | Child bead |
|---|---|---|---|---|---|
| 1 | `closures` | `card_id` | uuid → varchar(255) | Mirror of close events; poller writes via `Closure.upsert_all` per P9 §C.2 | `fizzy-flu` (F.5, repurposed v2) |
| 2 | `card_not_nows` | (table dropped) | drop_table | NotNow becomes `status='deferred'` per P6 §C; no Fizzy table needed | `fizzy-0as` (F.4 drop) |
| 3 | `card_goldnesses` | (table dropped) | drop_table | Goldness rendered from `priority=0` per P4 §G; no Fizzy table needed | `fizzy-7ka` (F.2 drop) |
| 4 | `card_activity_spikes` | (table dropped) | drop_table | Stalled computed from `issues.updated_at` per P6 §F | `fizzy-ml5` (F.3 drop) |
| 5 | `assignments` | `card_id` | uuid → varchar(255) | Multi-assign sidecar; primary mirrored to beads `assignee` per P7 §A.2 | `fizzy-h6i` (F.8) |
| 6 | `taggings` | `card_id` | uuid → varchar(255) | Fizzy-side join for Filter/Search per P9 §B.2 (kept, not dropped) | `fizzy-k48` (F.6, repurposed v2) |
| 7 | `comments` | `card_id` only (NOT id) | uuid → varchar(255) | Comments mirrored from beads `comments` per P9 §C.2; id-mirroring is S6 spec round | `fizzy-0b8` (F.9) |
| 8 | `steps` | `card_id` | uuid → varchar(255) | Fizzy-only (Q-S-020 deferred decision; widen for now) | `fizzy-daf` (F.10) |
| 9 | `pins` | `card_id` | uuid → varchar(255) | Fizzy-only | `fizzy-4wm` (F.11) |
| 10 | `watches` | `card_id` | uuid → varchar(255) | Fizzy-only | `fizzy-it5` (F.12) |
| 11 | `notifications` | `card_id` | uuid → varchar(255) | Fizzy-only | `fizzy-2ae` (F.13) |
| 12 | `cards` | `id` (PK) | uuid → varchar(255) | Card mirror id = beads issue id | `fizzy-05q` (F.20) |
| 13 | `cards` | (NEW) `beads_status` | (add) varchar(32) | mirror beads `issues.status` per P9 §A.2 | `fizzy-m6r` (F.1) |

### B.2 Polymorphic-FK tables (special handling)

These tables use polymorphic associations where `record_id` (or similar) carries an id for any of multiple types. We widen these unconditionally to varchar(255); rows pointing at Card use Beads issue ids; rows pointing at non-Card models still use UUIDs (which fit in varchar(255)).

| # | Table | Polymorphic column | Other type column | Type change | Beads scope | Child bead |
|---|---|---|---|---|---|---|
| 15 | `events` | `eventable_id` | `eventable_type` | uuid → varchar(255) | Card events mirrored from beads (P8 / P9) | TBD |
| 16 | `mentions` | `source_id` | `source_type` | uuid → varchar(255) | Card mentions Fizzy-only (P1 §C.5) | TBD |
| 17 | `reactions` | `reactable_id` | `reactable_type` | uuid → varchar(255) | Card reactions Fizzy-only (P1 §C.5) | TBD |
| 18 | `notifications` | `source_id` | `source_type` | uuid → varchar(255) | Notifications Fizzy-only (P1 §C.6) | TBD |
| 19 | `action_text_rich_texts` | `record_id` | `record_type` | uuid → varchar(255) | Card.description rich text (Q-S-012) | TBD |
| 20 | `active_storage_attachments` | `record_id` | `record_type` | uuid → varchar(255) | Card.image (Q-S-025 covers attachments more deeply in S7) | TBD |
| 21 | `search_records_*` (16 shards) | `searchable_id` AND `card_id` | `searchable_type` | uuid → varchar(255) for BOTH | Card + Comment indexed (P9 §C) | `fizzy-n9l` (F.19, v2 fixed) |
| 22 | `storage_entries` | `recordable_id` | `recordable_type` | uuid → varchar(255) | Storage audit polymorphic to Card per P1 §A.9 (Gemini S1 catch) | `fizzy-0ic` (F.18b, added v2) |

### B.3 Tables NOT affected

- `accounts`, `users`, `identities`, `boards`, `columns`, `tags`, `entropies`, `webhooks` — these don't have a card FK
- Solid Queue tables — infrastructure, not affected
- Filter join tables (`assignees_filters`, etc.) — they join Filter to other models, not to Card

### B.4 "Drop in fork" candidates (v2 — corrected per Codex S1 review)

Some tables are flagged in P-rounds as Fizzy-only or drop-in-fork. v1 of this doc proposed dropping closures + taggings; Codex's S1 review caught that P9 explicitly relies on both as Fizzy-side mirrors. v2 corrected:

- `card_goldnesses` → **DROP** per P4 §G (goldness rendered from `priority=0`).
- `card_activity_spikes` → **DROP** per P6 §F (stalled computed from `issues.updated_at`).
- `card_not_nows` → **DROP** per P6 §C (postpone is Beads `status='deferred'`; audit via Beads `events.actor`).
- `closures` → **KEEP + WIDEN** per P9 §C.2 (poller writes `Closure.upsert_all` on Beads close events; closer attribution mirrored from `events.actor`). Earlier P6 §B suggested dropping; P9 doctrine supersedes for V1.
- `taggings` → **KEEP + WIDEN** per P9 §B.2 (Filter/Search use Fizzy-side `taggings` joins because cross-DB joins are impossible; Beads labels remain canonical, mirrored into taggings by the poller). Earlier P7 §B.2 suggested dropping; P9 doctrine supersedes for V1.
- `steps` → **KEEP + WIDEN** for V1 (Q-S-020 deferred decision; UI may hide).

### B.5 `taggings` decision (v2 corrected)

v2: KEEP + WIDEN per §B.4. P7 §B.2 originally said "drop taggings"; P9 §B.2 came later and explicitly relies on it for Filter/Search Fizzy-side joins. Where docs conflict, P9 wins because it's the more recent + Codex-confirmed correctness call.

---

## §C — Polymorphic column handling

### C.1 The constraint

Polymorphic AR columns (`record_id` paired with `record_type`) hold ids for ANY referenced model. In our case Card is one of the types but not the only one. So we cannot type-narrow the column to "varchar referencing cards".

### C.2 Approach

- Widen the polymorphic id column to `varchar(255)` (same width that fits both UUIDs for non-Card records and Beads ids for Card records).
- Add NO FK constraint at the DB level (polymorphic columns can't have FKs). Application-level integrity stays as-is.
- The `*_type` column is unchanged.

### C.3 Per-Card-type subset

Where a polymorphic table is being used ONLY for Card (e.g., reactions are Card-only or Comment-only), we could partition the column. But this introduces complexity without a migration benefit. Pass for V1; spec round S2 may revisit if needed.

---

## §D — Rollback strategy

Each migration file has a paired `down` method that reverses the column type change. Order is reverse:

1. Drop FK constraints
2. Narrow child columns from varchar(255) back to uuid (will fail if any row holds a Beads-format string — that's OK; rollback is for "we didn't deploy this yet" scenarios)
3. Narrow `cards.id` PK back to uuid
4. Re-add FK constraints
5. Drop `cards.beads_status`

For dropped tables (`closures`, `card_not_nows`, `card_goldnesses`, `card_activity_spikes`, `taggings`): the `down` recreates them (with original schema) but data is lost on rollback; document.

The rollback script is part of the spec; the implementation round produces the actual `db/migrate/...rb` files.

---

## §E — Verification tests

Each child bead's AC includes:

1. `bin/rails db:migrate` succeeds (forward)
2. `bin/rails db:rollback` succeeds for that step
3. `bin/rails db:migrate` succeeds again (re-apply)
4. The schema diff in `db/schema.rb` matches expected output (committed alongside migration)
5. Existing tests pass (`bin/rails test` for unit/integration; `bin/rails test:system` for system) — for a fresh-install scenario, expect zero data; tests that rely on fixtures may need fixture updates (separate spec round S-fixtures-update).

---

## §F — `cards.beads_status` column addition

Per P9 §A.2 disambiguation: keep `cards.status` enum `{drafted, published}` unchanged; add a new `cards.beads_status` `varchar(32)` column to mirror Beads `issues.status` set (`open`/`in_progress`/`blocked`/`deferred`/`closed` + custom).

```ruby
class AddBeadsStatusToCards < ActiveRecord::Migration[8.2]
  def change
    add_column :cards, :beads_status, :string, limit: 32
    add_index  :cards, :beads_status
  end
end
```

This is its own child bead, runs FIRST (before any FK changes; it's purely additive).

---

## §G — Dry-run procedure

Before the implementation round (I-S1) runs migrations against a real DB:

1. Run all migrations against a fresh sqlite/mysql DB (`bin/rails db:reset`)
2. Diff `db/schema.rb` before/after
3. Verify zero AR errors at boot (`bin/rails console -e test` then exit)
4. Run `bin/rails test` and `bin/rails test:system` (with `PARALLEL_WORKERS=1`)
5. Hit dev server (`bin/dev` then `curl -I http://app.fizzy.localhost:3006/`)
6. Document every step's output in the implementation round signoff

---

## §H — Child task beads inventory

The following child task beads will be created via `bd create` and wired with `bd dep add <child> fizzy-669 --type parent-child`. Each follows the perfect-bead structure (RoE-4 §5). Child-to-child `--type blocks` deps preserve the order from §A.2.

(Beads will be created in a follow-up commit; this section will be populated with `fizzy-XXX` ids once minted.)

| Step | Title | Type | Priority | Depends on |
|---|---|---|---|---|
| F.1 | Add cards.beads_status column | task | 1 | (none) |
| F.2 | Drop card_goldnesses table | task | 1 | F.1 |
| F.3 | Drop card_activity_spikes table | task | 1 | F.1 |
| F.4 | Drop card_not_nows table | task | 1 | F.1 |
| F.5 | Drop closures table | task | 1 | F.1 |
| F.6 | Drop taggings table | task | 1 | F.1 |
| F.7 | Drop FK constraints from remaining child tables | task | 1 | F.2-F.6 |
| F.8 | Widen FK columns: assignments.card_id | task | 1 | F.7 |
| F.9 | Widen FK columns: comments.card_id + comments.id | task | 1 | F.7 |
| F.10 | Widen FK columns: steps.card_id | task | 1 | F.7 |
| F.11 | Widen FK columns: pins.card_id | task | 1 | F.7 |
| F.12 | Widen FK columns: watches.card_id | task | 1 | F.7 |
| F.13 | Widen FK columns: notifications.card_id + source_id | task | 1 | F.7 |
| F.14 | Widen polymorphic: events.eventable_id | task | 1 | F.7 |
| F.15 | Widen polymorphic: mentions.source_id | task | 1 | F.7 |
| F.16 | Widen polymorphic: reactions.reactable_id | task | 1 | F.7 |
| F.17 | Widen polymorphic: action_text_rich_texts.record_id | task | 1 | F.7 |
| F.18 | Widen polymorphic: active_storage_attachments.record_id | task | 1 | F.7 |
| F.19 | Widen polymorphic: search_records_* (16 shards) | task | 1 | F.7 |
| F.20 | Widen cards.id PK | task | 1 | F.8-F.19 |
| F.21 | Re-add FK constraints | task | 1 | F.20 |
| F.22 | Schema verification + rollback test (full forward+down+forward) | task | 1 | F.21 |

22 child beads total. The actual `bd create` calls happen in §I.

---

## §I — Bead minting (executed during S1)

All 22 child beads minted; 58 dependencies wired (22 parent-child to `fizzy-669` + 36 blocks per §A.2 ordering).

| Step | Bead id | Title |
|---|---|---|
| F.1 | `fizzy-m6r` | Add cards.beads_status column |
| F.2 | `fizzy-7ka` | Drop card_goldnesses table |
| F.3 | `fizzy-ml5` | Drop card_activity_spikes table |
| F.4 | `fizzy-0as` | Drop card_not_nows table |
| F.5 | `fizzy-flu` | Drop closures table |
| F.6 | `fizzy-k48` | Drop taggings table |
| F.7 | `fizzy-x2i` | Drop FK constraints from remaining child tables |
| F.8 | `fizzy-h6i` | Widen assignments.card_id |
| F.9 | `fizzy-0b8` | Widen comments.card_id + comments.id |
| F.10 | `fizzy-daf` | Widen steps.card_id |
| F.11 | `fizzy-4wm` | Widen pins.card_id |
| F.12 | `fizzy-it5` | Widen watches.card_id |
| F.13 | `fizzy-2ae` | Widen notifications.card_id + source_id |
| F.14 | `fizzy-rpt` | Widen events.eventable_id (polymorphic) |
| F.15 | `fizzy-33r` | Widen mentions.source_id (polymorphic) |
| F.16 | `fizzy-hrf` | Widen reactions.reactable_id (polymorphic) |
| F.17 | `fizzy-jzw` | Widen action_text_rich_texts.record_id (polymorphic) |
| F.18 | `fizzy-cjs` | Widen active_storage_attachments.record_id (polymorphic) |
| F.19 | `fizzy-n9l` | Widen search_records_0..15 searchable_id (16 shards) |
| F.20 | `fizzy-05q` | Widen cards.id PK (keystone) |
| F.21 | `fizzy-i2m` | Re-add FK constraints |
| F.22 | `fizzy-iwk` | Schema verification + rollback test |

Verification commands:

```
bd show fizzy-669       # see epic with all 22 children
bd ready                # F.1 (fizzy-m6r) is the only currently-unblocked work
bd graph fizzy-669      # render dependency DAG
```

---

## §J — Resolved Q-S items

- **Q-S-002a — UUID→string FK migration cost** → ANSWERED. M-a widen-all approach formalized as 22 child beads; ordered; safety + rollback documented. See §A-§H.
- **Q-S-011** — already merged with Q-S-002a in P3 §E; this S1 round formalizes the implementation steps.

---

## §K — Open questions for downstream rounds

> **Q-S-S1-001 — Should `comments.id` mirror Beads `comments.id` directly, or use a separate Fizzy id with a beads_comment_id column?**
> §B.1 row 8 picks the former (mirror id directly) for consistency with Card. Spec round S6 (Rich text + comments) may revisit if it complicates rich-text storage.

> **Q-S-S1-002 — Do we keep `closures` for any reason (e.g., Fizzy-only audit not in Beads events)?**
> §B.4 picks "drop"; if a downstream UX requirement surfaces a need (e.g., "close reason field" beyond what Beads supports), reopen.

---

## §L — Validation checklist (pre-lock)

- [ ] §A-§G drafted with concrete migrations
- [ ] §B enumerates every affected table from P1 §A FK list (cross-checked)
- [ ] §C polymorphic handling explicit
- [ ] §D rollback documented
- [ ] §E verification tests defined
- [ ] §F beads_status column migration sketched
- [ ] §H child bead inventory listed (22 steps)
- [ ] §I child beads minted via `bd create` (22 actual fizzy-XXX ids)
- [ ] All child beads `parent-child` to fizzy-669; `blocks` deps wired per §A.2 ordering
- [ ] Ratified 3-of-3 by `[S1: agreed]`

---

## Convergence signal (S1)

3-of-3 lock: `[FROM→TO S1: agreed]` from all three agents.

After lock: parent epic `fizzy-669` stays OPEN (closes when child impl beads close in I-S1). LOG handoff: "S1 locked; opens S2 — Board/Column/Access projection spec (P4 → impl beads)."
