# Brief — S3-auth-actor-propagation-spec

## Identity
- Round / bead: `S3-auth-actor-propagation-spec` / `fizzy-rqx` (epic)
- Drafter / owner: `fizzy-claude` (alternation: S1=Claude, S2=Codex, S3=Claude)
- Reviewers: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
- CEO ratification: not required during round (P-batch already ratified)

## Context (inputs)
- `llm/notes/p5-auth-bridging.md` — primary input
  - §A Actor resolution across all paths (Identity-as-actor; per-call argv flag NOT env)
  - §B Bearer-token JSON API future
  - §C User model simplification
  - §D Roles in single-tenant
- `llm/notes/p3-data-path-decision.md` (CommandClient pattern referenced from §A.3)
- `llm/notes/s2-board-column-access-projection-spec.md` §D.5 (writes that touch Beads — controllers that will use CommandClient)
- `app/models/identity.rb`, `app/models/user.rb`, `app/models/session.rb` (current auth code refs)
- `app/controllers/concerns/authentication.rb` + sessions controllers (login flow)
- `app/jobs/application_job.rb` + `FizzyActiveJobExtensions` (existing Current.account propagation; we extend this to Current.actor)
- `db/schema.rb` (identities, users, sessions tables)
- `.beads/config.yaml` (bd CLI conventions)

## Objective (one sentence)
Produce an implementation-ready spec — captured as a parent epic + child task perfect-beads + a design doc — for the actor-propagation system that lets every Beads-touching write carry the canonical actor identifier (Identity email per P5 §A.5) all the way from controller to job to the `bd --actor <email>` argv flag, without leaking actor state across requests/threads or ENV.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/s3-auth-actor-propagation-spec.md` complete with sections:
  - **§A** — `Current.actor` definition: where set, where read, lifecycle (request boundary; job boundary), thread-safety guarantees
  - **§B** — `Fizzy::Beads::CommandClient` exact API: method signatures (`call(*args, actor:)`), how `--actor <email>` argv flag is composed, error semantics (raised on missing actor)
  - **§C** — Web controller integration: where `Current.actor = Current.user.identity.email` is set (likely a `set_current_actor` before_action in `ApplicationController`); how it propagates to CommandClient calls inside the action
  - **§D** — Background job actor propagation: extension to `FizzyActiveJobExtensions` (existing pattern for Current.account) to also serialize+restore Current.actor; how the system-actor (e.g. entropy auto-postpone job) maps to a designated system Identity
  - **§E** — Bearer-token JSON API future hook: how a future bearer-token request resolves to an Identity (P5 §B placeholder; V1 doesn't ship this but the spec must NOT preclude it)
  - **§F** — System-actor identity: who/what email represents Fizzy itself when it acts on Beads (e.g. `system@<install>.fizzy`); how it is created at install time; how it differs from human Identity (no Session, no login)
  - **§G** — Failure modes: what happens if Current.actor is unset when CommandClient is called (raise vs. fallback); what happens if the actor email doesn't exist as a Beads-side known actor; offline/missing bd binary handling
  - **§H** — Test strategy: unit tests (CommandClient with explicit actor), integration tests (controller→CommandClient actor propagation), job tests (Current.actor restoration)
  - **§I** — Open questions deferred to later S-rounds (with explicit handoff)
  - **§J** — Bead inventory (table mapping each AC to a child bead under fizzy-eq4-equivalent S3 epic)
  - **§K** — Validation checklist
- [ ] Parent epic bead `<S3 epic id>` exists with full perfect-bead structure
- [ ] Child task beads created — one per atomic unit (Current.actor module, CommandClient class, ApplicationController before_action, ActiveJob extension, system-Identity bootstrap, test suites). Each child has full perfect-bead structure (title verb-led, description=WHY, design=HOW, acceptance=WHAT verifiable, type, priority, labels, assignee, parent-child to S3 epic, blocks-deps where ordering matters)
- [ ] Dependency graph wired: child beads parent-child to S3 epic; intra-S3 ordering deps; cross-spec deps to S2 children where Beads-touching controllers exist (e.g. `fizzy-eq4.8`, `fizzy-eq4.9` — will use CommandClient)
- [ ] Ratified 3-of-3 by `[S3: agreed]` signals

## Allowed paths (scope boundary)
- Writable: `llm/notes/s3-*.md`, `llm/LOG.md`, `llm/claude-state.md`, `.beads/` via `bd create` / `bd update`
- Read-only: app code, db/schema.rb, P1-P10 docs, S1+S2 docs
- **Excluded**: any code change, any actual auth rewire (this is SPEC, not IMPLEMENTATION); login/session UX (P5 already locked, not S3); board/column projection internals (S2 owns); lifecycle/entropy CLI argv table (S4 owns); label CLI argv table (S5 owns — S3 only specifies CommandClient surface and how actor flag is composed)

## Out of scope (explicit)
- Implementing CommandClient or running CLI integration (that's I-S3)
- Designing the bearer-token endpoint internals (P5 §B is the locked posture; S3 only ensures spec is forward-compatible)
- Login/magic-link flow changes (P5 §A, no change)
- Designing the system-Identity install bootstrap UX (out of scope for V1; S3 only specifies "system Identity must exist" + how it's created programmatically at install)

## Sources of truth
- `llm/notes/p5-auth-bridging.md` (primary)
- `llm/notes/p3-data-path-decision.md` §A.3 (CommandClient sketch)
- `app/controllers/concerns/authentication.rb` + `app/models/current.rb` (current Current.* pattern)
- `app/jobs/application_job.rb` + extensions (existing serialization pattern to extend)
- `app/models/identity.rb` (canonical actor entity)

## Verification plan
### Worker-verification
- `bd show <S3-epic>` shows the epic with full perfect-bead fields
- `bd list --label=spec --label=auth` shows the parent + every child
- `bd show <child>` shows each child has parent-child dep to S3 epic + appropriate blocks-deps to predecessors + cross-spec deps to S2 controllers
- Cross-check: every §B method in CommandClient has a corresponding bead in §J
- Cross-check: §D ActiveJob extension has a bead with explicit test acceptance criteria
- §F system-actor bootstrap has a bead

### Operator-verification (CEO)
- Read `llm/notes/s3-auth-actor-propagation-spec.md` and `bd show <S3-epic>` to understand the actor-propagation plan end-to-end
- Spot-check: `bd --actor <email>` argv flag is the ONLY way actor reaches Beads (no env var, no global state)

## Output location (artifact)
- `llm/notes/s3-auth-actor-propagation-spec.md` (the design doc)
- Parent epic bead (TBD id; `bd create` during S3 v1 draft)
- Child task beads (created via `bd create` during S3 execution; counts TBD ~8-14)
- LOG entries

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[S3: agreed]`
- Parent epic stays OPEN until I-S3 implementation round consumes it
- Commit + push to dev (incremental per work-persistence)
- Handoff to LOG: "S3 locked; opens S4 — Lifecycle + entropy spec (P6 → impl beads, Codex drafts per alternation)"

## Drafter alternation
- S1 = Claude drafted, Codex peer, Gemini third-lens → locked
- S2 = Codex drafted, Claude peer, Gemini third-lens → locked
- **S3 = Claude drafts, Codex peer, Gemini third-lens** (this brief)
- S4 = Codex drafts, Claude peer, Gemini third-lens (next)
