# P5 — Auth Bridging: Identity ↔ bd `--actor` + User simplification

**Status**: locked v2 (recovered after working-tree loss; content verified against my edit history + Codex's review summary + Gemini's ratify)
**Bead**: `fizzy-3m5`
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer, agreed), `fizzy-gemini` (third-lens, ratify-confirm)
**Brief**: see `llm/notes/p5-brief.md`

This decision doc closes Q-S-004 (bd actor resolution + bearer-token API future), Q-S-006a (multi-user team in single-tenant), Q-S-008 (User model simplification), Q-S-046 (system-user Identity row). It builds on P3's data-path decision (CommandClient is the only place we shell out to `bd`, so it's also the only place that needs to set the actor).

---

## §A — Actor resolution across all paths

### A.1 Decision

**Resolve the actor to the email of `Current.identity` (or the system-user email if none) at the moment of the `bd` invocation, and pass it as the explicit `--actor <email>` flag on every `bd` subprocess invocation. Do NOT use the `BEADS_ACTOR` environment variable; do NOT mutate the Rails-process global ENV.**

Concretely, the `Fizzy::Beads::CommandClient` (P3 §D) takes `actor:` in its constructor; that string becomes `--actor <email>` prepended to every subprocess argv. Resolution happens at controller / job entry, not deep in the adapter.

**Why `--actor` flag instead of `BEADS_ACTOR` env**:

- `bd --help` confirms the precedence is `--actor` → `$BEADS_ACTOR` → `git user.name` → `$USER`. The flag is the most explicit and unambiguous.
- Passing via env requires per-call env-hash plumbing through `Open3.capture3`. Passing via argv is one extra string.
- Env-based actor risks accidentally bleeding into a subshell or being inherited by an unrelated child process. Argv is scoped exactly to the one invocation.

### A.2 Resolution per code path (CURRENT vs TARGET)

CURRENT vs TARGET state matters here. Today only `Current.account` propagates through Solid Queue jobs (via `app/jobs/concerns/account_tenanted.rb`). `Current.identity` does NOT propagate yet — adding that propagation is its own change tracked as Q-S-045 in §H. Until Q-S-045 lands, jobs that need a human-originator actor must carry the actor via an explicit job arg.

| Code path | Today (CURRENT) | Target (after Q-S-045) | Resolved `--actor <email>` |
|---|---|---|---|
| **Web request (cookie session)** | `Authentication#resume_session` sets `Current.session`; `Current.identity = session.identity` works today | unchanged | `Current.identity.email_address` |
| **JSON API request (bearer token)** | `Authentication#authenticate_by_bearer_token` resolves `Identity.find_by_permissable_access_token(...)`; sets `Current.identity` works today | unchanged | `Current.identity.email_address` |
| **Background job triggered by a human** | Today: only `Current.account` is in job data; identity is NOT propagated. The job must accept an `actor_email:` arg (or similar) explicitly. | After Q-S-045: a `CurrentTenanted` / `IdentityTenanted` concern propagates `Current.identity` alongside Account; jobs auto-restore both. | `Current.identity.email_address` (today: from explicit job arg; target: from restored Current) |
| **Recurring job (no triggering user)** | No human originator; no `Current.identity` to propagate | Same | system-user email (see §E) |
| **Webhook callback (inbound — V2+)** | Not in V1 | Not in V1 | TBD (Q-S-043) |

### A.3 Plumbing pattern (sketch)

```ruby
# In any controller / job:
client = Fizzy::Beads::CommandClient.for(Current.identity)
client.create_issue(title: "...", description: "...", ...)

# Class-level helper:
module Fizzy
  module Beads
    class CommandClient
      def self.for(identity)
        actor = (identity&.email_address) || SystemUser.email
        new(actor: actor)
      end

      def initialize(actor:, bd_bin: "bd")
        @actor  = actor
        @bd_bin = bd_bin
      end

      private

      def invoke!(argv)
        # Prepend explicit --actor flag; never rely on env-var resolution.
        full_argv = [@bd_bin, "--actor", @actor, *argv]
        stdout, stderr, status = Open3.capture3(*full_argv)
        raise CommandError.new(full_argv, status, stderr) unless status.success?
        stdout
      end
    end
  end
end
```

