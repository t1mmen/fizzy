# S4 — Lifecycle + Entropy Spec (Fizzy actions → bd argv via CommandClient)

**Status**: drafting (commit-at-first-write)
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

| Fizzy lifecycle action | Beads write (CommandClient) | Canonical `bd` argv | Notes |
|---|---|---|---|
| Close card | `close_issue(id, reason: ...)` | `bd update <id> --status closed [--notes ...]` | Close reason captured in metadata or notes (see §C) |
| Reopen card | `reopen_issue(id)` | `bd reopen <id>` OR `bd update <id> --status <prior_or_open>` | Prefer `bd reopen` if it exists and preserves audit semantics; otherwise status update (see §F) |
| Start work | `update_status(id, "in_progress")` | `bd update <id> --status in_progress` | Column move controller rewires (see §E) |
| Mark blocked | `update_status(id, "blocked")` | `bd update <id> --status blocked` | |
| Postpone (Not now) | `update_status(id, "deferred")` | `bd update <id> --status deferred` | Replaces upstream not_now / card_not_nows (P6 §C) |
| Resume from deferred | `update_status(id, <prior_or_open>)` | `bd update <id> --status <prior_or_open>` | Restore prior status via metadata (P6 §G; §F) |
| Defer until timestamp | `defer_until(id, ts)` | `bd update <id> --defer <ts>` (exact flag TBD) | Used by entropy; exact bd flag verified in S4 (see §D.4) |
| Clear defer_until | `clear_defer_until(id)` | `bd update <id> --defer ""` (empty clears) | Align with bd update --help (empty clears defer) |

**Open question (must be resolved in this round):** exact `bd update` flag name for defer-until (`--defer` vs `--defer-until`). We treat this as part of §A completion and will verify against `bd update --help`.

---

## §B — CommandClient lifecycle method enumeration (public API)

S3 locks the dispatch primitive and constructor shape. S4 enumerates the lifecycle-facing public methods that controllers/jobs call.

### B.1 Required public methods

At minimum V1 requires:

```ruby
# status transitions
update_status(id, status)

# close/reopen
close_issue(id, reason: nil)
reopen_issue(id)

# defer_until / entropy
defer_until(id, time)
clear_defer_until(id)

# helpers for reopen semantics
read_issue(id) # optional; if we need prior_status from metadata
```

### B.2 Error semantics

- All methods call `invoke!([subcommand, ...])` and raise `CommandError` on non-zero exit.
- Methods must be side-effecting; no retry inside CommandClient (retry belongs in job retry policy).

### B.3 Actor semantics

All call sites use `CommandClient.current` (web request/job with restored actor) OR `CommandClient.for(SystemActor.identity)` (rare; prefer `Current.with` block + `.current`).

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

---

## §D — Entropy implementation (system actor + defer_until)

Entropy (auto-postpone) becomes Beads defer-until.

### D.1 Inputs (Fizzy-side config)

Config remains Fizzy-side (P6):
- account default entropy window (Account::Entropy)
- board override window (Board::Entropy)

### D.2 Output (Beads write)

For each eligible card, set:
- status to `deferred` (if needed) and/or
- `defer_until` to computed timestamp

Exact behavior must match upstream semantics as closely as feasible without resurrecting not_now.

### D.3 Job actor discipline

Entropy job MUST run in:

```ruby
Current.with(actor: SystemActor.email) do
  ... CommandClient.current ...
end
```

This is non-negotiable to prevent actor leak across jobs (S3 v2 §D.3).

### D.4 CLI argv verification (required in this round)

We must verify the exact `bd update` flag that sets `defer_until`.

Required evidence to capture into this doc:
- output excerpt from `bd update --help` showing the flag name and the “empty clears” semantics.

---

## §E — Triage / in-progress controllers → status writes

Upstream writes `cards.column_id` and uses triageable/column placement.

Fork posture (S2/P6):
- Column placement is derived from `cards.beads_status`.
- Any “move to column” UI operation becomes `bd update <id> --status <mapped_status>`.

This spec does not decide the mapping from arbitrary custom columns to statuses (that’s S2 §B.3 and potentially a board-config spec), but it does require:
- `Cards::ColumnsController` (or equivalent) calls CommandClient lifecycle methods instead of updating AR.

---

## §F — Reopen semantics (restore prior status)

P6 posture: reopen restores prior status via metadata.

### F.1 Required behavior

When transitioning from closed → reopened:
- If prior status is recorded: restore it.
- Otherwise: default to `open`.

### F.2 Where prior status lives

We will store prior status in Beads issue metadata on close/reopen transitions (exact key names defined in I-S4 beads; spec locks the key schema).

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

To be populated in v1 with:
- child beads under `fizzy-858`
- each bead maps to one atomic slice of §A–§G
- cross-spec deps to S3 and S1 keystones

---

## §J — Validation checklist

Pre-lock checklist for S4:
- [ ] §A CLI argv table complete and defer-until flag verified from bd help output
- [ ] §B CommandClient lifecycle method list complete and matches beads
- [ ] §C closure SoT deprecation plan yields concrete implementation beads
- [ ] §D entropy job spec includes actor discipline + argv for defer_until
- [ ] §E controller rewires enumerate concrete targets
- [ ] §F reopen semantics key schema decided
- [ ] §I bead inventory table complete and deps wired
- [ ] `[CODEX→CLAUDE S4 v1 ready]` sent + peer review complete
- [ ] `[FROM→TO S4: agreed]` 3-of-3 lock
