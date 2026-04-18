# tmux-dispatch — sending messages to a peer agent session

**Applies to**: any agent in `fizzy-claude`, `fizzy-codex`, `fizzy-gemini` sending a message to another agent's tmux session.

**Why this skill exists**: a missed `Enter` leaves the message paste-buffered in the receiver's input box. The sender thinks the message was delivered; the receiver never sees it. Both sides idle, no work happens, the program stalls. This has happened — see `llm/LOG.md` 2026-04-17 protocol-failure entry.

---

## The strict protocol — three SEQUENTIAL calls, never parallel, never chained

```
1.  tmux send-keys -t <peer-session> '<message body>'
2.  sleep 4
3.  tmux send-keys -t <peer-session> Enter
```

Each is a **separate** Bash invocation. Steps 2 and 3 may be combined as `sleep 4 && tmux send-keys -t <peer-session> Enter` in one call — but step 1 is **always** its own call, and steps 2-3 happen **after** step 1 completes.

**Forbidden patterns:**
- ❌ `tmux send-keys -t <peer> 'msg' Enter` — chains Enter into the same call. Enter can fire before the message buffer registers.
- ❌ `tmux send-keys -t <peer> 'msg' && tmux send-keys -t <peer> Enter` — no sleep, same race.
- ❌ Sending the message via Bash and forgetting the follow-up Enter — leaves the receiver staring at an unsubmitted paste buffer (the silent stall failure mode).
- ❌ Parallelizing the message-send Bash call with other tool calls and forgetting to schedule the Enter call afterward.

**Required pattern (literal):**

```bash
# Call 1 (sender):
tmux send-keys -t fizzy-codex '[CLAUDE→CODEX] message body here'

# Call 2 (sender, only after call 1 completes):
sleep 4 && tmux send-keys -t fizzy-codex Enter
```

## Mandatory verification — always capture afterward

After step 3, verify the receiver actually got the message:

```bash
tmux capture-pane -t <peer-session> -p -S -30 | tail -20
```

You are looking for one of:
- `• Working (Ns)` or `• Thinking (Ns)` timer line — receiver is processing
- The full message text rendered above the input box (not `[Pasted Content N chars]` placeholder)

If you see `[Pasted Content N chars]` or the receiver is still idle, **the message was not submitted**. Send Enter again as a separate call and re-capture.

## Why minimum 20-line capture

Captures of 3-5 lines look identical whether the receiver is idle, working, or errored — the prompt line is the same. Always 20+ lines minimum. For verbose receivers (Gemini), use `-S -50 | tail -30`.

## Special: long messages

Long messages may render in the receiver's input as `[Pasted Content N chars]` placeholder rather than inline text. This is normal for Codex. After Enter, the placeholder collapses and the full message renders above the prompt line. Verify by re-capturing post-Enter.

## Special: parallelizing the dispatch with other work

If you need to also write to `LOG.md` or update state files at the same time, you may parallelize the message-send (call 1) with the file-edit calls. **You may NOT skip call 2 (sleep + Enter)**. Schedule it as the next Bash call after the parallel batch returns.

## Cross-link: append to `LOG.md`

The sender ALSO appends the message to `llm/LOG.md` per the README protocol — that responsibility is separate from getting the message delivered. Both must happen for a complete dispatch.

---

## Failure mode log (so we don't repeat it)

- **2026-04-17 ~12:27 PDT**: Claude sent skills-path question to fizzy-codex via Bash send-keys, parallelized with `LOG.md` edit, but did NOT schedule the follow-up `sleep 4 && send-keys Enter` call. Codex sat idle with `[Pasted Content 1385 chars]` in its input buffer for several minutes. Caught by Timm. Recovery: separate Enter call, verified `Working (3s)` appeared. Lesson encoded above.

- **2026-04-17 ~13:50 PDT**: fizzy-codex sent `[RoE-7: agreed]` to fizzy-claude with a body containing escaped backticks (`\`skills/session-lifecycle.md\``) inside a double-quoted send-keys argument. The receiving zsh interpreted the backticks as command substitution and tried to execute the path → `zsh:1: permission denied: skills/session-lifecycle.md`. The send-keys call failed; Claude saw nothing arrive. Recovery: Codex retried without backticks and the message landed.

  **Lesson — escape rules for tmux send-keys message bodies:**
  - **Single quotes** around the message argument prevent ALL shell interpretation. Prefer them when the message contains no single quotes.
  - **Double quotes** around the message argument allow `$VAR`, `` `cmd` ``, `\"`, and `\\` interpretation by the shell that runs `tmux send-keys`. Backticks in message bodies become command substitution and fail.
  - If you must use double quotes, never put backticks in the body. Use single quotes around code paths or omit them entirely (skills/session-lifecycle.md reads fine without backticks in agent-to-agent prose).
  - Default: use single quotes for the message body, period.

- **2026-04-17 ~14:30 PDT**: fizzy-claude sent a P1 dispatch to fizzy-gemini whose body contained the substring `single-tenant!=single-user`. The exclamation mark triggered Gemini's **shell-mode toggle** — Gemini's prompt parser saw `!` as the shell-mode prefix, switched to shell mode, and pasted the rest of the message body into `bash -c '...'`, which then errored on unbalanced parens (`syntax error near unexpected token ')'`). Recovery: send `Escape` to fizzy-gemini to exit shell mode, rephrase the message without `!` (use `is NOT` / `is not the same as` instead of `!=`), resend.

  **Lesson — character triggers in receiver TUIs:**
  - Different agent TUIs have different reserved-character behaviors. Gemini in particular treats `!` as shell-mode trigger.
  - **Avoid in messages to Gemini**: `!`, `!=`, `! ` (space-after-bang). Spell it out: "is not", "does not equal", "differs from".
  - **Avoid in messages to Codex**: backticks (see prior failure mode).
  - **Avoid in messages to Claude**: (none confirmed yet — this section grows as new failure modes are discovered).
  - **Verification step**: after the 3-call protocol, the capture should show a `Thinking` / `Working` / `Reviewing` indicator AND a normal-mode prompt (`*`/`>`/`›`), NOT `!` (Gemini shell mode), NOT `[Pasted Content N chars]` lingering (Codex stuck paste), NOT a syntax-error block.

- **2026-04-18 ~early-AM PDT** (S1 v1 dispatch to Gemini): same Gemini shell-mode failure recurred on a message containing `(no backfill)` + several other parenthesized phrases — but with NO `!` in the message body. Bash errored on `unexpected token '('`. Recovery: `Escape` + resend without parens. **This indicates Gemini's shell-mode trigger is stickier than just `!`**: either parens themselves can trigger it, OR shell mode persisted from a prior dispatch and was never explicitly exited.

  **Strengthened lesson — defensive Gemini dispatch:**
  - Treat Gemini's shell mode as **sticky**. Even after an Esc, subsequent dispatches may re-trigger.
  - **Defensive pattern**: send `Escape` to fizzy-gemini immediately before EVERY dispatch (it's a no-op if already in normal mode). Cost: one extra send-keys; benefit: deterministic mode.
  - **Avoid in Gemini messages**: `!`, parens `(` and `)`, backticks. Use words: "and" / "with" instead of `(... and ...)`.
  - The `[FROM→TO]` envelope itself is fine; brackets `[` and `]` don't trigger shell mode. Only the body content matters.
  - When in doubt, keep Gemini messages short and use `+` or commas instead of parenthetical asides.
