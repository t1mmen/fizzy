# S7 — Attachments + Storage Quotas Spec (Fizzy-only attachments keyed by Beads issue id)

**Status**: v1 ready for peer review
**Bead**: `fizzy-yeu` (epic)
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/s7-brief.md`

This spec defines how ActiveStorage attachments survive the Beads/Fizzy boundary:

- **Beads has NO canonical attachment model**. Attachments are Fizzy-only, keyed by Beads issue id strings (post-S1 FK widening).
- **Inline attachments in description/comments**: stripped on Beads plaintext write (lossy on the Beads side); retained as Fizzy associations on the ActionText derived cache (visible in UI).
- **Storage quota**: per-account using existing `Storage::Total` materialized ledger; soft-warn + hard-reject thresholds at upload time.
- **Cleanup**: orphan job for attachments whose Beads parent has been deleted (rare in V1; CLI-driven).

The existing Fizzy storage layer (`Storage::Entry` ledger + `Storage::Total` materialized + `Storage::Tracked` concern) already supports varchar polymorphic record_ids post-S1 and per-account aggregation. S7 builds on it rather than replacing it.

---

## §A — ActiveStorage record_id varchar posture (verification)

### A.1 Post-S1 schema state

S1 already widened the relevant polymorphic FK columns:
- `fizzy-cjs` — `active_storage_attachments.record_id` uuid → varchar(255)
- `fizzy-0ic` — `storage_entries.recordable_id` uuid → varchar(255)
- `fizzy-jzw` — `action_text_rich_texts.record_id` uuid → varchar(255)

These migrations are children of S1 epic `fizzy-669` and ship as part of I-S1.

### A.2 What S7 verifies

S7 does not re-migrate. S7 mints test beads that verify, post-S1 implementation:
- A Card with `id = "fizzy-abc"` (varchar Beads issue id) can have ActionText description attachments correctly resolved through `active_storage_attachments(record_type="ActionText::RichText", record_id=<rich_text.id>)`.
- A Comment (post-S6 with `comments.id` widened) can have ActionText body attachments correctly resolved.
- `Storage::Tracked#storage_attachments_for_records` correctly resolves attachments through RichText parents when the Card id is varchar.
- `Storage::Entry.record` writes a ledger row keyed by `recordable_id = card.id` (varchar) without type errors.

These tests live in `test/models/storage/` extended for varchar IDs.

## §B — Attachment-to-Beads relationship: Fizzy-only

### B.1 Decision

Beads has NO attachment concept. Beads stores `description` and `comments.text` as plaintext. There is no Beads-side blob storage, no `bd` CLI surface for attachments.

**Attachments stay 100% Fizzy-side**. `active_storage_blobs` + `active_storage_attachments` are Fizzy MySQL tables, never mirrored to Beads, never touched by `bd` writes.

The polymorphic FK `active_storage_attachments.record_id` (varchar post-S1) carries either:
- `record_type="Card", record_id=<beads_issue_id>` (rare; Card direct attachments — none in upstream)
- `record_type="ActionText::RichText", record_id=<rich_text.id>` (common; description + comment body inline attachments)

### B.2 Beads is unaware

`bd ready`, `bd show`, `bd query` see no attachments. Users who interact with Beads via CLI see plain text only. This is documented expected behavior.

If a user wants to share an attachment via CLI workflow, they must reference it by some Fizzy URL (e.g. `https://app.fizzy.localhost/attachments/<id>`) embedded as a plaintext URL in the description/comment body. Out of V1 scope to formalize; documented.

## §C — Inline attachment in description: strip-on-write, retain-in-cache

### C.1 The problem

Per S6 §A, Card description's canonical text is Beads `issues.description` (plaintext). Fizzy ActionText is a derived cache rebuilt from the plaintext.

When a user pastes/embeds an inline image into the Fizzy ActionText editor, the editor produces an `<action-text-attachment>` element wrapping a blob signed_id. On save, S6 §G says we serialize ActionText → Beads plaintext. Plaintext cannot represent the inline attachment — it's lost on the Beads side.

