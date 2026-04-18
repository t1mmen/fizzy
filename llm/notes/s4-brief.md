# Brief — S4-lifecycle-entropy-spec

## Identity
- Round / bead: `S4-lifecycle-entropy-spec` / `fizzy-858` (epic)
- Drafter / owner: `fizzy-codex` (alternation: S1=Claude, S2=Codex, S3=Claude, S4=Codex)
- Reviewers: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)
- CEO ratification: not required during round (P-batch already ratified)

## Context (inputs)
- `llm/notes/p6-lifecycle-adapter.md` — primary input
  - §A status mapping table (Q-S-013): canonical Beads status set + Fizzy lifecycle mapping; drafted/published collapsed to "unlabeled inbox"
  - §B closure migration (Q-S-014): Beads is source-of-truth for close signal + attribution; do NOT keep `closures` as SoT
  - §C NotNow → deferred (Q-S-015): postpone/resume are Beads-native status transitions
  - §D entropy → defer_until (Q-S-016): entropy config stays Fizzy-side; applied via CLI writes setting `defer_until`
  - §G reopen semantics: Beads-native restore prior status via metadata
  - §H lifecycle hook plumbing (sketch only — S4 fills it in)
- `llm/notes/p3-data-path-decision.md` §A.3 / §D (CommandClient sketch — now locked in S3)
- `llm/notes/s3-auth-actor-propagation-spec.md` §B.1 (CommandClient signature S4 builds public methods on)
- `llm/notes/s2-board-column-access-projection-spec.md` §B.2 (default column ↔ status mapping that S4 must keep consistent)
- `llm/notes/p9-search-strategy.md` §A.2 (cards.beads_status mirror — S4 status transitions write through CommandClient and the poller catches up)
- `app/models/card/closeable.rb`, `app/models/card/triageable.rb`, `app/models/card/postponable.rb`, `app/models/card/reopenable.rb`, `app/jobs/postponements/auto_postpone_due_*` (existing lifecycle code surface)
- `app/models/closure.rb`, `app/models/account/entropy.rb`, `app/models/board/entropy.rb` (existing entropy / closure code)
- `db/schema.rb` (closures, cards, accounts, boards columns related to lifecycle)

