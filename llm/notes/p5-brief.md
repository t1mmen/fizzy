# Brief — P5-auth-bridging — Identity/AccessToken ↔ Beads actor + User simplification

> **STATUS**: skeleton (drafted in advance; finalize after P3/P4 land). Bead created at P5 dispatch time.

## Identity
- Round / bead: `P5-auth-bridging` / `fizzy-XXX` (created at dispatch)
- Drafter / owner: `fizzy-claude` (alternation: P1 mixed, P2 Codex, P3 Claude, P4 Codex → P5 Claude)
- Review target: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)

## Context (inputs)
- `llm/notes/p1-foundational-gap-inventory.md` §E.3 — Q-S-004 (bearer-token + actor), Q-S-006a (multi-user team survives), Q-S-008 (User simplification)
- `llm/notes/p3-data-path-decision.md` (locked) — chosen data-path determines how `BD_ACTOR` env var gets set (per-request shell-out vs persistent connection)
- `app/controllers/concerns/authentication.rb`, `app/controllers/concerns/request_forgery_protection.rb`, `app/models/identity/access_token.rb`, `app/models/identity.rb`, `app/models/user.rb`
- `app/models/session.rb`, `app/models/magic_link.rb`
- Beads `actor` semantics (string per commit, no auth model in beads itself)
- `app/models/concerns/account_tenanted.rb` (Solid Queue + Current.account)

## Objective (one sentence)
Decide and document how Fizzy authenticates writes to Beads (mapping Fizzy identities to `BD_ACTOR`), how the bearer-token JSON API surface evolves, and what the simplified `User` model looks like in single-tenant — closing Q-S-004, Q-S-006a, and Q-S-008.

## Acceptance criteria (verifiable)
- [ ] File `llm/notes/p5-auth-bridging.md` with sections:
  - **§A — `BD_ACTOR` resolution**: how Fizzy resolves the current Identity/User → `BD_ACTOR` string for every `bd` invocation. Include: web request path (Identity from Session), API request path (Identity from AccessToken), background-job path (Identity from `AccountTenanted` concern's serialized Current). Decision: per-call env var vs ENV-fixed-with-application-side audit.
  - **§B — Bearer-token JSON API future**: confirm/refute that the existing `Identity::AccessToken` + `bearer_token_authenticatable_request?` machinery survives intact. Document the new beads-backed endpoints that will live under it (e.g., POST /cards via beads write).
  - **§C — User model simplification**: concrete decision on Q-S-008 (a) keep User intact; (b) inline name+role into Identity; (c) deprecate `user_id` in favor of `identity_id` everywhere. With migration plan if (b) or (c).
  - **§D — Roles in single-tenant**: how the `User.role` enum (member/owner/system) is interpreted when there is one Account. Owner = install admin? Member = team member? System = automation account (bot user for `bd` writes that don't have a human actor)?
  - **§E — System-user mechanics**: every install needs a "system" User for writes that have no human (recurring jobs, webhooks). Document creation + `BD_ACTOR=fizzy-system@<install>` convention.
  - **§F — CSRF interaction**: confirm `RequestForgeryProtection#allowed_api_request?` (Sec-Fetch-Site nil + format.json) survives. Document any v1 changes.
  - **§G — Resolved Q-S items**: marks Q-S-004, Q-S-006a, Q-S-008 ANSWERED.
  - **§H — Open questions**: any new Q-S items.
- [ ] Cross-link from p1 inventory's Q-S entries.
- [ ] No code changes; configuration / convention sketches OK.
- [ ] Ratified 3-of-3 by `[P5: agreed]`.

## Allowed paths (scope boundary)
- **Writable**: `llm/notes/p5-*.md`, `llm/LOG.md`, `llm/claude-state.md`, `llm/notes/p1-foundational-gap-inventory.md` (Q-S markers only).
- **Read-only**: app code, all auth concerns, P3/P4 decision docs.
- **Excluded**: any code change, any auth implementation.

## Out of scope (explicit)
- Implementing the BD_ACTOR plumbing (Implementation round).
- Adding new auth flows (e.g., OAuth, SSO) — out of v1 unless CEO redirects.
- Lifecycle adapter (P6).
- Multi-assignee gap (P7).
- Events sync (P8).

## Sources of truth (anchors)
- `app/controllers/concerns/authentication.rb`
- `app/controllers/concerns/request_forgery_protection.rb`
- `app/models/identity.rb`, `app/models/identity/access_token.rb`
- `app/models/user.rb` (role enum)
- `app/models/session.rb`, `app/models/magic_link.rb`
- `app/jobs/concerns/account_tenanted.rb` (Current.account propagation pattern)
- `Beads` source: `BD_ACTOR` env var convention
- `llm/notes/p3-data-path-decision.md` — informs how `BD_ACTOR` is plumbed in adapter

## Verification plan
### Worker-verification
- For each role transition (web request, API request, background job), trace through code and confirm where `BD_ACTOR` would be set/exported.
- Validate that `Identity::AccessToken.allows?(method)` still returns the right answers for the new beads-backed endpoints (no auth regression).

### Operator-verification
- CEO can read p5-auth-bridging.md and follow §A → §E to understand who writes to Beads as whom, in every code path.

## Output location (artifact)
- `llm/notes/p5-auth-bridging.md`
- Updated `llm/notes/p1-foundational-gap-inventory.md` (Q-S markers)
- Bead `fizzy-XXX` notes/close
- LOG entries

## Definition of done
- All AC bullets satisfied
- 3-of-3 `[P5: agreed]`
- `bd close fizzy-XXX`
- Commit + push to `dev`
- Handoff entry in LOG: "P5 locked; opens P6 — proposed scope: lifecycle adapter deep-dive (Q-S-013/014/015/016 status, closure, postpone, entropy)"
