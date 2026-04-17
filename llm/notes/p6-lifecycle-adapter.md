# P6 — Lifecycle Adapter: status / closure / postpone / entropy (Fizzy → Beads)

**Status**: drafting (P6 round in flight)  
**Bead**: `fizzy-v4j`  
**Drafter**: `fizzy-codex`  
**Reviewers**: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)  
**Brief**: `llm/notes/p6-brief.md`  

This doc closes lifecycle questions from P1 §E.4 for V1:
Q-S-013, Q-S-014, Q-S-015, Q-S-016.

Constraint reminders:
- P3: **SQL reads (Trilogy) + CLI writes (`bd`)** (`llm/notes/p3-data-path-decision.md`).
- P4: **Board membership label + status→column mapping** (`llm/notes/p4-ui-projection-deep-dive.md`).
- P5: **Actor is explicit via `bd --actor <email>`** (`llm/notes/p5-auth-bridging.md`).

---

## §A — Status mapping table (Q-S-013)

### A.1 Ground truth: upstream Fizzy lifecycle is compositional

Upstream Fizzy represents lifecycle as multiple signals:
- `cards.status` enum (`drafted`/`published`) (`app/models/card/statuses.rb`)
- closure presence (`Closure` row exists) (`app/models/card/closeable.rb`, `app/models/closure.rb`)
- not-now presence (`Card::NotNow` row exists) (`app/models/card/postponable.rb`, `app/models/card/not_now.rb`)
- column presence (triaged vs awaiting triage) (`app/models/card/triageable.rb`)

In the fork, “Card” is a Beads issue. Beads has one canonical lifecycle signal:
- `issues.status` (string; default `'open'`) (P1 §B DDL)
…plus timestamps:
- `issues.closed_at`
- `issues.defer_until`
…plus audit:
- `events(actor, event_type, old_value, new_value, created_at, …)` (P1 §B DDL)

Therefore the fork should collapse multiple Fizzy-side lifecycle components into:
**Beads status + timestamps + Beads event attribution**.

### A.2 Decision: drop Fizzy drafted/published; represent “draft/inbox” as unlabeled issues

**Decision (V1): do not introduce a custom Beads status for drafts.**

Instead, treat “draft/untriaged” as:
- Beads issue exists, but has **no board-membership label** (`fizzy/board/*`).

And treat “published/on-board” as:
- Beads issue has **exactly one** `fizzy/board/<board_uuid>` label (P4 single-board invariant).

Rationale:
- Keeps all task data in Beads (CEO Q2), without inventing a draft status.
- Uses the already-required board-membership label mechanism (P4).
- Provides an “Inbox” list view naturally (P4 list view; keyboard/a11y anchor).

### A.3 Fork lifecycle mapping table (canonical)

This table maps *user-visible* lifecycle state to Beads canonical state.

| Fork state | Upstream Fizzy reference encoding | Beads canonical |
|---|---|---|
| Inbox (untriaged) | awaiting triage (`column_id` nil) and/or drafted | `issues.status in ('open','in_progress','blocked','deferred')` (unchanged) + **no `fizzy/board/*` label** |
| On-board: Todo | triaged into a column | `issues.status='open'` + `fizzy/board/<uuid>` |
| On-board: Doing | triaged into a column | `issues.status='in_progress'` + board label |
| On-board: Blocked | triaged into a column | `issues.status='blocked'` + board label |
| On-board: Not now | `not_now` row exists | `issues.status='deferred'` (+ optional `defer_until`) + board label |
| Done | `closure` row exists | `issues.status='closed'` + `issues.closed_at` set + close attribution from `events.actor` |

Notes:
- Pinned is treated as an overlay per P4. If Beads uses `status='pinned'`, we treat it as a separate overlay/section (Q-S-050).

---

## §B — Closure migration (Q-S-014)

### B.1 Ground truth: closure row is the close signal + attribution in upstream

