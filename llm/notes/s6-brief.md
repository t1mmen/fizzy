# Brief — S6-rich-text-comments-spec

## Identity
- Round / bead: `S6-rich-text-comments-spec` / `fizzy-edq` (epic)
- Drafter / owner: `fizzy-codex` (alternation: S1=Claude, S2=Codex, S3=Claude, S4=Codex, S5=Claude, S6=Codex)
- Reviewers: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)
- CEO ratification: not required during round (P-batch already ratified)

## Context (inputs)
- `llm/notes/p1-foundational-gap-inventory.md` §C (Card description as Action Text rich text) and §B (Beads `comments` schema)
- `llm/notes/p3-data-path-decision.md` (CommandClient pattern)
- `llm/notes/s1-card-fk-migration-spec.md` §F.9 (`comments.card_id` widened post-S1) AND tombstone note re `comments.id` deferred to S6 (cards.id is varchar, comments table id stays as it is until S6 decides)
- `llm/notes/s3-auth-actor-propagation-spec.md` §B.1 (CommandClient surface — S6 adds comment-facing methods)
- `llm/notes/s4-lifecycle-entropy-spec.md` §B (S4 method-enum precedent for adding new CommandClient methods)
- `llm/notes/s5-labels-assignees-spec.md` §B.3 (poller mirror pattern — S6 follows the same callback-bypass posture for comment mirror)
- `llm/notes/p9-search-strategy.md` §A.2 (Card mirror doctrine; comments mirror is parallel to taggings mirror)
- `db/schema.rb` (comments table; action_text_rich_texts table; mentions table)
- `app/models/comment.rb`, `app/models/card.rb` (Card has Action Text rich text on `description`)
- `app/controllers/cards/comments_controller.rb` (current write surface)
- `app/models/mention.rb` (current mention model)
- `bd comment --help` and `bd comments --help` (Beads CLI surface for comments)

## Objective (one sentence)
Produce an implementation-ready spec — captured as a parent epic + child task perfect-beads + a design doc — for (a) Card description: where canonical rich text lives (Beads `issues.description` plaintext vs Fizzy Action Text HTML), how the two stay in sync, (b) Comments: Fizzy `comments` table as MySQL mirror of Beads `comments` (Beads is SoT), with writes through CommandClient and reads from mirror, (c) `comments.id` migration decision (deferred from S1), (d) mention parsing pipeline (`@user` in body → `mentions` rows on poller mirror).

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/s6-rich-text-comments-spec.md` complete with sections:
  - **§A** — Card description: canonical storage decision (Beads plaintext SoT vs Fizzy ActionText HTML cache); render-time conversion strategy; how user edits flow through CommandClient
  - **§B** — Comments mirror schema: how `comments` table mirrors Beads `comments(issue_id, body, author, created_at, ...)`; comments.id post-migration type (varchar(255) matching Beads comment id?); cross-spec dep to S1 deferred decision
  - **§C** — `CommandClient` comment methods: `add_comment(issue_id, body, ...)`, `update_comment(comment_id, body)`, `delete_comment(comment_id)` signatures + `bd comment` argv composition + actor enforcement
  - **§D** — Comment poller contract (S9-owned mechanism; S6 specifies what mirrors): callback-bypass upsert_all per S5 §B.3 precedent; explicit Search::Record sync for searchable comment bodies
  - **§E** — `Cards::CommentsController` rewire: `#create/#update/#destroy` calls CommandClient instead of AR write; optimistic UI per S5 §G.2 precedent
  - **§F** — Mention parsing: `@email` or `@username` in comment body → `mentions(comment_id, mentioned_user_id)` rows; whether mention parsing happens at controller (write side) or poller (mirror side); how Beads-side direct comment writes that contain @mentions get mirrored into Fizzy mention notifications
  - **§G** — Card description rich text: Action Text `description` survives (Fizzy-side) but the canonical text is Beads `issues.description` (plaintext). On Card edit: write plaintext via CommandClient `bd update --description`; on render: Fizzy ActionText HTML is a derived display cache (rebuilt from Beads plaintext on poller tick or on-demand)
  - **§H** — Test strategy: unit (CommandClient comment methods), integration (CommentsController flow), poller mirror (out of scope; S9 owns)
  - **§I** — Open questions deferred to later spec rounds (with explicit handoff)
  - **§J** — Bead inventory (table mapping each AC to a child bead)
  - **§K** — Validation checklist
