# S4 — Lifecycle + Entropy Spec (Fizzy actions → bd argv via CommandClient)

**Status**: v1 ready for peer review
**Bead**: `fizzy-858` (epic)
**Drafter**: `fizzy-codex`
**Reviewers**: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/s4-brief.md`

This spec turns the P6 lifecycle-adapter doctrine into implementation-ready perfect beads:
- Every lifecycle action uses `Fizzy::Beads::CommandClient` (S3) and emits a concrete `bd` argv.
- Beads is the source of truth for status + close + defer_until; Fizzy MySQL mirrors via poller.
- Entropy becomes a system-actor recurring job that updates Beads `defer_until`.

Constraints (non-negotiable):
- No direct Beads SQL writes from Rails (P3).
- No ENV-based actor; only `bd --actor <email>` argv (P5/S3).
- Board/column projection must stay consistent with S2 §B.2 status mapping.

---

## §A — Lifecycle action → CLI argv table (canonical)

This table is the implementation source of truth for which `bd update` flags + status values correspond to Fizzy lifecycle operations.

### A.1 Canonical Beads status set

Baseline Beads statuses in V1 UI projection (P4/S2):
- `open`
- `in_progress`
- `blocked`
- `deferred`
- `closed`

Additional statuses:
- `pinned` may exist as a special status and must be treated as overlay (S2 §B.2 / §E)
- custom statuses may exist and are categorized by Beads `custom_statuses(category)`; V1 maps them via projection (S2 §B.2)

### A.2 Actions

Primary rule: prefer explicit `bd` subcommands that emit dedicated events (`bd close`, `bd reopen`, `bd defer`, `bd undefer`) over a raw `bd update --status ...` when both exist.

| Fizzy lifecycle action | Beads write (CommandClient) | Canonical `bd` argv | Notes |
|---|---|---|---|
| Close card | `close_issue(id, reason: ...)` | `bd close <id> [--reason <text>]` | Use `bd close` (not `bd update --status closed`) so audit semantics stay explicit. |
| Reopen card | `reopen_issue(id, reason: nil, restore_status: nil)` | `bd reopen <id> [--reason <text>]` then optionally `bd update <id> --status <restore_status>` | `bd reopen` sets status to `open` and clears `closed_at` (per `bd reopen --help`). If we restore a non-open prior status, do it as a second write. |
| Start work | `update_status(id, "in_progress")` | `bd update <id> --status in_progress` | Column move controller rewires (see §E) |
| Mark blocked | `update_status(id, "blocked")` | `bd update <id> --status blocked` | |
| Postpone (Not now) | `defer_issue(id)` | `bd defer <id>` | Replaces upstream `not_now` / `card_not_nows` (P6 §C). |
| Resume from deferred | `undefer_issue(id, restore_status: nil)` | `bd undefer <id>` then optionally `bd update <id> --status <restore_status>` | `bd undefer` restores to `open` and clears `defer_until` (verified via probe in §D.4). If we restore a non-open prior status, do it as a second write. |
| Defer until timestamp | `defer_until(id, ts)` | `bd defer <id> --until=<ts>` | Verified `bd defer --until=<RFC3339>` accepts ISO8601 and sets `defer_until` (probe in §D.4). |
| Clear defer_until | `undefer_issue(id)` | `bd undefer <id>` | Prefer explicit subcommand; do not rely on `bd update --defer ""` unless batching. |

Secondary / batch-capable alternative (allowed, but default to subcommands above): `bd update <id> --defer <ts>` also works and accepts ISO8601; it sets status to `deferred` as part of the update (probe in §D.4). Use only when we explicitly want “single update call” semantics.

---

## §B — CommandClient lifecycle method enumeration (public API)

S3 locks the dispatch primitive and constructor shape. S4 enumerates the lifecycle-facing public methods that controllers/jobs call.

### B.1 Required public methods

At minimum V1 requires:

```ruby
# status transitions (direct)
update_status(id, status)

# close/reopen (explicit subcommands + optional restoration)
close_issue(id, reason: nil)
reopen_issue(id, reason: nil, restore_status: nil)