Upstream:
- closed? = `closure.present?` (`app/models/card/closeable.rb`)
- close does:
  - destroys `not_now` if present
  - `create_closure!(user: user)`
  - tracks event `:closed`
- reopen destroys the closure row and tracks `:reopened`

### B.2 Decision: do not keep `closures` as a source-of-truth; read close attribution from Beads

**Decision (V1):**
- Close = Beads status transition (`issues.status='closed'`), performed via CLI with explicit actor (`bd --actor <email> ...`).
- Close attribution (“closed by” + “closed at”) is read from:
  - `issues.closed_at` (timestamp), and
  - Beads `events.actor` for the last close-related event.

Why this is correct:
- P5 ensures actor is explicitly passed on every `bd` invocation; Beads is now the audit source-of-truth.
- A Fizzy-side `closures` cache would add drift risk and duplicate the audit trail.

Spec/impl note:
- Beads `events.event_type` values must be inspected so we can query “closed-by actor” correctly (S-lifecycle-events).

---

## §C — NotNow → deferred (Q-S-015)

### C.1 Ground truth: upstream postpone is “open but excluded from active workflow”

Upstream:
- postponed = open + published + `not_now.present?` (`app/models/card/postponable.rb`)
- postpone does:
  - `send_back_to_triage(skip_event: true)` (clears `column_id`)
  - `reopen` (ensures open)
  - destroys `activity_spike`
  - creates `not_now(user: user)` unless already postponed
  - tracks event (`postponed` / `auto_postponed`)
- resume destroys `not_now` and `activity_spike`

### C.2 Decision: postpone/resume are Beads-native status transitions

**Decision (V1):**
- Postpone (manual): set `issues.status='deferred'`. `defer_until` is optional UI input.
- Resume: set `issues.status='open'` and clear `defer_until`.

Attribution:
- “postponed by” is read from Beads `events.actor` for the postpone-related event.

Why `defer_until` is optional for manual postpone:
- Some teams use “Not now” as “not currently in focus” without a date.
- When a date is chosen, it should be stored in Beads-native `defer_until` and drive both UI and `bd ready`.

---

## §D — Entropy → defer_until (Q-S-016)

### D.1 Ground truth: upstream entropy is a recurring sweep over active cards

Upstream:
- `Entropy` config is stored as rows on Account and Board containers (`app/models/entropy.rb`).
- `Card::Entropic.due_to_be_postponed` is computed from `last_active_at` and `auto_postpone_period` (board override, account fallback) (`app/models/card/entropic.rb`).
- `auto_postpone_all_due` iterates and calls `card.auto_postpone(user: card.account.system_user)`.

### D.2 Decision: keep entropy config Fizzy-side; apply to Beads via CLI writes setting `defer_until`

**Decision (V1):**
- Keep `Entropy` config in Fizzy DB (it is a projection/config).
- Implement the sweep as a recurring job that:
  1) Queries Beads issues in scope (board label present, status active).
  2) Computes “due to postpone” using a Beads-derived “last active”.
  3) Mutates Beads via CLI: set `status='deferred'` and set `defer_until = now + auto_postpone_period`.
  4) Uses the system identity via `bd --actor system@<install-hostname>` (P5 synthetic system Identity).

Why `defer_until = now + period` (not nil):
- Entropy’s purpose is to get items out of the active workflow but allow them to return automatically.
- `defer_until` is the Beads-native primitive for “comes back later” and hides from `bd ready` until then.

### D.3 Board vs account entropy resolution (unchanged)

Resolution rule remains:
- If the board has an entropy override: use it.
- Else: use account entropy default.

Mapping from issue → board is via the reserved `fizzy/board/<uuid>` label namespace (P4).

---

## §E — Goldness (confirm P4 disposition)

P4 closed Q-S-028: priority replaces goldness (`llm/notes/p4-ui-projection-deep-dive.md` §G).

