# S6 — Rich Text + Comments Spec (Beads plaintext SoT; Fizzy ActionText + MySQL mirror)

**Status**: v1 draft in progress
**Bead**: `fizzy-edq` (epic)
**Drafter**: `fizzy-codex`
**Reviewers**: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/s6-brief.md`

This spec defines how Fizzy’s rich-text surfaces (Card description + Comment body) are driven by the Beads immutable schema:

- Beads is source-of-truth for **issue description** and **comment text** (plaintext).
- Fizzy persists **derived caches** for UI rendering and indexing:
  - `action_text_rich_texts` rows for Card.description + Comment.body (derived HTML).
  - `comments` rows as a MySQL mirror of Beads comments (Beads is canonical).
  - `mentions` rows derived from Beads comment text (for notifications/watch behavior), computed on the mirror/poller side.

This round also decides the deferred S1 question: `comments.id` is widened to `varchar(255)` so Fizzy can use Beads `comments.id` directly.

---

## §A — Card description canonical storage + derived render cache

## §B — Comments mirror schema + `comments.id` decision

## §C — CommandClient comment methods + argv (and unsupported operations)

## §D — Comment poller contract (S9-owned mechanism; S6 specifies WHAT mirrors)

## §E — Cards::CommentsController rewire + optimistic UI posture

## §F — Mention parsing pipeline (poller-side; supports direct bd writes)

## §G — Card description edit flow (UI → Beads plaintext → derived ActionText cache)

## §H — Test strategy (unit + integration; poller tests deferred to S9)

## §I — Open questions / deferrals

## §J — Child bead inventory (maps each AC to an impl bead)

## §K — Validation checklist