# defer/undefer (explicit subcommands + optional restoration)
defer_issue(id, until: nil)
undefer_issue(id, restore_status: nil)

# compatibility: batch form for defer_until (when we explicitly want bd update semantics)
update_defer_until(id, until:)

# helpers for reopen semantics
read_issue(id) # optional; if we need prior_status from metadata
```

### B.2 Error semantics

- All methods call `invoke!([subcommand, ...])` and raise `CommandError` on non-zero exit.
- Methods must be side-effecting; no retry inside CommandClient (retry belongs in job retry policy).

### B.3 Actor semantics

All call sites use `CommandClient.current` (web request/job with restored actor) OR `CommandClient.for(SystemActor.identity)` (rare; prefer `Current.with` block + `.current`).

### B.4 Custom statuses and “category preservation” (Gemini prior #1)

Lifecycle methods MUST accept any status string (including custom status names) and pass it through to `bd update --status <status>`. Column routing depends on Beads `custom_statuses(category)` (done/frozen/unspecified) being mirrored into MySQL (S9). S4 does not define custom-status creation, but it must not prevent setting a custom status by name.

---

## §C — Closure model deprecation (Beads is SoT)

P6 doctrine: closures table must not be a source of truth.

### C.1 What becomes canonical

Canonical closed signal and attribution come from Beads:
- `issues.status='closed'`
- `issues.closed_at` (if present)
- events audit trail (actor + timestamp) (P6)

### C.2 What stays in Fizzy (if anything)

V1 posture:
- `closures` table may survive temporarily as a *mirror cache* to keep existing UI code running, but must be treated as derived and disposable.
- Any remaining closure metadata in MySQL should be recomputable from Beads events.

S4 will produce beads for:
- stopping writes to `closures` as source-of-truth
- reading closure state from `cards.beads_status` + mirrored closed_at
- removing closure-dependent UX that cannot be mirrored yet (if needed)

### C.3 Explicit read path (Gemini prior #2)

The fork’s UI cannot join into Beads at request time (P3/P9). Therefore closure display and filtering MUST read from the MySQL Card mirror.

Required MySQL mirror fields (projected from Beads by the S9 poller):
- `cards.beads_status` (already planned in S1 bead `fizzy-m6r`)
- `cards.closed_at` (new; mirrors Beads `issues.closed_at`)
- `cards.defer_until` (new; mirrors Beads `issues.defer_until`)
- optionally `cards.close_reason` (new; mirrors Beads `issues.close_reason`) if we want “why closed” in UI without re-parsing events
- optionally `cards.closed_by_actor` (new; derived from Beads event actor, if/when we mirror events; otherwise omit in V1)

Until these fields exist, any remaining uses of `Closure` are transitional-only and must be treated as derived cache, not authoritative.

### C.4 Concrete upstream code surfaces that must be rewired (owned by I-S4 beads)

Read surfaces (today) that currently treat `closures` as truth:
- `app/models/card/closeable.rb` scopes: `closed`, `open`, `recently_closed_first`, `closed_at_window`, `closed_by`
- `Card#closed_at`, `Card#closed_by`, `Card#closed?`
- any views/partials that show closure metadata

Write surfaces (today) that create/destroy `Closure` rows:
- `Card#close` / `Card#reopen` (`app/models/card/closeable.rb`)
- `Cards::ClosuresController#create/destroy` (`app/controllers/cards/closures_controller.rb`)

I-S4 must rewire close/reopen to use the Beads CLI via CommandClient and to read closure state from mirrored Beads fields (C.3).

---

## §D — Entropy implementation (system actor + defer_until)

Entropy (auto-postpone) becomes Beads defer-until.

### D.1 Inputs (Fizzy-side config)

Config remains Fizzy-side (P6):
- account default entropy window (Account::Entropy)
- board override window (Board::Entropy)

### D.2 Output (Beads write)

For each eligible card, set:
- status to `deferred` (implicit when using `bd defer`), and
- `defer_until` to a computed timestamp