### C.2 Decision: option (i) strip on Beads write, retain Fizzy associations

The serializer (S6 bead `fizzy-edq.4` — `Fizzy::Beads::ActionTextToPlaintext`) strips inline `<action-text-attachment>` elements when producing the Beads plaintext.

But the underlying `ActiveStorage::Attachment` rows that bind blobs to the `ActionText::RichText` row are NOT deleted. They remain in MySQL. Therefore:
- On render: when the poller (or controller projection) rebuilds the ActionText cache from Beads plaintext, the cache HTML is plaintext-paragraphs only — no inline attachments rendered inline.
- But the `ActiveStorage::Attachment` rows still exist, pointing at the `ActionText::RichText` row by `record_id`. They are "orphaned attachments" from the inline-render perspective but still accessible programmatically.

### C.3 UI behavior in V1

V1 ships:
- Description editor accepts inline image paste.
- On save, image is stored as a blob; the inline `<action-text-attachment>` is included in the saved `body` HTML for the ActionText row.
- BUT the Beads `description` is plaintext-only.
- After poller reconciles (or immediately if controller-projection is used per S6 §A.4), the rendered HTML drops the inline attachment.
- **Practical effect**: users SEE their pasted image rendered immediately (optimistic UI from the local AT row), but on next page reload after poller rebuild, the image disappears from inline render. The blob is still stored (and still on the ActionText row), so the attachment count + storage usage stay accurate.

This is intentionally loose for V1 to avoid blocking on an attachment-as-link UX. Revisit in V2 (see §I).

### C.4 Why not option (ii) plaintext markers + reattach on render

Option (ii) would encode inline attachments as plaintext markers like `[attachment:blob_xyz]` in Beads description text, then on render replace with the actual `<action-text-attachment>` elements. Pros: round-trips perfectly. Cons:
- Beads CLI users see the marker garbage in plain readouts.
- Requires careful escaping (what if user types `[attachment:foo]` literally?).
- Marker → blob_id mapping needs an indirection table OR uses a globally unique blob id (signed_id) which exposes internal IDs to readers.

Deferred to V2 if inline-attachment fidelity matters.

## §D — Comment attachment handling

Same pattern as §C: inline attachments in comment ActionText body are stripped on Beads `bd comments add` write (S6 §E.2 plaintext serialization). Blobs and AT row attachments remain in Fizzy MySQL but don't render inline after poller-rebuild.

S6 §E.3 disabled comment edit/delete in V1, so:
- Comment attachments cannot be removed from a comment (Beads append-only + no delete UI).
- Orphan attachment cleanup happens via §F (when the parent Card is deleted in Beads, all comment AT rows + their attachments are cleaned up).

## §E — Storage quota model

### E.1 Existing Fizzy storage layer

Fizzy already has a storage layer (verified via `app/models/storage/`):

- **`Storage::Entry`**: ledger row per attachment add/remove/transfer (`account_id`, `board_id`, `recordable_id` polymorphic, `delta` bytes, `operation`).
- **`Storage::Total`**: materialized per-account / per-board total (re-summed periodically).
- **`Storage::Tracked` concern**: included in `Card`, `ActionText::RichText` (per `Storage::TRACKED_RECORD_TYPES`); records entries on attach/transfer.
- **`Storage::Totaled` concern**: provides `storage_entries` association + `materialize_storage_later` enqueue.
- **`Storage::AttachmentTracking`**: per-attachment lifecycle hooks.

The system already aggregates `byte_size` per account using only the *original upload bytes* (variants/derivatives excluded) — this is the right "user-facing storage usage" semantic for quota enforcement.

### E.2 Per-account quota config (NEW for S7)

V1 single-tenant means one account per install. Quota is therefore install-level.