- [ ] Parent epic bead `<S6 epic id>` exists with full perfect-bead structure
- [ ] Child task beads created — one per atomic unit (CommandClient comment methods, comments.id migration, CommentsController rewire, ActionText description sync, mention parser, tests). Each child has full perfect-bead structure
- [ ] Dependency graph wired: child beads parent-child to S6 epic; intra-S6 ordering deps; cross-spec deps to S3 (`fizzy-5jt`, `fizzy-r4v`, `fizzy-3ad`), S5 (`fizzy-5yn` LabelNormalizer if comments need normalization?), S1 (`fizzy-0b8` comments.card_id widen + new `comments.id` widen if S6 decides yes)
- [ ] If S6 decides `comments.id` should widen to varchar(255), spec must include a new S1-style migration bead for that change (or wire to existing S1 deferred-decision tombstone bead)
- [ ] Ratified 3-of-3 by `[S6: agreed]` signals

## Allowed paths (scope boundary)
- Writable: `llm/notes/s6-*.md`, `llm/LOG.md`, `llm/codex-state.md` (Codex's own state file), `.beads/` via `bd create` / `bd update`
- Read-only: app code, db/schema.rb, P1-P10 docs, S1-S5 docs
- **Excluded**: any code change, any actual rewire (this is SPEC, not IMPLEMENTATION); auth/actor (S3 locked); lifecycle (S4 locked); labels/assignees (S5 locked); FK migrations except comments.id (S1 locked except for the explicit deferred-to-S6 decision); board projection (S2 locked); attachments (S7); events feed UI (S8); search/poller internals (S9 owns mechanism — S6 specifies WHAT must mirror)

## Out of scope (explicit)
- Implementing the rewire / poller / migrations (that's I-S6)
- Designing attachments mirror (S7)
- Designing events feed UI (S8)
- Designing the poller internals (S9)
- Any V2 features (per p10 §G.3 deferrals)

## Sources of truth
- `llm/notes/p1-foundational-gap-inventory.md` §B (Beads comments schema) + §C (Card.description ActionText)
- `llm/notes/s1-card-fk-migration-spec.md` (comments.card_id widened; comments.id deferred to S6)
- `llm/notes/s5-labels-assignees-spec.md` §B.3 + §G.2 (mirror + controller-rewire precedent to follow)
- `app/models/comment.rb`, `app/models/card.rb`, `app/models/mention.rb` (current shape)
- `bd comment --help` (CLI argv surface)

## Verification plan
### Worker-verification
- `bd show <S6-epic>` shows the epic with full perfect-bead fields
- `bd list --label=spec --label=comments` shows the parent + every child
- `bd show <child>` shows each child has parent-child dep + intra-S6 ordering + cross-spec deps to S3/S5/S1
- Cross-check: §A canonical-storage decision is concrete (one of: Beads-plaintext-SoT-with-Fizzy-HTML-cache OR Fizzy-HTML-SoT-with-Beads-plaintext-cache OR something else explicitly justified)
- Cross-check: §B comments.id migration decision is concrete (widen-to-varchar OR keep-uuid-with-mapping-table OR something else)
- Cross-check: §F mention parsing pipeline has a clear ownership boundary (controller vs poller)

### Operator-verification (CEO)
- Read `llm/notes/s6-rich-text-comments-spec.md` and `bd show <S6-epic>` to understand the rich text + comments plan end-to-end
- Spot-check: Beads is SoT for comment bodies; Fizzy mirror is callback-bypass per S5 precedent; no cross-DB joins

## Output location (artifact)
- `llm/notes/s6-rich-text-comments-spec.md` (the design doc)
- Parent epic bead (TBD id; `bd create` during S6 v1 draft)
- Child task beads (created via `bd create` during S6 execution; counts TBD ~10-14)
- LOG entries

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[S6: agreed]`
- Parent epic stays OPEN until I-S6 implementation round consumes it
- Commit + push to dev (incremental per work-persistence)
- Handoff to LOG: "S6 locked; opens S7 — Attachments + storage quotas spec (P1 attachments + storage models → impl beads, Claude drafts per alternation)"

## Drafter alternation
- S1 = Claude → locked
- S2 = Codex → locked
- S3 = Claude → locked
- S4 = Codex → locked
- S5 = Claude → locked
- **S6 = Codex drafts, Claude peer, Gemini third-lens** (this brief)
- S7 = Claude drafts, Codex peer, Gemini third-lens (next)