## Objective (one sentence)
Produce an implementation-ready spec — captured as a parent epic + child task perfect-beads + a design doc — for the lifecycle adapter that (a) maps every Fizzy lifecycle action (close/reopen/postpone/triage/resume) to an exact `bd` argv invocation through `Fizzy::Beads::CommandClient`, (b) closes the upstream `Closure` model as source-of-truth (read from Beads instead), and (c) implements entropy as a recurring job that calls `bd update --defer-until ...` with the system actor.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/s4-lifecycle-entropy-spec.md` complete with sections:
  - **§A** — Lifecycle action → CLI argv table (canonical): close, reopen, postpone, triage/in-progress, defer-until, resume — exact `bd update` flags + status values
  - **§B** — `CommandClient` public method enumeration for lifecycle: signatures (`close_issue`, `reopen_issue`, `update_status`, `defer_until`, etc.) building on S3 §B.1
  - **§C** — Closure model deprecation: how Card#closed_at and closure attribution are read from Beads (issues.closed + events) instead of `closures` table; what (if anything) survives in `closures` as Fizzy-side metadata
  - **§D** — Entropy implementation: `AutoPostponeJob` (or successor) using `Current.with(actor: SystemActor.email)` block per S3 §D.3; how board/account entropy windows are computed; argv composition for `bd update --defer-until <ts>`
  - **§E** — Triage / in-progress controllers: how `Cards::ColumnsController` move-to-column flow becomes `bd update --status <status>` (NOT `cards.column_id` write per S2 §B.1)
  - **§F** — Reopen semantics: how reopening a closed issue restores prior status (P6 §G.2 metadata approach); what happens if no prior status is recorded (default to `open`)
  - **§G** — Test strategy: unit (CommandClient lifecycle methods), integration (controller → CommandClient → bd argv), job (AutoPostponeJob with stubbed bd)
  - **§H** — Open questions deferred to later spec rounds
  - **§I** — Bead inventory (table mapping each AC to a child bead)
  - **§J** — Validation checklist
- [ ] Parent epic bead `<S4 epic id>` exists with full perfect-bead structure
- [ ] Child task beads created — one per atomic unit (CLI mapping per action, CommandClient method per status transition, Closure deprecation migration, AutoPostponeJob rewrite, controller rewires, tests). Each child has full perfect-bead structure
- [ ] Dependency graph wired: child beads parent-child to S4 epic; intra-S4 ordering deps; cross-spec deps to S3 (`fizzy-5jt` CommandClient, `fizzy-r4v` Current.actor, `fizzy-1s3` BeadsActorTenanted, `fizzy-du0` SystemActor) and S1 (`fizzy-m6r` cards.beads_status, `fizzy-flu` closures.card_id widening)
- [ ] Ratified 3-of-3 by `[S4: agreed]` signals

## Allowed paths (scope boundary)
- Writable: `llm/notes/s4-*.md`, `llm/LOG.md`, `llm/codex-state.md` (Codex's own state file), `.beads/` via `bd create` / `bd update`
- Read-only: app code, db/schema.rb, P1-P10 docs, S1+S2+S3 docs
- **Excluded**: any code change, any actual lifecycle rewire (this is SPEC, not IMPLEMENTATION); auth/actor (S3 locked); board/column/access projection (S2 locked); FK migrations (S1 locked); label semantics (S5); rich text/comments (S6); attachments (S7); events feed UI (S8); search/poller internals (S9 owns the mirror that catches up status changes)

## Out of scope (explicit)
- Implementing the AutoPostponeJob rewrite or running migrations (that's I-S4)
- Designing the events feed UI (S8)
- Designing the comments mirror (S6)
- Designing the Tag/Tagging mirror (S5; placeholder bead fizzy-6iv exists)
- Bulk lifecycle operations (V2+ per p10 §G.3)
- Modifying P6 doctrine — Codex draft must implement, not re-litigate

## Sources of truth
- `llm/notes/p6-lifecycle-adapter.md` (primary)
- `llm/notes/s3-auth-actor-propagation-spec.md` §B.1 (CommandClient surface to extend)
- `llm/notes/s2-board-column-access-projection-spec.md` §B.2 (column ↔ status mapping consistency)
- `app/models/card/closeable.rb` etc. (current lifecycle code surface)

## Verification plan
### Worker-verification
- `bd show <S4-epic>` shows the epic with full perfect-bead fields
- `bd list --label=spec --label=lifecycle` shows the parent + every child
- `bd show <child>` shows each child has parent-child dep to S4 epic + appropriate blocks-deps to predecessors + cross-spec deps to S3+S1 beads where required
- Cross-check: §A action table has a corresponding bead per action
- Cross-check: §C closure deprecation has migration bead + read-path rewire bead
- §D AutoPostponeJob rewrite uses `Current.with(actor:)` per S3 §D.3 (verify in design field)

### Operator-verification (CEO)
- Read `llm/notes/s4-lifecycle-entropy-spec.md` and `bd show <S4-epic>` to understand the lifecycle adapter end-to-end
- Spot-check: every lifecycle write goes through CommandClient with explicit actor (no env, no global state, no direct Beads SQL writes)

## Output location (artifact)
- `llm/notes/s4-lifecycle-entropy-spec.md` (the design doc)
- Parent epic bead (TBD id; `bd create` during S4 v1 draft)
- Child task beads (created via `bd create` during S4 execution; counts TBD ~10-16)
- LOG entries

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[S4: agreed]`
- Parent epic stays OPEN until I-S4 implementation round consumes it
- Commit + push to dev (incremental per work-persistence)
- Handoff to LOG: "S4 locked; opens S5 — Labels + assignees spec (P7 → impl beads, Claude drafts per alternation)"

## Drafter alternation
- S1 = Claude → locked
- S2 = Codex → locked
- S3 = Claude → locked
- **S4 = Codex drafts, Claude peer, Gemini third-lens** (this brief)
- S5 = Claude drafts, Codex peer, Gemini third-lens (next)