Exact behavior must match upstream semantics as closely as feasible without resurrecting not_now.

**V1 decision (matches P6 posture “entropy → defer_until”)**: for an auto-postponed card, set:
- `status='deferred'`, and
- `defer_until = Time.current + auto_postpone_period` (board override or account default).

This gives a deterministic “snooze window” for CLI readiness (`bd ready` hides deferred until `defer_until`), while the Fizzy UI continues to show deferred cards in the Not now column regardless of `defer_until`.

### D.3 Job actor discipline

Entropy job MUST run in:

```ruby
Current.with(actor: SystemActor.email) do
  ... CommandClient.current ...
end
```

This is non-negotiable to prevent actor leak across jobs (S3 v2 §D.3).

### D.4 CLI argv verification (required in this round)

We must verify the exact Beads CLI surface for defer/undefer and timestamp formats.

Required evidence to capture into this doc:
- output excerpt from `bd update --help` showing `--defer` and its “empty clears” semantics
- output excerpt from `bd defer --help` showing `--until`
- a local probe confirming RFC3339/ISO8601 timestamps are accepted and round-trip back as `defer_until`

Evidence (captured during S4 drafting):

- `bd update --help` includes: `--defer string  Defer until date (empty to clear).`
- `bd defer --help` includes: `--until string  Defer until specific time (e.g., +1h, tomorrow, next monday)`
- Probe: `bd defer <id> --until=2026-04-18T03:43:56Z` resulted in `status='deferred'` and `defer_until='2026-04-18T03:43:56Z'`.
- Probe: `bd undefer <id>` cleared `defer_until` and set `status='open'`.

---

## §E — Triage / in-progress controllers → status writes

Upstream writes `cards.column_id` and uses triageable/column placement.

Fork posture (S2/P6):
- Column placement is derived from `cards.beads_status`.
- Any “move to column” UI operation becomes `bd update <id> --status <mapped_status>`.

This spec does not decide the mapping from arbitrary custom columns to statuses (that’s S2 §B.3 and potentially a board-config spec), but it does require:
- `Cards::ColumnsController` (or equivalent) calls CommandClient lifecycle methods instead of updating AR.

Concrete upstream surfaces that must be rewritten in I-S4:
- `Card::Triageable#triage_into` / `#send_back_to_triage` (`app/models/card/triageable.rb`) — stop writing `column_id`; translate to `update_status` using the column’s `beads_status` mapping (`columns.beads_status`, authored in S2 bead `fizzy-eq4.1`).
  - `send_back_to_triage` becomes “reset to Todo”: `update_status(id, "open")` unless board config dictates otherwise.
  - keep the existing “column must belong to board” constraint, but it becomes a projection-metadata constraint, not a FK constraint.
- `Cards::ColumnsController` UI endpoints (`app/controllers/cards/columns_controller.rb`) — column selection becomes status update, not FK update.
- `BoardsController#show_columns` currently uses `awaiting_triage` (missing column); this becomes status-based (S2 already owns board show rewrite; S4 just ensures we don’t reintroduce `column_id` as lifecycle truth).

Postpone / Not now surfaces (also lifecycle-affecting):
- `Card::Postponable#postpone` (`app/models/card/postponable.rb`) — replace the transaction that creates `Card::NotNow` + reopens + destroys activity_spike with a Beads `bd defer` write (and potentially a status reset to `open` first if we retain “send back to triage” semantics).
  - V1 posture: keep board membership, set `status='deferred'`, set `defer_until` only for entropy (manual postpone uses no `--until` by default).
- `Cards::NotNowsController#create` (`app/controllers/cards/not_nows_controller.rb`) and `Columns::Cards::Drops::NotNowsController#create` (`app/controllers/columns/cards/drops/not_nows_controller.rb`) — call the CommandClient defer methods, not `@card.postpone`.

---

## §F — Reopen semantics (restore prior status)

P6 posture: reopen restores prior status via metadata.

### F.1 Required behavior

When transitioning from closed → reopened:
- If prior status is recorded: restore it.
- Otherwise: default to `open`.

