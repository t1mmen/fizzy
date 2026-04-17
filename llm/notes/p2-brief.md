# Brief — P2-local-dev-grounding — bd+Dolt+Rails connectivity

## Identity
- Round / bead: `P2-local-dev-grounding` / `fizzy-3zi`
- Drafter / owner: `fizzy-codex`
- Review target: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)
- CEO ratification: not required (per Q8a, autonomous post-RoE)

## Context (inputs)
- `llm/notes/p1-foundational-gap-inventory.md` (locked) — especially §B (Beads schema, Dolt server mode confirmed) and §E.1 (Q-S-001 data-path candidates: CLI shell-out / Dolt SQL / hybrid)
- `llm/notes/r0-dolt-cleanup.md` — Dolt canonical at `.beads/dolt/fizzy`, server running on a random port (was 53365, then 54309 — re-discover at session time via `bd dolt status`)
- `bin/setup`, `bin/dev`, `config/database.yml`, `Gemfile` (current Rails MySQL via Trilogy)
- AGENTS.md — dev URL `http://app.fizzy.localhost:3006`, login `david@example.com`

## Objective (one sentence)
Stand up a working local-dev configuration where `bin/dev` runs Fizzy AND the same process can reach Beads+Dolt — proving at least one data-path option (CLI shell-out and/or Dolt SQL via Mysql2/Trilogy) — and document the replicable setup at `skills/local-dev.md`.

## Acceptance criteria (verifiable)
- [ ] `bin/setup` succeeds in a clean (or near-clean) state and the steps are documented.
- [ ] `bin/dev` boots Fizzy at `http://app.fizzy.localhost:3006` (verify with `curl -I`).
- [ ] Dolt server is up locally; record the running port + path; verify with `bd context --json` and a `dolt sql` query against `.beads/dolt/fizzy`.
- [ ] **Connection proof**: at least ONE of:
  - (A) `bin/rails runner` script that queries the Dolt server via Mysql2/Trilogy and returns at least one Beads issue (file + path + verbatim output captured).
  - (B) `bin/rails runner` script that shells out to `bd list --json` and parses the result (file + verbatim output captured).
  - Both ideal; one is the minimum bar.
- [ ] `skills/local-dev.md` documents: prerequisites, `bin/setup` flow, `bd init` posture (we already have `.beads/`, no need to re-init), Dolt server start/stop, magic-link login flow, the connection-pattern proof from above.
- [ ] `llm/notes/p2-local-dev-grounding.md` captures: every command run, every output, every gotcha, plus a "feeds into P3" section listing what Q-S-001 evidence we now have.
- [ ] No code changes to Fizzy production paths (config files for local-only dev are OK; new `bin/` scripts for the connection proof are OK).
- [ ] Ratified 3-of-3 by `[P2: agreed]` signals.

## Allowed paths (scope boundary)
- **Writable**: `skills/local-dev.md` (new), `llm/notes/p2-*.md`, `llm/LOG.md`, `llm/codex-state.md`, `bin/p2-*` scripts (proof scripts), config-file edits ONLY if local-dev-only (e.g. additional database env in `config/database.yml` for the dolt connection — gated to development env).
- **Read-only**: app code, models, controllers, lib (no logic changes).
- **Excluded**: Beads schema (immutable per RoE-4), production config, Kamal config.

## Out of scope (explicit)
- Choosing between CLI vs SQL data-path (that is **P3**, after empirical evidence here).
- Building any adapter layer / Card model rewiring (that is implementation, post-spec).
- Fixing `bd dolt push` to remote (already known broken; separate plumbing round).
- Adding Playwright/Chromia (separate Spec + Implementation work).

## Sources of truth (anchors)
- `bin/setup`, `bin/dev`, `config/ci.rb`
- `config/database.yml`
- `bd context --json`, `bd dolt status`
- `.beads/dolt/fizzy/.dolt/sql-server.info` (running port file)
- `.beads/metadata.json`
- AGENTS.md (dev URL + login)

## Verification plan
### Worker-verification (agents run)
- `bin/setup --skip-server`, capture output
- `bd context --json`, `bd dolt status`
- `dolt sql -q "select count(*) from issues"` inside `.beads/dolt/fizzy/`
- The connection-proof scripts (run + capture verbatim output)
- `curl -I http://app.fizzy.localhost:3006/` after `bin/dev` is up

### Operator-verification (CEO, optional)
- CEO can clone fresh, follow `skills/local-dev.md`, and reach the same state.

## Output location (artifact)
- `skills/local-dev.md` (new — the canonical procedure)
- `llm/notes/p2-local-dev-grounding.md` (new — research findings, command outputs, P3 feed-forward)
- `bin/p2-rails-dolt-probe.rb` and/or `bin/p2-rails-bd-probe.rb` (new — the proof scripts)
- Bead `fizzy-3zi` notes/close
- LOG entries

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[P2: agreed]`
- `bd close fizzy-3zi`
- Commit + push to `dev`
- Handoff entry in LOG: "P2 locked; opens P3 — proposed scope: data-path decision (Q-S-001/Q-S-001a) using P2 evidence"
