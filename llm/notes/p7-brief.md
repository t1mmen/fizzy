# Brief — P7-multi-assignee-tags-labels — Q-S-017/018

## Identity
- Round / bead: `P7-multi-assignee-tags-labels` / `fizzy-47p`
- Drafter / owner: `fizzy-claude`
- Reviewers: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)

## Context
- P1 §C.4 (Assignment table, max 100 assignees per card), §C.5 (Tag/Tagging), §E.6 (Q-S-017/018), §B (Beads `labels` table, `issues.assignee` single string)
- P3 (CommandClient writes), P4 (board-label namespace `fizzy/board/<uuid>` already establishes label conventions), P5 (--actor for write attribution)
- `community-bead-uis-research.md` (label patterns from BeadBoard etc.)
- `app/models/assignment.rb`, `app/models/tag.rb`, `app/models/tagging.rb`

## Objective
Decide how Fizzy's many-assignees-per-card model preserves through Beads (which has a single `assignee` string per issue), and how Fizzy `Tag` records sync with Beads `labels` — closing Q-S-017 and Q-S-018.

## Acceptance criteria
- [ ] File `llm/notes/p7-multi-assignee-tags-labels.md` with sections:
  - **§A — Multi-assignee strategy** (Q-S-018): pick one of P1 candidates: (a) Fizzy `assignments` sidecar + Beads `assignee` mirrors primary; (b) serialize all assignees into `issues.metadata.assignees: [...]`; (c) lossy single-assignee. With trade-offs + recommendation.
  - **§B — Tag↔Label sync** (Q-S-017): explicit pattern. (a) Tag is Fizzy display object with name == Beads label string; tagging adds label, deleting tag deletes label. (b) Drop Fizzy Tag entirely; labels are first-class strings. With trade-offs.
  - **§C — Label namespace conflict prevention**: P4 reserved `fizzy/board/<uuid>`; P7 must define how user labels avoid clashing (probably: forbid user labels matching `fizzy/*` prefix).
  - **§D — Tag normalization**: Fizzy Tag normalizes to lowercase, strips leading `#`. Apply same normalization to Beads label writes (otherwise the label-side gains junk like `#Foo` and `Foo` as separate strings).
  - **§E — Adapter shape sketch**: how `Beads::IssueRepository` exposes `add_assignee` / `remove_assignee` / `add_label` / `remove_label`. Includes the Fizzy-side sidecar table (if §A picks (a)) shape.
  - **§F — Resolved Q-S items**: marks Q-S-017 + Q-S-018 ANSWERED.
  - **§G — Open questions** (any new Q-S).
- [ ] Cross-link from p1 inventory.
- [ ] No code changes; sketches only.
- [ ] Ratified 3-of-3 by `[P7: agreed]`.

## Allowed paths
- Writable: `llm/notes/p7-*.md`, LOG/state, p1 (Q-S markers).
- Read-only: app code, P3-P6 docs.
- Excluded: code changes, label/assignment implementation.

## Out of scope
- Implementation (Spec round).
- Events sync (P8).
- Search (P9).

## Sources of truth
- `app/models/assignment.rb`, `app/models/tag.rb`, `app/models/tagging.rb`
- Beads `issues.assignee` (single string) + `labels` table
- P3-P6 decision docs

## Verification
- For each chosen mapping, demonstrate via Rails console / Dolt SQL that the round-trip works under the chosen pattern.

## Output
- `llm/notes/p7-multi-assignee-tags-labels.md`
- Updated p1 inventory
- Bead `fizzy-47p` close
- LOG entries

## Definition of done
- AC satisfied
- 3-of-3 `[P7: agreed]`
- `bd close fizzy-47p`
- Commit + push to dev
- Handoff: "P7 locked; opens P8 — events two-way sync (Q-S-005/021/022)"
