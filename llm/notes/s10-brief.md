# Brief — S10-metadata-boundary-spec (FINAL spec round)

## Identity
- Round / bead: `S10-metadata-boundary-spec` / `fizzy-e5m` (epic)
- Drafter / owner: `fizzy-codex` (alternation: S9=Claude, S10=Codex — last alternation in S-batch)
- Reviewers: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)
- **This is the FINAL spec round.** After S10 locks, S-batch is complete and Implementation rounds (I-S1+) open.

## Context (inputs)
- `llm/notes/p1-foundational-gap-inventory.md` (entity inventory + metadata fields)
- `llm/notes/p3-data-path-decision.md` (Beads schema immutable; what survives in MySQL is sidecar by definition)
- `llm/notes/p7-multi-assignee-tags-labels.md` §C (reserved label namespace `fizzy/*`)
- `llm/notes/p9-search-strategy.md` §A.2 (Card mirror schema vs sidecar boundary)
- All locked S-rounds (S1-S9) — the metadata vs sidecar decisions implicit in each
- `db/schema.rb` — every Fizzy table that is "sidecar" vs Beads-mirror

## Objective (one sentence)
Produce the rulebook spec — captured as a parent epic + child task perfect-beads + a design doc — that codifies the **decision criteria** for "should this Fizzy concern live as a Beads `metadata.fizzy.*` JSON field, OR as a Fizzy MySQL sidecar table?", documents the reserved key namespaces (`metadata.fizzy.*` JSON path conventions, `fizzy/*` label namespace), and audits every existing S1-S9 design choice against the rulebook for consistency.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/s10-metadata-boundary-spec.md` complete with sections:
  - **§A** — Decision rulebook: under what conditions does a concern live in Beads `metadata.fizzy.*` JSON vs in a Fizzy MySQL sidecar table? Criteria include: cardinality (single-value vs many), query frequency (frequent → sidecar for indexable joins; rare → metadata), CLI visibility need (must be visible to `bd query` → metadata; Fizzy-only → sidecar), atomicity (atomic update needed → sidecar with FK; eventual sync OK → metadata)
  - **§B** — Reserved key namespaces:
    - `metadata.fizzy.*` JSON path: reserved for Fizzy-side metadata stored in Beads `issues.metadata` (e.g. `metadata.fizzy.prior_status` per S4 §F.2)
    - `fizzy/*` label prefix: reserved for system labels per P7 §C + S5 §D.1
    - registry table covering both
  - **§C** — Audit of S1-S9 decisions: pass/fail each existing concern against the rulebook
    - Card lifecycle fields (status, closed_at, defer_until) → MIRROR (sidecar columns on cards) — passes (high-frequency UI query)
    - Comments → MIRROR (comments table) — passes (high-frequency UI query + ActionText cache)
    - Tags → MIRROR (tags+taggings) — passes (autocomplete + filter)
    - Assignments → SIDECAR-CANONICAL (Beads only mirrors primary) — passes (multi-assignee + UI primary)
    - Pins → SIDECAR-CANONICAL (Fizzy-only) — passes (per-user)
    - Reactions → ? (unaudited — what's the decision?)
    - Watch state → SIDECAR-CANONICAL (Fizzy-only watches table) — passes
    - Boards/Columns/Access → SIDECAR-CANONICAL (Fizzy-only, label namespace projects via S2) — passes
    - prior_status (S4 reopen) → METADATA in Beads — passes (rare query, needs CLI visibility for audit)
    - Storage entries (S7) → SIDECAR-CANONICAL (Fizzy-only) — passes
  - **§D** — Migration / write rules: when writing a concern that's in metadata, what's the protocol? `bd update <id> --metadata fizzy.foo=bar` (or equivalent) via CommandClient with `--actor`
  - **§E** — Read rules: how do controllers/queries access metadata vs sidecar? Sidecar = AR; metadata = poller-mirrored field on Card if needed for filtering
  - **§F** — Deprecated patterns: explicit list of "do NOT" patterns (e.g. don't store Fizzy-only state directly in Beads metadata if it's ephemeral; don't create a sidecar for a single-value attribute that fits in metadata cleanly)
  - **§G** — Test strategy
  - **§H** — Open questions
  - **§I** — Bead inventory
  - **§J** — Validation checklist
- [ ] Parent epic + child beads (~6-10 — smallest S-round, mostly audits + rulebook docs)
- [ ] **Audits S1-S9 for consistency** — flags any concern that needs reclassification (rare; expected to mostly pass)
- [ ] Cross-spec deps where applicable
- [ ] Ratified 3-of-3 by `[S10: agreed]` signals

## Allowed paths
- Writable: `llm/notes/s10-*.md`, `llm/LOG.md`, `llm/codex-state.md`, `.beads/`
- Read-only: app code, db/schema.rb, P1-P10 docs, S1-S9 docs

## Out of scope
- Re-litigating any S1-S9 decision (S10 just AUDITS for consistency — if a S1-S9 decision is wrong per the rulebook, S10 logs it as an open question for a future round, doesn't fix it)
- Implementation of metadata read/write code (that's I-S10 if any)

## Definition of done
- 3-of-3 `[S10: agreed]`; epic stays OPEN until I-S10 (if any implementation needed; mostly docs)
- Handoff: "S10 locked; **S-batch COMPLETE**; opens I-batch (Implementation rounds I-S1+ in dependency order)"

## Drafter alternation
- S9 = Claude → locked
- **S10 = Codex drafts, Claude peer, Gemini third-lens** (FINAL)
- After S10 lock: S-batch closes; I-batch opens.