Note the `--actor <email>` argv prefix on every invocation. This supersedes the P3 §D sketch which (correctly for that round) showed the env-hash form; P5 finalizes the actor-passing as the explicit flag form.

### A.4 Why per-call argv flag, not Rails-process ENV

If we set `ENV["BEADS_ACTOR"] = ...` at the start of every request, concurrent requests in different threads would race. Even per-call env (Open3 env hash) is more error-prone than the explicit `--actor` flag because env propagates to any nested process. The `--actor` argv form is scoped exactly to the one bd invocation.

### A.5 Why Identity (not User) is the canonical actor

`Identity.email_address` is globally unique and stable across the lifetime of an install. `User` is per-tenant in upstream Fizzy and remains per-install in the fork (see §C). Beads' `actor` string is best matched to a stable, unambiguous identifier — Identity wins.

---

## §B — Bearer-token JSON API future

### B.1 Decision

**The existing bearer-token JSON API surface (`Identity::AccessToken` + `bearer_token_authenticatable_request?` + `RequestForgeryProtection#allowed_api_request?`) survives intact in the fork. New beads-backed endpoints live under it without modification.**

### B.2 Why it survives

P1 §D-7 evidence confirmed the surface is real and well-defined:
- `app/controllers/concerns/authentication.rb:58–73` gates bearer-token auth on JSON requests
- `app/models/identity/access_token.rb:5–7` enums `permission` (read/write) and `allows?(method)` gates write access
- `app/controllers/concerns/request_forgery_protection.rb:10–14` allows JSON requests when `Sec-Fetch-Site` is absent (non-browser clients)

These mechanics are orthogonal to the data-path change (P3). Adding beads-backed endpoints (e.g., `POST /cards` that creates a Beads issue) just plugs into the existing controller pattern.

### B.3 New endpoints expected in V1

Endpoints that need to exist for the kanban UI + JSON API parity:

- `GET /cards` — list (Beads SQL read; `Identity::AccessToken#allows?("GET")` → always allowed)
- `GET /cards/:id` — show
- `POST /cards` — create (CommandClient write; permission check requires `write`)
- `PATCH /cards/:id` — update
- `DELETE /cards/:id` — close (or move to `:not_now`)
- `POST /cards/:id/dependencies` — add dependency
- `POST /cards/:id/comments` — comment

All inherit the bearer-token mechanism. Spec round S-controllers-api owns the actual route and controller list.

### B.4 What does NOT change

- No new auth flow (no OAuth/SSO in V1 — out of scope per CEO Q4a)
- No new permission level (`read` and `write` enum stays as-is)
- No new token format (existing `has_secure_token` mechanism is fine)

---

## §C — User model simplification

### C.1 Decision

**Keep the `User` model intact** as a per-install team-member entity (Q-S-006a + Q-S-008(a) candidate). `account_id` becomes a constant FK to the singleton account (per P1 §C.1 retag); name + role + active flag stay; `identity_id` remains the link to the global Identity.

### C.2 Why not (b) inline name+role into Identity

- `Identity` is global (one row per email across the world); we don't want install-specific role/name on it.
- Multi-install scenarios (a contributor with the same email working on two Fizzy/Beads forks) need separate roles/names per install.
- Keeping `User` preserves the existing Fizzy code surface (60+ models join via `user_id`); collapsing now is unnecessary churn.

### C.3 Why not (c) deprecate `user_id` in favor of `identity_id`

- Same churn-without-benefit argument.
- Beads uses `actor` (string), not a User FK. So bidirectional sync stays via Identity.email_address (see §A.5).

### C.4 What changes operationally in single-tenant

| Before (upstream multi-tenant) | After (fork single-tenant) |
|---|---|
| Identity in N Accounts → N User rows | Identity in 1 install → 1 User row |
| `User.account_id` varies | `User.account_id = Account.singleton.id` always |
| `User.role` enum: `member`/`owner`/`system` | Same — still meaningful (see §D) |
| `User.identity_id` may be nil for orphaned/deactivated users | Same |

