# Brief — P3-data-path-decision — how Fizzy talks to Beads at runtime

> **STATUS**: skeleton (drafted in advance; finalize after P2 lands so we cite P2 evidence). Bead created at P3 dispatch time.

## Identity
- Round / bead: `P3-data-path-decision` / `fizzy-XXX` (created at dispatch)
- Drafter / owner: `fizzy-claude`
- Review target: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
- CEO ratification: not required (autonomous post-RoE)

## Context (inputs)
- `llm/notes/p1-foundational-gap-inventory.md` §E.1 — Q-S-001 (read path), Q-S-001a (write path), Q-S-002a (UUID→string FK migration cost)
- `llm/notes/p2-local-dev-grounding.md` (locked) — empirical proof of connection patterns
- `skills/local-dev.md` (locked) — confirmed local-dev shape
- `bin/p2-rails-dolt-probe.rb` and/or `bin/p2-rails-bd-probe.rb` (the proof scripts)
- P1 §C.4 — Card-as-issues mapping (depends on this decision)

## Objective (one sentence)
Decide and document the canonical data-path Fizzy uses to **read** and **write** Beads issues at runtime, including the adapter shape, trade-off analysis, and migration implications — closing Q-S-001, Q-S-001a, and Q-S-002a so the Spec phase can build on a settled foundation.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/p3-data-path-decision.md` exists with the following sections:
  - **§A — Decision**: one-paragraph statement of the chosen approach (CLI shell-out / Dolt SQL via Mysql2-Trilogy / Hybrid).
  - **§B — Evidence cited**: every claim references P2 proof script + verbatim output (no new empirical claims here).
  - **§C — Trade-off analysis**: explicit comparison across (1) latency, (2) write-side hook coverage (bd events/audit), (3) error handling/retries, (4) transactionality, (5) read-after-write consistency, (6) concurrent-writer safety, (7) operational cost (process forks vs connection pool), (8) failure mode for each path.
  - **§D — Adapter shape**: proposed Ruby module/class layout (e.g., `Fizzy::Beads::Adapter`, `Fizzy::Beads::IssueRepository`, `Fizzy::Beads::CommandClient`) with method signatures only (no implementation). Identifies clearly where the decision boundary lives.
  - **§E — Migration implications**: concrete plan for Q-S-002a (every Fizzy table with `card_id uuid` → `card_id varchar(255)`). Lists every affected column with file:line refs from p1 §A.
  - **§F — Resolved Q-S items**: explicitly marks Q-S-001, Q-S-001a, Q-S-002a as ANSWERED with link to the relevant section here.
  - **§G — Open questions for downstream rounds**: any new Q-S items that emerged.
- [ ] No code changes (planning round; Adapter shape is sketch only).
- [ ] Cross-link from p1 inventory's Q-S-001/001a/002a entries to p3 §A.
- [ ] Ratified 3-of-3 by `[P3: agreed]` signals.

## Allowed paths (scope boundary)
- **Writable**: `llm/notes/p3-*.md`, `llm/LOG.md`, `llm/claude-state.md`, `llm/notes/p1-foundational-gap-inventory.md` (only to update Q-S-001/001a/002a "ANSWERED" markers).
- **Read-only**: app code, models, controllers, P2 proof scripts.
- **Excluded**: any code change, any adapter implementation, any migration code.

## Out of scope (explicit)
- Implementing the adapter (that is an Implementation round, post-spec).
- Running the migrations (Implementation).
- Choosing how the kanban board projects onto data (P4).
- Choosing auth bridging (P5).
- Choosing lifecycle adapter (P6).

## Sources of truth (anchors)
- `llm/notes/p2-local-dev-grounding.md` (P2 evidence — locked before P3 starts)
- `llm/notes/p1-foundational-gap-inventory.md` §B (Beads schema), §C.4 (Card mapping), §E.1 (data-path Q-S items)
- `Gemfile` (current Trilogy adapter, schema:31 for `mysql2` / `trilogy` gems)
- `config/database.yml` (current Rails DB config)
- `bd context --json`, `bd dolt status` (Dolt server location/port)

## Verification plan
### Worker-verification (agents run)
- Re-run P2 proof scripts against current state, confirm outputs match what's quoted in p3 §B.
- For the chosen path, measure: round-trip latency for `bd list` equivalent (prove < 100ms is achievable for UI-blocking call).
- For the chosen path, run a write + immediately read; confirm the write is visible.

### Operator-verification (CEO, optional)
- CEO can read p3-data-path-decision.md and follow §A → §C → §E to understand and assess the trade-off.

## Output location (artifact)
- `llm/notes/p3-data-path-decision.md` (new — the decision)
- Updated `llm/notes/p1-foundational-gap-inventory.md` (Q-S markers)
- Bead `fizzy-XXX` notes/close
- LOG entries

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[P3: agreed]`
- `bd close fizzy-XXX`
- Commit + push to `dev`
- Handoff entry in LOG: "P3 locked; opens P4 — proposed scope: UI projection deep-dive (Q-S-003/009/010 board+column projection onto beads labels/status)"