**Decision (V1):**
- Drop `card_goldnesses` as a stored lifecycle component.
- If UI needs “golden”, render it as **derived from `issues.priority=0`** (display-only).

---

## §F — ActivitySpike (confirm v1 disposition)

Upstream `Card::ActivitySpike` exists to support “stalled” detection (`app/models/card/stallable.rb`), with:
- persisted `card_activity_spikes` row
- async detection job
- `stalled?` depending on last spike time and `updated_at`

**Decision (V1): drop the persisted ActivitySpike row and compute “stalled” from Beads timestamps.**

V1 computation (proposal):
- stalled if:
  - on-board and active (`status in ('open','in_progress','blocked')`)
  - `issues.updated_at` older than N days (default N=14 to match upstream)

If we need fidelity later:
- compute from Beads `events` (v2+), not a Fizzy-side write surface.

---

## §G — Reopen semantics

### G.1 Ground truth: upstream reopen only removes closure

Upstream `reopen` simply destroys closure and tracks event (`app/models/card/closeable.rb`). It does not explicitly restore a prior column.

### G.2 Decision: reopen is Beads-native; restore prior status via metadata (optional)

**Decision (V1):**
- Reopen = Beads status transition via CLI (`bd reopen <id>` or equivalent), with explicit `--actor`.
- Default reopened status is `open` (Todo column per P4).

Optional fidelity (recommended):
- On close, store `issues.metadata.fizzy.previous_status=<status>` if current status is not `open`.
- On reopen, restore to `previous_status` when safe; else fall back to `open`.

This maintains Fizzy-like simplicity while enabling “return to Doing” behavior when desired.

---

## §H — Lifecycle hook plumbing (sketch only)

**Decision (V1): lifecycle translation lives in the Beads adapter layer, not controllers.**

Sketch (no code in P6):
- `Beads::IssueRepository` owns lifecycle entrypoints:
  - `close(id, actor:)`
  - `reopen(id, actor:)`
  - `postpone(id, actor:, defer_until: nil)`
  - `resume(id, actor:)`
  - `auto_postpone_due!(system_actor:)` (recurring job)
- `Beads::Lifecycle` module provides mapping helpers (status sets, metadata keys, etc.).

All mutations go through `Fizzy::Beads::CommandClient` and always pass `--actor <email>` (P5).

---

## §I — Resolved Q-S items (links back to P1)

This doc answers and closes:

- **Q-S-013**: Drafted/published collapses to “inbox (no board label) vs on-board (exactly one board label)” and Beads status drives columns. (§A)
- **Q-S-014**: Closure becomes Beads `status='closed'`; closer attribution reads from Beads (`issues.closed_at` + `events.actor`). (§B)
- **Q-S-015**: NotNow becomes Beads `status='deferred'` (+ optional `defer_until`); resume clears. (§C)
- **Q-S-016**: Entropy becomes a recurring job that sets `status='deferred'` and `defer_until=now+period` via CLI using system actor; entropy config stays Fizzy-side. (§D)

---

## §J — Open questions for downstream rounds

> **Q-S-048 — What is the canonical “last active” signal for a Beads issue?**
> V1 proposal uses `issues.updated_at`. If comments/events should count as activity, we may need `MAX(events.created_at)` as last active. Impacts entropy and stalled detection.

> **Q-S-049 — What exact `bd` argv do we standardize on for lifecycle transitions?**
> `bd update --status …` vs `bd close` / `bd reopen` / `bd defer` / `bd undefer`. Spec round S-lifecycle-cli owns the exact command surface and error semantics.

> **Q-S-050 — How do we treat `status='pinned'`?**
> P4 uses pinned as overlay. Beads views reference `pinned`. Decide whether pinned is a status, a label, or a UI-only grouping.

---

## Convergence signal (P6)

When all three agents agree P6 is complete, each sends:

`[FROM→TO P6: agreed]`

After all signals are in `llm/LOG.md`, this file is locked, bead `fizzy-v4j` is closed, and P7 opens.