No User-model code changes. Only the `account_id` constraint becomes effectively trivial.

---

## §D — Roles in single-tenant

### D.1 Decision

The existing `User.role` enum (`member` / `owner` / `system`) is interpreted as:

| Role | Meaning in single-tenant | Privilege |
|---|---|---|
| `owner` | Install admin (the user who set up the install; can invite/remove others, change install settings, delete account) | All UI actions; all API actions; all `bd` write actions; can delete users; can run `kamal deploy` (CEO only per Q8a — but the role grants intra-app authority) |
| `member` | Regular team member | Can create/edit/close their own issues; can edit shared boards per `Access` ACL; can use the bearer-token JSON API per `Identity::AccessToken` permissions |
| `system` | Bot / automation account (one per install, auto-created) | Used by recurring jobs and any non-human writer (see §E) |

### D.2 Per-board ACL still applies

`Access` (board-level ACL with `involvement` enum: `access_only` / `watching`) survives unchanged. `User.role` is install-level; `Access` is per-board. No change needed; both layers apply.

### D.3 Owner-on-install bootstrapping

The first User created during install setup gets `role: owner` automatically. Subsequent invites default to `role: member`. Spec round S-install-setup owns the actual install bootstrap UI.

---

## §E — System-user mechanics

### E.1 Decision

**Every install auto-creates a singleton `Identity` with `email_address: "system@<install-hostname>"` (e.g., `system@app.fizzy.localhost`) AND a singleton `User` with `role: system`, `name: "Fizzy System"`, `identity_id: <synthetic-identity-id>`.** This Identity/User pair is the actor for any Beads write that has no human originator (recurring jobs, webhook callbacks, internal automation).

The `--actor` flag for system-user writes resolves to that synthetic email — stable per install and unambiguous in the Beads `events` audit trail.

**Why synthetic Identity (not nil-identity User)**: many parts of Fizzy assume `User.identity` is present (e.g., `User#setup?` does `name != identity.email_address`). Special-casing nil identity throughout would be invasive. Creating a synthetic Identity is one row at install setup and removes an entire class of nil-checks. (This decision supersedes Q-S-046, which is now closed in §G.)

### E.2 Why a real User (not just a string)

- Fizzy's existing `creator_id`, `assignee_id`, etc. FKs require a real User row to point at.
- Audit/history queries that group by user benefit from a stable User.
- Eventual permission model (e.g., "system user cannot delete other users") is easier to express with a role.

### E.3 What recurring jobs use it for

From `config/recurring.yml` (per P1 §A.12):
- Auto-postpone all due cards → system user closes/postpones via `bd` (Q-S-016 settles the entropy plumbing)
- Cleanup webhook deliveries / magic links / exports / imports → no Beads writes (Fizzy-only)
- Deliver bundled notifications → no Beads writes

Only auto-postpone touches Beads in V1. Spec round S-jobs owns the per-job actor decision.

---

## §F — CSRF interaction

### F.1 Decision

**`RequestForgeryProtection#allowed_api_request?` survives intact.** No changes needed for V1.

The check (`sec_fetch_site_value.nil? && request.format.json?`) handles non-browser clients correctly. Beads-backed JSON endpoints inherit it without modification.

### F.2 Why no changes needed

- Bearer-token-authenticated requests come from non-browsers (CLI tools, scripts, API integrations); they don't send `Sec-Fetch-Site`.
- Browser-driven JSON requests (Hotwire fetch / Turbo) DO send `Sec-Fetch-Site` and DO honor the standard CSRF token mechanism.
- No new auth path means no new CSRF surface.

### F.3 What spec rounds must verify

- New `POST /cards` (et al) routes inherit the same CSRF posture as existing `POST /boards` etc.
- The `RequestForgeryProtection` concern is included in the relevant ApplicationController (verify; it should already be).

---

## §G — Resolved Q-S items (links back to P1)

The following items in `llm/notes/p1-foundational-gap-inventory.md` §E.3 are now ANSWERED by this doc:

