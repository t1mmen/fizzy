# Brief — S5-labels-assignees-spec

## Identity
- Round / bead: `S5-labels-assignees-spec` / `fizzy-h91` (epic)
- Drafter / owner: `fizzy-claude` (alternation: S1=Claude, S2=Codex, S3=Claude, S4=Codex, S5=Claude)
- Reviewers: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
- CEO ratification: not required during round (P-batch already ratified)

## Context (inputs)
- `llm/notes/p7-multi-assignee-tags-labels.md` — primary input
  - §A multi-assignee strategy (Q-S-018): assignments sidecar table; many-to-many
  - §B Tag↔Label sync (Q-S-017): Beads labels canonical, Fizzy `tags`/`taggings` mirror, ApplicationCable broadcast on poller writes
  - §C label namespace conflict prevention: reserved `fizzy/` prefix registry
  - §D tag normalization (Q-S-051): downcase + slugify + replace `/` etc., applied on Beads writes
  - §E adapter shape sketch (S5 fills it in concretely)
- `llm/notes/p4-ui-projection-deep-dive.md` §A.5 (label namespace `fizzy/board/<board_uuid>` reserved)
- `llm/notes/s2-board-column-access-projection-spec.md` §A.2/§A.3/§D.4 (Board membership label, TaggingsController rewires depend on this spec; cross-spec dep `fizzy-eq4.9` blocked-by S5 placeholder `fizzy-6iv`)
- `llm/notes/s3-auth-actor-propagation-spec.md` §B.1 (CommandClient surface — S5 adds `add_label`, `remove_label`, `set_labels` methods)
- `llm/notes/s4-lifecycle-entropy-spec.md` (S4 already locked CommandClient lifecycle methods; S5 adds label-facing methods following same patterns)
- `db/schema.rb` (tags, taggings, assignments tables — current shape)
- `app/models/tag.rb`, `app/models/tagging.rb`, `app/models/assignment.rb` (current AR models)
- `app/controllers/cards/taggings_controller.rb` (current write surface)
- `app/controllers/cards/assignments_controller.rb` (current write surface)

