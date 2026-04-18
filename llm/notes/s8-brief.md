# Brief — S8-events-activity-feed-spec

## Identity
- Round / bead: `S8-events-activity-feed-spec` / `fizzy-n3l` (epic)
- Drafter / owner: `fizzy-codex` (alternation: S7=Claude, S8=Codex)
- Reviewers: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)

## Context (inputs)
- `llm/notes/p8-events-sync.md` — primary input
  - §A current event systems (Fizzy Event + Webhook + Beads events/comments)
  - §C canonical events log decision (Beads is canonical)
  - §D Beads→Fizzy ingestion strategy
  - §E webhooks posture (V1 = inbound webhooks deferred)
  - §F activity feed / timeline posture
  - §G failure modes (loop avoidance, etc.)
- `llm/notes/p9-search-strategy.md` §A.2 (poller doctrine; S9 owns mechanism — S8 specifies what events drive the activity feed)
- `llm/notes/s4-lifecycle-entropy-spec.md` (lifecycle CommandClient writes that produce Beads events)
- `llm/notes/s5-labels-assignees-spec.md` (label writes that produce Beads events)
- `llm/notes/s6-rich-text-comments-spec.md` (comment + description writes that produce Beads events)
- `app/models/event.rb`, `app/models/eventable.rb` (current Fizzy Event surface)
- `app/models/webhook.rb`, `app/jobs/webhook/*` (current outbound webhook delivery — survives intact in V1)

## Objective (one sentence)
Produce an implementation-ready spec for: (a) which Beads events the S9 poller mirrors into Fizzy `Event` rows for the activity feed/timeline UI, (b) loop-avoidance (Fizzy-originated writes already produce events; do NOT re-emit when the poller mirrors them back), (c) outbound webhooks posture (Fizzy outbound webhooks survive intact for V1; Beads-originated writes also fire them once after mirror), (d) inbound webhooks deferral (V2+).

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/s8-events-activity-feed-spec.md` complete with sections:
  - **§A** — Beads event types mirrored: which `bd events` types become Fizzy `Event` rows (status_change, comment_added, label_added/removed, assignee_changed, defer_changed, etc.); per-type mapping to Fizzy Eventable polymorphic targets
  - **§B** — Loop avoidance: Fizzy-originated writes (controller → CommandClient → bd) already create a Fizzy Event row at the controller layer (eventually); Beads emits its own event; poller mirrors it. Prevent double-emit using event correlation/dedup (Beads event id stored on the mirrored row)
  - **§C** — Activity feed UI: which Events surface in the feed (Card.events, Board.events, User.events); how the feed is paginated; timezone/timestamp handling
  - **§D** — Outbound webhooks: existing `Webhook` + delivery pipeline survives intact; ensure poller-mirrored events trigger outbound webhooks ONCE (Fizzy-originated writes shouldn't double-fire)
  - **§E** — Inbound webhooks: explicitly deferred (Q-S-022 V2+); document the deferral
  - **§F** — Notification triggers: Card watch + mention notifications work with mirrored events (cross-link to S6 §F mention parser)
  - **§G** — Test strategy
  - **§H** — Open questions deferred
  - **§I** — Bead inventory
  - **§J** — Validation checklist
- [ ] Parent epic + child beads (~8-12)
- [ ] Cross-spec deps to S3 (CommandClient), S4/S5/S6 (write paths that emit Beads events), S9 placeholder (poller mechanism)
- [ ] Ratified 3-of-3 by `[S8: agreed]` signals

## Allowed paths
- Writable: `llm/notes/s8-*.md`, `llm/LOG.md`, `llm/codex-state.md`, `.beads/`
- Read-only: app code, db/schema.rb, P1-P10 docs, S1-S7 docs

## Out of scope
- Implementation (I-S8); inbound webhooks (V2+); search filtering/poller internals (S9); UI design beyond data path

## Definition of done
- 3-of-3 `[S8: agreed]`; epic stays OPEN until I-S8
- Handoff: "S8 locked; opens S9 — Search + filter + poller spec (P9 → impl beads, Claude drafts per alternation)"

## Drafter alternation
- S8 = Codex drafts, Claude peer, Gemini third-lens
- S9 = Claude drafts (next)
