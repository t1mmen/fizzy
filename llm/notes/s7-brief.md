# Brief — S7-attachments-storage-quotas-spec

## Identity
- Round / bead: `S7-attachments-storage-quotas-spec` / `fizzy-yeu` (epic)
- Drafter / owner: `fizzy-claude` (alternation: S1=Claude, S2=Codex, S3=Claude, S4=Codex, S5=Claude, S6=Codex, S7=Claude)
- Reviewers: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)

## Context (inputs)
- `llm/notes/p1-foundational-gap-inventory.md` §A (active_storage_attachments, storage_entries, attachments-via-ActionText)
- `llm/notes/s1-card-fk-migration-spec.md` (FK widening already shipped: `fizzy-cjs` active_storage_attachments.record_id, `fizzy-0ic` storage_entries.recordable_id, `fizzy-jzw` action_text_rich_texts.record_id)
- `llm/notes/s6-rich-text-comments-spec.md` §A (Beads description plaintext SoT; ActionText is derived cache — implications for inline attachments embedded in description rich text)
- `llm/notes/p3-data-path-decision.md` (Beads has no canonical attachment model; attachments are Fizzy-only)
- `app/models/storage_entry.rb`, `app/models/storage/cleanup.rb` (current Fizzy storage layer)
- `app/models/account.rb` storage quota fields (if any) + `app/models/account/storage_*` if exists
- `db/schema.rb` — active_storage_*, storage_entries tables

## Objective (one sentence)
Produce an implementation-ready spec for: (a) how ActiveStorage attachments survive when their parent record's id becomes a Beads issue id string (post-S1 FK widening), (b) attachment lifecycle when Beads is the SoT for description/comments but Beads has no attachment concept (Fizzy-only attachments), (c) storage quota posture per-account in single-tenant install (per Q-S-026), (d) cleanup/orphan handling when Beads issues are closed/deferred.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/s7-attachments-storage-quotas-spec.md` complete with sections:
  - **§A** — ActiveStorage record_id varchar posture: how `active_storage_attachments(record_type, record_id)` rows reference Card/Comment/etc. with varchar IDs (post-S1 already migrated; S7 verifies + tests)
  - **§B** — Attachment-to-Beads relationship: Beads has NO canonical attachment model. Where attachments "live" (Fizzy-side `active_storage_blobs` + `active_storage_attachments` keyed by Beads issue id string)
  - **§C** — Inline-attachment-in-description handling (S6 §A.3 says ActionText is a derived cache from Beads plaintext — so what happens to inline image attachments? Plaintext loses them. Two options: (i) Inline attachments stripped on Beads write (Fizzy retains via separate `cards_attachments` association); (ii) Inline attachments encoded as plaintext markers + reattached on render)
  - **§D** — Comment attachment handling: same as §C but for comment bodies
  - **§E** — Storage quota model: per-account quota config; how usage is computed (sum of `active_storage_blobs.byte_size` for account); enforcement at upload time; soft-warn vs hard-reject
  - **§F** — Cleanup/orphan handling: when a Beads issue is deleted (rare; not in V1 UI but possible via CLI), what happens to its attachments? Cleanup job design
  - **§G** — Existing import/export interaction: per AGENTS.md "Imports and exports", attachments must round-trip through ZIP — how single-tenant export bundles attachments keyed by Beads issue id string
  - **§H** — Test strategy
  - **§I** — Open questions deferred
  - **§J** — Bead inventory
  - **§K** — Validation checklist
- [ ] Parent epic bead exists with full perfect-bead structure
- [ ] Child task beads created (~6-12 — smaller scope than S2-S6 since FK widening is already done)
- [ ] Cross-spec deps to S1 (`fizzy-cjs`, `fizzy-0ic`, `fizzy-jzw`) and S6 (`fizzy-edq.4` plaintext serializer for inline-attachment stripping)
- [ ] Ratified 3-of-3 by `[S7: agreed]` signals

## Allowed paths
- Writable: `llm/notes/s7-*.md`, `llm/LOG.md`, `llm/claude-state.md`, `.beads/`
- Read-only: app code, db/schema.rb, P1-P10 docs, S1-S6 docs

## Out of scope
- Implementation (I-S7); CDN/external storage migration (deferred); attachment encryption (V2)

## Sources of truth
- `llm/notes/p1-foundational-gap-inventory.md` §A
- `llm/notes/s1-card-fk-migration-spec.md`
- `llm/notes/s6-rich-text-comments-spec.md` §A
- `app/models/storage_entry.rb`, `app/models/account/data_transfer/`

## Definition of done
- 3-of-3 `[S7: agreed]`; epic stays OPEN until I-S7
- Handoff: "S7 locked; opens S8 — Events + activity feed + (deferred) webhooks (P8 → impl beads, Codex drafts per alternation)"

## Drafter alternation
- S7 = Claude drafts, Codex peer, Gemini third-lens
- S8 = Codex drafts (next)
