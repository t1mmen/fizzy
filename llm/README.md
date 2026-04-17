# Claude ↔ Codex Collaboration Protocol

This directory (`llm/`) is the shared workspace for the two AI agents working on Fizzy:

- **Claude** — tmux session `fizzy-claude`
- **Codex** — tmux session `fizzy-codex` (gpt-5.2 high)

Timm (`timm@timely.com`) is the human in the loop. He hands work to either of us; we coordinate the rest.

## Channels

### 1. Direct messaging — tmux send-keys

**See `skills/tmux-dispatch.md` for the strict protocol.** Three sequential calls (message, sleep, Enter), never chained, always followed by capture-pane verification. Forgetting Enter causes silent stalls — both sides idle while the message rots in the receiver's input buffer.

Quick reminder:

```bash
# Call 1
tmux send-keys -t <peer-session> "[FROM→TO] message body"
# Call 2 (separate, after Call 1 returns)
sleep 4 && tmux send-keys -t <peer-session> Enter
# Call 3 (verify)
tmux capture-pane -t <peer-session> -p -S -30 | tail -20
```

Look for `• Working` or `• Thinking` timer in the capture; absence = message stuck. Sign every message with `[FROM→TO]` envelope.

### 2. Append-only log — `LOG.md`

Every direct message also gets appended to `llm/LOG.md` so we have a durable record that survives context compaction. Format:

```
## 2026-04-17 11:23 CLAUDE→CODEX
<body>

---
```

Either side can `grep llm/LOG.md` to recover context after a clear/compact.

**Who writes**: the **sender** appends their own message to `LOG.md`. Receivers do **not** re-append the message they got — only their own reply (ACK / NACK / response) goes in.

### 3. Per-agent state files

- `llm/claude-state.md` — what Claude is working on right now, blockers, open questions for Codex
- `llm/codex-state.md` — same, for Codex

(Named `*-state.md` instead of `claude.md` / `codex.md` to avoid clashing with Claude Code's auto-loaded `CLAUDE.md` on case-insensitive filesystems.)

Update yours whenever you claim/finish a beads issue or change focus. The other agent reads it to know what's safe to touch.

### 4. Per-task design notes

- `llm/notes/<bead-id>.md` — design decisions, sketches, scratch work for a specific beads issue

Either of us writes; both read. Reference these in beads issues with `bd update <id> --notes "see llm/notes/<id>.md"`.

## Task tracking

Beads is canonical (`bd ready`, `bd update <id> --claim`, `bd close <id>`). Whoever claims a beads issue owns it end-to-end.

- **Hand off** = `bd update <id> --assignee=<peer>` + tmux ping + update your state file
- **Block on peer** = `bd update <id> --notes "blocked on <reason>, pinged <peer>"` + tmux ping

## File-edit coordination

To avoid stepping on each other:

1. If your beads issue clearly owns a file, just edit it.
2. If a file might be touched by both of us in parallel, ping first: `[CLAUDE→CODEX] Touching app/models/card.rb for bd-XYZ — clear?`
3. Wait for an ACK before editing.

## Acknowledgment protocol

- Messages requiring action → reply with `[FROM→TO ACK] <plan or ETA>` within one cycle
- Pure FYI messages → no ACK needed
- If you can't act, reply with `[FROM→TO NACK] <reason>` so the sender can re-route

## Pane inspection

When checking on each other's pane (status, debugging), use:

```bash
tmux capture-pane -t <session> -p -S -30 | tail -20
```

Minimum 20 lines — shorter captures hide working state.

## Session-close

Both of us follow the project's session-close rules in `AGENTS.md`: file remaining work as beads issues, run quality gates, push to remote. Whoever finishes last is responsible for the final `git push`.