- **Q-S-004 — How does Fizzy's `Identity::AccessToken` coexist with Beads' git-identity `actor`?** → ANSWERED. Per-call `bd --actor <Current.identity.email_address> ...` argv prefix on every `bd` subprocess (NOT env-var-based); bearer-token API survives intact; new beads-backed endpoints plug in unchanged. See §A, §B.
- **Q-S-006a — Does multi-user team / invites / roles / per-board access survive in V1?** → ANSWERED. **YES**. `Account` is singleton; `User` model intact; roles meaningful (owner/member/system); `Access` per-board ACL retained. See §C, §D.
- **Q-S-008 — How does `User` simplify in single-tenant?** → ANSWERED. **Keep User intact** (option (a) from P1 §E.3). `account_id` becomes constant FK to singleton Account. No code change to User model. See §C.
- **Q-S-046 — System user Identity row?** → ANSWERED. Create a synthetic Identity (`system@<install-hostname>`) for the system User; do NOT use nil-identity. See §E.1.

A subsequent edit to `p1-foundational-gap-inventory.md` will mark these ANSWERED with a backlink.

---

## §H — Open questions for downstream rounds

> **Q-S-043 — Webhook callback inbound auth model (V2+)?**
> If V2 introduces inbound webhook callbacks (e.g., from `bd` post-commit hooks or external integrations), what authenticates them and what actor do they use? Current V1 has no inbound webhook surface; deferred.

> **Q-S-044 — Token-rotation UX for `Identity::AccessToken`?**
> Existing tokens have no expiry / no rotation flow. Adding both is a security hardening. Defer to v2 unless CEO escalates.

> **Q-S-045 — Should `Current.identity` propagate through Solid Queue jobs the same way `Current.account` does (via `AccountTenanted`)?**
> Today only Account propagates. For actor resolution in jobs (per §A.2 row 3), we need either (a) Identity in the same `AccountTenanted` envelope renamed to `IdentityTenanted` / `CurrentTenanted`, or (b) jobs explicitly carry an `actor_email:` arg. Recommend (a). Spec round S-jobs owns this.

<!-- Q-S-046 — DECIDED IN §E.1 (synthetic Identity for system user); kept here as a tombstone for cross-ref consistency. -->

> **Q-S-047 — Owner-only operations enforced where?**
> Today `User.role` is checked ad-hoc. V1 should formalize role-based authorization (e.g., a `RoleAuthorization` concern) so "owner" actions (delete user, change install settings) are gated consistently. Spec round S-roles-authz owns this.

---

## §I — Validation checklist (locked v2)

- [x] §A names every code path that needs actor resolution (web cookie, web API bearer, sync job, recurring job).
- [x] §A.3 sketch is signature-only (no implementation).
- [x] §A specifies `bd --actor <email>` argv flag (NOT BEADS_ACTOR env).
- [x] §A.2 distinguishes CURRENT (only Account propagates today) from TARGET (Q-S-045 lands).
- [x] §B confirms no new auth flow / no new permission level / no new token format in V1.
- [x] §C explicitly chooses option (a) "keep User intact" for Q-S-008.
- [x] §D names the three roles and what they grant in single-tenant.
- [x] §E system-user mechanics are concrete (singleton Identity + singleton User, synthetic email convention, no nil-identity).
- [x] §F CSRF posture survives unchanged.
- [x] §G marks Q-S-004/006a/008/046 ANSWERED.
- [x] §H surfaces 4 follow-up questions (Q-S-043/044/045/047) — Q-S-046 closed in §G via §E.1.
- [x] No "we'll figure it out later" language.

---

## Convergence signal (P5)

3-of-3 lock reached:
- `[CLAUDE→CODEX P5: agreed]` (after applying Codex round-2 fixes)
- `[CODEX→CLAUDE P5: agreed]` (Codex re-reviewed v2)
- `[GEMINI→ALL P5 v2: ratify-confirm]` (Gemini ratified v1, then re-ratified v2 after corrections)

Bead `fizzy-3m5` to be closed in the lock commit. P6 (lifecycle adapter, brief at `p6-brief.md`, drafter Codex per alternation) opens next.