### F.2 Where prior status lives

We will store prior status in Beads issue metadata on close/reopen and defer/undefer transitions.

**Key schema (locked by S4):**
- `metadata.fizzy.prior_status` — status string to restore on reopen/undefer
  - written immediately before `bd close` / `bd defer`
  - read on reopen/undefer to optionally apply `bd update --status <restore_status>` after the explicit subcommand
  - if missing or empty: restore to `open`

S4 does not define how metadata is mirrored into MySQL (S9), only how it is written and consumed by lifecycle transitions.

---

## §G — Test strategy

Minimum tests required in I-S4:
- Unit tests for lifecycle CommandClient methods (argv + error handling).
- Controller integration tests for status transitions (move-to-column, close/reopen).
- Job tests for entropy auto-postpone calling the correct argv with system actor.

---

## §H — Open questions (deferred)

- Bulk lifecycle actions (V2+).
- Events feed UI consequences (S8).
- Search freshness/read-after-write UX (S9 owns poller; S4 assumes eventual consistency).

---

## §I — Child bead inventory

Child beads (I-S4 implementation tasks) are minted under epic `fizzy-858`.

Cross-spec placeholders:
- `fizzy-1iz` — S9 lock placeholder for projecting Beads lifecycle fields into MySQL Card mirror (no cross-DB joins).

| F.N | Bead | Title | Satisfies | Key dependencies |
|---|---|---|---|---|
| F.1 | `fizzy-858.1` | Add lifecycle methods to CommandClient | §A, §B | `fizzy-5jt`, `fizzy-r4v` |
| F.2 | `fizzy-858.2` | Add Card mirror lifecycle columns | §C.3, §D.2 | `fizzy-05q`, `fizzy-m6r`, `fizzy-1iz` |
| F.3 | `fizzy-858.3` | Rewire close/reopen; deprecate Closure as truth | §C.4 | `fizzy-858.1`, `fizzy-858.2`, `fizzy-flu` |
| F.4 | `fizzy-858.4` | Rewire postpone (Not now) to defer/undefer | §A.2, §E | `fizzy-858.1` (and blocks `fizzy-0as`) |
| F.5 | `fizzy-858.5` | Rewire triage/column placement to status | §E | `fizzy-858.1`, `fizzy-eq4.1`, `fizzy-m6r` |
| F.6 | `fizzy-858.6` | Entropy auto-postpone uses bd defer --until | §D | `fizzy-858.1`, `fizzy-du0`, `fizzy-r4v` |
| F.7 | `fizzy-858.7` | Persist/restore metadata.fizzy.prior_status | §F | `fizzy-858.1` |
| F.8 | `fizzy-858.8` | Unit tests for lifecycle CommandClient methods | §G | `fizzy-858.1` |
| F.9 | `fizzy-858.9` | Integration tests for close/reopen/defer flows | §G | `fizzy-858.1`, `fizzy-858.3`, `fizzy-858.4`, `fizzy-858.5`, `fizzy-3ad` |
| F.10 | `fizzy-858.10` | Job tests for entropy defer_until + system actor | §G | `fizzy-858.1`, `fizzy-858.6`, `fizzy-1s3` |

---

## §J — Validation checklist

Pre-lock checklist for S4:
- [x] §A CLI argv table complete and defer/undefer/reopen/close flags verified from bd help + probe
- [x] §B CommandClient lifecycle method list complete and matches beads
- [x] §C closure SoT deprecation plan yields concrete implementation beads + explicit MySQL read path
- [x] §D entropy job spec includes actor discipline + canonical timestamp format (RFC3339) for `--until`
- [x] §E controller rewires enumerate concrete targets
- [x] §F reopen semantics key schema decided (metadata.fizzy.prior_status)
- [x] §I bead inventory table complete and deps wired (including cross-spec deps to S3/S1 and S9 placeholder)
- [ ] `[CODEX→CLAUDE S4 v1 ready]` sent + peer review complete
- [ ] `[FROM→TO S4: agreed]` 3-of-3 lock
