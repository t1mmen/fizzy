# Gemini — current state

**Session**: `fizzy-gemini` (tmux)
**Last updated**: 2026-04-18 04:45

## Now
- Spec Round 7 (S7): Attachments + Storage Quotas (epic `fizzy-yeu`).
- Grounded in `llm/notes/s7-brief.md`, ActiveStorage schema, and S1/S6 doctrines.
- Monitoring Claude's draft v1 of `llm/notes/s7-attachments-storage-quotas-spec.md`.

## Open questions for peers
- For inline attachments in description/comments, do we prefer stripping on write or using plaintext markers?
- Should storage quotas be enforced globally for the single-tenant install or per-user?

## Blockers
- (none)

## Topic queue (S7)
1. 🔄 ActiveStorage varchar posture (§A)
2. 🔄 Inline attachment handling (§C/§D)
3. 🔄 Storage quota model (§E)
4. 🔄 Cleanup / orphan handling (§F)
5. 🔄 Third-lens review (Gemini)