Add to `Account` model (or `Account::Storage` concern):
- `storage_quota_bytes` — config (defaults to a sensible cap, e.g. 50 GiB for V1; configurable via initializer)
- `storage_warn_threshold` — default 0.85 (85% triggers UI warning)
- `storage_hard_reject_threshold` — default 1.0 (100% blocks new uploads)

These are install-config (not user-editable for V1). Set in `config/application.rb` or an initializer.

### E.3 Enforcement

At upload time (in the controller or in `Storage::Tracked` before the `Storage::Entry` is recorded):
- Read current `Storage::Total` for the account.
- If `(current + new_blob.byte_size) > storage_quota_bytes`: reject upload with 422 + clear error message ("Account storage quota exceeded; remove old attachments or contact admin").
- If `(current + new_blob.byte_size) >= storage_quota_bytes * storage_warn_threshold`: allow, but flash a warning banner in the UI.

Implementation hook: `Storage::Tracked#storage_quota_check` runs before attach commits. New bead F.4 carries this.

### E.4 Quota visibility

Settings UI (`Account::Settings` controller area) shows:
- Current usage bytes / total quota bytes (progress bar)
- Warn state if past threshold
- "What's using my storage" breakdown (per-board, per-card top-N) — uses existing `Storage::Total` per-board

Out of S7 scope to design the UI in detail (that's I-S7); spec specifies the data API is `Storage::Total.for(account)` + `Storage::Total.per_board(account)`.

## §F — Cleanup / orphan handling

### F.1 When a Beads issue is deleted

Beads issue deletion is rare in V1 — there's no UI delete button, but a user can run `bd close <id>` (status only) or `bd issue delete <id>` (hard delete via CLI).

If a Beads issue is hard-deleted via CLI:
- The S9 poller detects the missing issue on next tick.
- Poller runs `OrphanCleanupJob.perform_later(issue_id)`:
  - `Card.find(issue_id).destroy` triggers existing AR cascade (action_text_rich_texts → attachments via dependent: :destroy chains).
  - `Storage::Entry.suppressing_recording { ... }` is used during cleanup to avoid double-counting (the attachments' deletion would otherwise emit negative delta entries that re-balance the ledger).
  - The blob retention period (default 24h) governs when the actual S3/disk file is purged.

### F.2 When a Card is closed (NOT deleted)

Closed Cards retain their attachments (as today). The storage usage stays charged to the account until the Card is hard-deleted.

### F.3 Orphan-attachment scan job

Defensive scheduled job (weekly?): scan for `active_storage_attachments` rows whose `record` no longer resolves (e.g., the parent Card was deleted but cascade missed an attachment). Log + optionally clean up.

This is a defense-in-depth measure; the primary cleanup path is the AR cascade in §F.1.

## §G — Import/export interaction

### G.1 Existing export

Per AGENTS.md "Imports and exports", Account can export to ZIP (handles 500+GB). Existing path: `app/models/account/data_transfer/active_storage/...` walks attachments and bundles them.

### G.2 Post-S1 / S7 changes needed

Because `record_id` is now varchar (Beads issue id string), the export bundle's manifest must serialize attachment associations using string IDs (not the old uuid format). The import side must rehydrate against varchar IDs.

This is a small change to the existing exporter/importer code — no schema work, just serialization key handling. Bead F.5.

### G.3 Round-trip invariant

Export an account → import the ZIP into a fresh install → all attachments resolve correctly to their Beads-issue-keyed parents (the import recreates the Beads issues via `bd` writes first, then attaches blobs). The import order matters: Beads issues before Fizzy attachment rehydration.

## §H — Test strategy

### H.1 Unit tests

- `Storage::Entry.record(recordable_id: "fizzy-abc", ...)` (varchar): persists correctly.
- `Storage::Tracked#storage_attachments_for_records` resolves RichText parents when Card.id is varchar.
- Quota enforcement: `Storage::Tracked#storage_quota_check` rejects when `current + new > quota`.

### H.2 Integration tests

- POST `/cards/:id/attachments` (or the relevant attachment upload route) with a varchar `:id`: succeeds, charges the ledger.
- POST when over quota: 422 with quota-exceeded error.
- Description editor inline image upload: ActionText row + attachment created; Beads description plaintext does NOT contain attachment markup.

### H.3 Cleanup tests

- Hard-delete a Beads issue via stub CLI; poller `OrphanCleanupJob` runs; attachments and blobs are scheduled for purge after retention period.

## §I — Open questions deferred

1) Inline attachment fidelity (option (ii) round-trip via plaintext markers): V2 if usage warrants.
2) Per-board quotas (vs per-account only): V2; existing `Storage::Total.per_board` already supports the data, just needs UI + enforcement.
3) Attachment encryption at rest: V2.
4) CDN hand-off / external storage migration: V2.
5) Attachment-as-link UX (where Beads CLI users see "see attachment at <url>"): explicit V2 design round.
6) Bulk download (export all attachments for a card): V2.

