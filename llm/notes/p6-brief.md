# Brief — P6-lifecycle-adapter — status / closure / postpone / entropy translation

> **STATUS**: skeleton (drafted in advance; finalize after P5 lands). Bead created at P6 dispatch time.

## Identity
- Round / bead: `P6-lifecycle-adapter` / `fizzy-XXX` (created at dispatch)
- Drafter / owner: `fizzy-codex` (alternation: P3 Claude, P4 Codex, P5 Claude → P6 Codex)
- Review target: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)

## Context (inputs)
- `llm/notes/p1-foundational-gap-inventory.md` §C.4 — Card lifecycle is compositional (status + side-table presence) — and §E.4 — Q-S-013 (drafted/published mapping), Q-S-014 (Closure migration), Q-S-015 (Card::NotNow → deferred), Q-S-016 (Entropy → defer_until)
- `llm/notes/p3-data-path-decision.md` — adapter shape (CommandClient writes, Beads::Issue reads)
- `llm/notes/p4-ui-projection-deep-dive.md` (locked) — Status/column projection decided in P4 informs how lifecycle transitions surface
- `llm/notes/p5-auth-bridging.md` (locked) — `BD_ACTOR` resolution informs `closed_by` / `not_now_by` user attribution
- `app/models/card.rb`, `app/models/card/closeable.rb`, `app/models/card/postponable.rb`, `app/models/closure.rb`, `app/models/card/not_now.rb`, `app/models/entropy.rb`, `app/models/card/entropic.rb`, `app/models/card/statuses.rb`
- Beads `issues.status` defaults + `custom_statuses` table + `issues.defer_until`

## Objective (one sentence)
Decide how Fizzy's compositional lifecycle (Card.status + Closure presence + Card::NotNow presence + Goldness presence + ActivitySpike presence + Entropy auto-postpone) maps onto Beads' single-status-plus-defer_until model — closing Q-S-013, Q-S-014, Q-S-015, Q-S-016.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/p6-lifecycle-adapter.md` with sections:
  - **§A — Status mapping** (table): Fizzy `cards.status × side-table-rows-present` × → Beads `issues.status`. Including the `drafted` case (no Beads native; pick one of P1 §E.4 candidates: custom status / metadata flag / not-yet-an-issue).
  - **§B — Closure migration**: how `closures` row presence (with `user_id`) survives the transition to `issues.status = closed`. Either (i) keep Fizzy `closures` table FK'd to `issues.id` for the `closed_by` user; (ii) read closer from Beads `events` history; (iii) stuff into `issues.metadata`.
  - **§C — NotNow → deferred**: how `card_not_nows` becomes `issues.status = deferred`. With or without `defer_until` from entropy config?
  - **§D — Entropy → defer_until**: how Board+Account entropy config (auto_postpone_period seconds) translates into per-issue `defer_until` writes. Cron job? On-card-update hook? Both?
  - **§E — Goldness**: from Q-S-028 (P4 likely closed this) — confirm v1 disposition (Fizzy-only sidecar OR drop OR map to priority=0).
  - **§F — ActivitySpike**: from P4 — confirm v1 disposition (Fizzy-only computed UI badge OR drop).
  - **§G — Reopen**: how reopening a closed bead works (presence-of-Closure removal AND Beads status revert). Includes: who is allowed to reopen, what state restores (back to which column).
  - **§H — Lifecycle hook plumbing**: where these mappings live in code (probably in the `Beads::IssueRepository` lifecycle methods sketched in P3 §D, or a new `Beads::Lifecycle` mixin).
  - **§I — Resolved Q-S items**: marks Q-S-013, 014, 015, 016 as ANSWERED.
  - **§J — Open questions**: any new Q-S items.
- [ ] Cross-link from p1 inventory's resolved Q-S entries.
- [ ] No code changes; sketches only.
- [ ] Ratified 3-of-3 by `[P6: agreed]`.

## Allowed paths (scope boundary)
- **Writable**: `llm/notes/p6-*.md`, `llm/LOG.md`, `llm/codex-state.md`, `llm/notes/p1-foundational-gap-inventory.md` (Q-S markers only).
- **Read-only**: app code, Card concerns, P3/P4/P5 decision docs.
- **Excluded**: any code change, any lifecycle implementation.

## Out of scope (explicit)
- Implementing the lifecycle adapter (Implementation round).
- Multi-assignee + tags (P7).
- Events sync (P8).
- Search (P9).
- Fork posture review (P10).

## Sources of truth (anchors)
- `app/models/card.rb`, `app/models/card/statuses.rb`
- `app/models/card/closeable.rb`, `app/models/closure.rb`
- `app/models/card/postponable.rb`, `app/models/card/not_now.rb`
- `app/models/entropy.rb`, `app/models/card/entropic.rb`, `app/models/card/entropy.rb`
- `app/models/card/goldness.rb`, `app/models/card/activity_spike.rb`
- `db/schema.rb` (relevant tables)
- Beads `issues` columns: `status`, `defer_until`, `metadata`, `custom_statuses`
- `llm/notes/p3-data-path-decision.md` §D (adapter shape)

## Verification plan
### Worker-verification
- For each Fizzy state transition (publish → triage → close → reopen → postpone → resume), trace through code and produce a step-by-step trace of: (1) what current Fizzy code does, (2) what the adapter does in each sub-step, (3) what bd CLI command(s) get invoked.
- Cross-check that the chosen mapping for `Closure.user_id` does not lose audit information.

### Operator-verification
- CEO can read p6-lifecycle-adapter.md and follow §A → §G to understand every state transition.

## Output location (artifact)
- `llm/notes/p6-lifecycle-adapter.md`
- Updated `llm/notes/p1-foundational-gap-inventory.md` (Q-S markers)
- Bead `fizzy-XXX` notes/close
- LOG entries

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[P6: agreed]`
- `bd close fizzy-XXX`
- Commit + push to `dev`
- Handoff entry in LOG: "P6 locked; opens P7 — proposed scope: multi-assignee + tags/labels gap (Q-S-017/018)"