## Objective (one sentence)
Produce an implementation-ready spec — captured as a parent epic + child task perfect-beads + a design doc — for (a) labels: how Beads-canonical labels mirror into Fizzy `tags`/`taggings` via the S9 poller and how Fizzy controllers WRITE labels via `bd update --add-label/--remove-label/--set-labels` through CommandClient, (b) assignees: how the existing `assignments` sidecar table (post-S1 FK widening) preserves multi-assignee, with sync to Beads `assignee` field via CommandClient, (c) reserved-label namespace registry + tag normalization rules.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/s5-labels-assignees-spec.md` complete with sections:
  - **§A** — Beads-canonical label model: `bd update --add-label`/`--remove-label`/`--set-labels` argv table; how multiple labels are passed; reserved namespace enforcement
  - **§B** — `tags`/`taggings` mirror schema: how the S9 poller projects Beads labels into MySQL (idempotent upserts; tag dedup by normalized title; Search::Record sync per P9)
  - **§C** — `CommandClient` label methods: `add_label(id, label)`, `remove_label(id, label)`, `set_labels(id, labels[])` signatures + argv composition + actor enforcement
  - **§D** — Reserved label namespace registry: `fizzy/board/*`, `fizzy/system/*`, etc.; how Fizzy validates user-typed labels reject reserved namespaces (controller-side); how poller honors them server-side
  - **§E** — Tag normalization: downcase + slugify rules; applied at Fizzy write time before passing to `bd`; documented invariant for any label flowing through CommandClient
  - **§F** — Assignment sidecar: how `assignments(card_id, user_id)` preserves multi-assignee; sync to Beads `issues.assignee` (single-value) — strategy (reserved label per assignee? sidecar canonical with single Beads assignee = "primary"?)
  - **§G** — TaggingsController rewire: how `Cards::TaggingsController#create/destroy` (current AR write) becomes CommandClient label write + poller mirror (closes S2 cross-spec dep `fizzy-eq4.9`)
  - **§H** — AssignmentsController rewire: how `Cards::AssignmentsController` keeps writing to `assignments` table AR-style + emits Beads assignee write via CommandClient
  - **§I** — Test strategy: unit (CommandClient label methods + normalization), integration (controller → CommandClient + AR sidecar consistency), poller-mirror (out of scope here; S9 owns)
  - **§J** — Open questions deferred to later S-rounds
  - **§K** — Bead inventory (table mapping each AC to a child bead)
  - **§L** — Validation checklist
- [ ] Parent epic bead `<S5 epic id>` exists with full perfect-bead structure
- [ ] Placeholder bead `fizzy-6iv` (S5 lock placeholder, created during S2) is CLOSED when S5 locks 3-of-3 (per its own acceptance criteria)
- [ ] Child task beads created — one per atomic unit (CommandClient label methods, normalization helper, namespace registry, controller rewires, sidecar mirror logic, tests). Each child has full perfect-bead structure
- [ ] Dependency graph wired: child beads parent-child to S5 epic; intra-S5 ordering deps; cross-spec deps to S3 (`fizzy-5jt` CommandClient, `fizzy-r4v` Current.actor) and S1 (`fizzy-k48` taggings.card_id, `fizzy-h6i` assignments.card_id widen)
- [ ] Cross-spec edge: when S5 locks, `fizzy-eq4.9` (S2 TaggingsController rewire) becomes unblocked from the S5-side perspective
- [ ] Ratified 3-of-3 by `[S5: agreed]` signals

## Allowed paths (scope boundary)
- Writable: `llm/notes/s5-*.md`, `llm/LOG.md`, `llm/claude-state.md`, `.beads/` via `bd create` / `bd update` / `bd close fizzy-6iv` (on lock)
- Read-only: app code, db/schema.rb, P1-P10 docs, S1-S4 docs
- **Excluded**: any code change, any actual rewire (this is SPEC, not IMPLEMENTATION); CommandClient surface (S3 locked; S5 only ADDS label-facing methods); auth/actor (S3); lifecycle (S4); FK migrations (S1); board projection (S2 — S5 only consumes the namespace decision); rich text/comments (S6); attachments (S7); events feed (S8); poller internals (S9 — S5 specifies WHAT must mirror; S9 specifies HOW)

## Out of scope (explicit)
- Implementing the rewire / poller / migrations (that's I-S5)
- Designing the comments mirror (S6)
- Designing the events feed UI (S8)
- Bulk label operations (V2+ per p10 §G.3)

## Sources of truth
- `llm/notes/p7-multi-assignee-tags-labels.md` (primary)
- `llm/notes/s3-auth-actor-propagation-spec.md` §B.1 (CommandClient surface to extend)
- `llm/notes/s4-lifecycle-entropy-spec.md` §B.1 (S4 method enum precedent for adding new methods)
- `db/schema.rb` (tags, taggings, assignments shape)

## Verification plan
### Worker-verification
- `bd show <S5-epic>` shows the epic with full perfect-bead fields
- `bd list --label=spec --label=labels` shows the parent + every child
- `bd show <child>` shows each child has parent-child dep + intra-S5 ordering + cross-spec deps to S3 (`fizzy-5jt`, `fizzy-r4v`) and S1 (`fizzy-k48`, `fizzy-h6i`)
- Cross-check: §A action table has corresponding bead per CommandClient method
- Cross-check: §D namespace registry has a controller-validation bead AND a poller-server-side enforcement bead
- After S5 locks: `bd close fizzy-6iv --reason="S5 locked 3-of-3; label projection doctrine + impl beads in place"` runs cleanly; `fizzy-eq4.9` shows fizzy-6iv as closed

### Operator-verification (CEO)
- Read `llm/notes/s5-labels-assignees-spec.md` and `bd show <S5-epic>` to understand the labels/assignees plan end-to-end
- Spot-check: every label write goes through CommandClient with explicit actor (no direct Beads SQL writes); reserved namespace rejected at controller validation

## Output location (artifact)
- `llm/notes/s5-labels-assignees-spec.md` (the design doc)
- Parent epic bead (TBD id; `bd create` during S5 v1 draft)
- Child task beads (created via `bd create` during S5 execution; counts TBD ~10-14)
- LOG entries
- `bd close fizzy-6iv` on lock

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[S5: agreed]`
- `fizzy-6iv` placeholder closed on lock
- Parent epic stays OPEN until I-S5 implementation round consumes it
- Commit + push to dev (incremental per work-persistence)
- Handoff to LOG: "S5 locked; opens S6 — Rich text + comments spec (P1+Beads comments → impl beads, Codex drafts per alternation)"

## Drafter alternation
- S1 = Claude → locked
- S2 = Codex → locked
- S3 = Claude → locked
- S4 = Codex → locked
- **S5 = Claude drafts, Codex peer, Gemini third-lens** (this brief)
- S6 = Codex drafts, Claude peer, Gemini third-lens (next)