## §J — Child bead inventory

Child beads (I-S7 implementation tasks) minted under epic `fizzy-yeu`. Smaller scope than S2-S6 since the FK widening (S1) and storage tracking layer (existing) are already in place.

| F.N | Bead | Title | Satisfies | Key dependencies |
|---|---|---|---|---|
| F.1 | `fizzy-a27` | Verify post-S1 ActiveStorage attachment + AT + Storage::Entry round-trips with varchar record_id | §A.2 | `fizzy-cjs`, `fizzy-0ic`, `fizzy-jzw` |
| F.2 | `fizzy-sgp` | Add `account.storage_quota_bytes` + warn/reject threshold config | §E.2 | none |
| F.3 | `fizzy-c3z` | Implement Storage::Tracked#storage_quota_check enforcement (422 on hard-reject) | §E.3 | `fizzy-sgp` |
| F.4 | `fizzy-dyw` | Inline-attachment strip in `ActionTextToPlaintext` serializer + render-side does NOT rebuild inline (per §C.2) | §C, §D | `fizzy-edq.4` (S6 plaintext serializer) |
| F.5 | `fizzy-9cx` | Update Account::DataTransfer export/import to handle varchar record_ids | §G.2 | `fizzy-cjs` |
| F.6 | `fizzy-nid` | OrphanCleanupJob + poller hook on Beads-issue hard-delete | §F.1 | `fizzy-edq.11` (S6 poller) |
| F.7 | `fizzy-8jc` | Account::Settings UI shows storage usage + quota progress bar (read-only data path) | §E.4 | `fizzy-sgp` |
| F.8 | `fizzy-60v` | Integration tests: upload over quota → 422; under quota → success; inline attachment behavior | §H.2 | `fizzy-c3z`, `fizzy-dyw` |

## §K — Validation checklist

Pre-lock checklist for S7:
- [x] §A documents post-S1 FK widening as the substrate; S7 verifies, does not re-migrate
- [x] §B explicit "Beads has no attachment model" — attachments are Fizzy-only
- [x] §C inline-attachment strip-on-write decision (option i) with rationale + V1 UX consequence + V2 fallback noted
- [x] §D comment attachments mirror §C with the S6 append-only constraint accounted for
- [x] §E quota model builds on existing Storage layer; introduces account.storage_quota_bytes config + warn/reject thresholds
- [x] §F orphan cleanup uses existing AR cascade + Storage::Entry.suppressing_recording for ledger correctness
- [x] §G import/export round-trip update is small (serialization key handling)
- [x] §H test strategy covers unit + integration + cleanup
- [x] §J child beads minted under fizzy-yeu with cross-spec deps to S1 (cjs/0ic/jzw) and S6 (edq.4 + edq.11)
- [ ] `[CLAUDE→CODEX S7 v1 ready]` sent + peer review complete
- [ ] `[FROM→TO S7: agreed]` 3-of-3 lock
