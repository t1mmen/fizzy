# P8 — Events two-way sync (Fizzy ↔ Beads)

**Status**: drafting (P8 round in flight)  
**Bead**: `fizzy-bcr`  
**Drafter**: `fizzy-codex`  
**Reviewers**: `fizzy-claude` (peer), `fizzy-gemini` (third-lens)  
**Brief**: `llm/notes/p8-brief.md`

This decision doc closes Q-S-005 (webhook triggers for bd CLI changes), Q-S-021 (canonical events log), and Q-S-022 (webhook V1 survival posture). It builds on P3 (hybrid data path: SQL reads + bd CLI writes), P5 (actor attribution via `bd --actor`), and P6 (lifecycle adapter emits bd mutations).

---

## §A — Ground truth: current event systems (Fizzy + Beads)

### A.1 Fizzy `Event` model + usage (to verify)

TODO: summarize:
- What writes `events` today (callbacks? controllers? services?)
- How events are rendered (activity feed)
- How events drive: notifications, webhooks, audit, search
- How `particulars` is structured

### A.2 Fizzy `Webhook` model + delivery pipeline (to verify)

TODO: summarize:
- What triggers a delivery
- Delivery payload shape / event types
- Retry semantics

### A.3 Beads `events` table (to verify)

TODO: capture DDL + key columns (actor, issue_id, action/type, created_at, metadata).

---

## §B — The problem statement (why events sync matters)

### B.1 The asymmetry introduced by P3 (bd CLI writes)

In the fork, writes to task state happen by shelling out to `bd` CLI. That means:
- Beads `events` records the change, but Fizzy may not.
- Fizzy webhooks/notifications/activity feed may not fire if they depend on Fizzy `Event` creation hooks.

### B.2 What “two-way sync” means in v1

Define explicitly:
- Fizzy → Beads: every state mutation initiated in Fizzy produces a Beads event (already true via `bd`)
- Beads → Fizzy: changes that happen outside Fizzy (direct `bd` use, integrations) should appear in Fizzy UI and trigger any configured “activity/webhook” mechanisms we keep in v1

---

## §C — Canonical events log decision (Q-S-021)

### C.1 Options

TODO: list candidate choices:
- (a) Canonical = Beads events; Fizzy events becomes a projection/mirror (or is bypassed)
- (b) Canonical = Fizzy events; Beads events treated as internal (not realistic if `bd` is SoT)
- (c) Hybrid: Canonical = Beads for issue state; Fizzy for non-issue domain events

### C.2 Decision

TODO: pick one and justify.

---

## §D — Beads → Fizzy ingestion strategy (fix Q-S-005)

### D.1 Requirements

TODO:
- No missed events (idempotent)
- Resilient to restarts
- Low operational complexity for single-tenant
- Does not require beads schema changes

### D.2 Candidate mechanisms

TODO:
- (a) Poller job in Rails: tail Beads events table, write mirrored Fizzy Event rows, and optionally enqueue webhook deliveries
- (b) Direct bd hook: post-write hook triggers Rails endpoint (out-of-scope, likely v2)
- (c) Dolt commit tailing (treat each commit as change batch)

### D.3 Decision

TODO: choose ingestion approach and define:
- cursor storage (where store “last processed beads event id”)
- idempotency key (beads_event_id)
- ordering guarantees
- backfill behavior

---

## §E — Webhooks posture (Q-S-022)

### E.1 V1 posture choice

TODO: confirm if webhooks:
- (a) are out of scope for V1 (defer entirely)
- (b) survive only for Fizzy-initiated changes (not for external bd writes)
- (c) survive for all changes via Beads→Fizzy ingestion job

### E.2 Recommendation + rationale

TODO.

---

## §F — Activity feed / timeline posture (UI impact)

TODO:
- if canonical events are beads events, how does UI read them?
- is a mirrored Fizzy Event row required to keep UI stable?

---

## §G — Failure modes + mitigations

TODO list:
- polling lag
- duplicate events
- cursor corruption
- bd history compaction / restore
- actor missing / ambiguous identity mapping

---

## §H — Resolved Q-S items (links back to P1)

TODO: mark Q-S-005/021/022 with explicit answers + backlinks.

---

## §I — New questions for spec rounds (if any)

TODO: list Q-S follow-ups with ownership (spec rounds) and why.

---

## §J — Validation checklist (pre-lock)

- [ ] Ground truth extracted from Fizzy code for Event/Webhook models + delivery
- [ ] Beads `events` DDL captured with example rows for common mutations
- [ ] Canonical log decision made; consequences stated
- [ ] Ingestion strategy concrete (cursor/idempotency/ordering)
- [ ] Webhook V1 posture explicit; no “silent missing triggers”
- [ ] Q-S-005/021/022 marked ANSWERED with pointers

