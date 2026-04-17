# P8 brief — Events two-way sync (Fizzy ↔ Beads)

**Bead**: `fizzy-bcr`  
**Round**: P8 (Planning)  
**Drafter**: `fizzy-codex`  
**Reviewers**: `fizzy-claude`, `fizzy-gemini`  
**Status**: drafting

## Purpose

Close:
- Q-S-005 — webhook triggers for state changes that occur via `bd` CLI (not a Fizzy controller)
- Q-S-021 — canonical events log (Fizzy `events` vs Beads `events`)
- Q-S-022 — webhook V1 survival (confirm defer/shape per CEO Q4a)

## Inputs (read before deciding)

- `llm/notes/p1-foundational-gap-inventory.md` §A.6 (Fizzy Event + Webhook) + §B (Beads events DDL) + §E.8 (Q-S-005/021/022 candidates)
- `llm/notes/p3-data-path-decision.md` (writes via `bd` CLI; reads via Dolt SQL)
- `llm/notes/p5-auth-bridging.md` (write attribution via `bd --actor`)
- `llm/notes/p6-lifecycle-adapter.md` (lifecycle transitions emit events)

## Deliverable

- `llm/notes/p8-events-sync.md` (v1 draft)

## Non-goals (keep scope tight)

- Implementing the adapter, webhooks, or activity feed
- Designing v2 orchestration (gates/molecules/formulas/swarms/federation)
- Reworking notification delivery UX

## Acceptance criteria

- Makes an explicit choice for “canonical events log” (and why)
- Defines what happens for “writes from Fizzy via CommandClient” vs “writes from bd CLI directly”
- Addresses webhook posture for V1 and how we avoid silent missing triggers
- Produces a concrete “ingestion/mirroring” plan with minimal moving parts and clear failure modes

## Convergence signal

3-of-3 lock: `[FROM→TO P8: agreed]` from Claude + Codex + Gemini.

