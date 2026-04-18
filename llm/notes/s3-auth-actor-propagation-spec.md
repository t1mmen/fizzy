# S3 — Auth + Actor Propagation Spec (Identity → bd `--actor` argv)

**Status**: v1 ready for peer review
**Bead**: `fizzy-rqx` (epic)
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
**Brief**: `llm/notes/s3-brief.md`

This spec turns the P5 auth-bridging decisions into implementation-ready perfect beads:
- Every `bd` subprocess invocation carries `--actor <email>` argv (P5 §A.1).
- The actor email is `Current.identity.email_address` (or system-actor email when no human originator).
- Web controllers, background jobs, and any other code path resolves the same way without ENV pollution or thread races.

Three third-lens priors from Gemini are explicitly enforced:
1) `Current.actor` MUST be strictly derived from `Identity.email_address` — no other source of truth.
2) `CommandClient` constructor MUST require an explicit `actor:` kwarg — no anonymous writes; raise on missing.
3) `FizzyActiveJobExtensions` MUST restore the actor context on async jobs so async `bd` mutations carry correct attribution.

---

## §A — `Current.actor` definition

### A.1 What `Current.actor` is

`Current.actor` is a **string** (an email address) representing the actor for the current unit of work. It is the value passed to `bd --actor <actor>` on every Beads write.

It is intentionally a string, not an Identity object, because:
- Beads' actor concept is a string identifier; matching the abstraction prevents accidental coupling to AR objects.
- Strings serialize trivially through Solid Queue job data.
- Avoids "what if `Current.identity` is stale by job-execution time" questions.

Canonical resolution rule (set once, at the request/job entry):

```ruby
Current.actor = Current.identity&.email_address || SystemActor.email
```

### A.2 Lifecycle (request boundary)

`Current` already extends `ActiveSupport::CurrentAttributes`, which is per-request and per-thread (via `CurrentAttributes` machinery). Adding `:actor` to the attribute list inherits that semantics.

Set in `ApplicationController` via a `before_action :set_current_actor` that runs **after** `Authentication#require_authentication` (so `Current.identity` is populated) and **before** any controller action body.

Cleared automatically at end-of-request by `CurrentAttributes` (no explicit teardown needed).

### A.3 Lifecycle (job boundary)

`Current.actor` is serialized into job data alongside `Current.account` (existing pattern) via a new `BeadsActorTenanted` concern (§D). Restored at `around_perform`. This closes Q-S-045 from P5 §H with option (a).

### A.4 Thread safety

`ActiveSupport::CurrentAttributes` is thread-local; `Current.actor` is therefore safe under multi-threaded servers (Puma) and multi-threaded job workers (Solid Queue with multi-threaded executor).

No global `ENV["BEADS_ACTOR"]` is ever set. Per P5 §A.4, ENV-based actor would race across concurrent requests.

### A.5 `Current` class addition (exact change)

Add `:actor` to the `attribute` list. Add a derived setter so any code that prefers to set `Current.identity` continues to populate `Current.actor` automatically:

```ruby
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :user, :identity, :account, :actor
  attribute :http_method, :request_id, :user_agent, :ip_address, :referrer

  def session=(value)
    super(value)
    if value.present?
      self.identity = session.identity
    end
  end

  def identity=(identity)
    super(identity)
    if identity.present?
      self.user  = identity.users.find_by(account: account)
      self.actor = identity.email_address
    end
  end

  # ... existing with_account/without_account ...
end
```

Setting `Current.identity = nil` clears `Current.actor` only via explicit setter. For system-job paths that set `Current.actor` directly (no Identity), that's fine — `Current.actor=` is an unmediated string write.

## §B — `Fizzy::Beads::CommandClient` exact API

### B.1 Class signature (locked)

```ruby
module Fizzy
  module Beads
    class CommandClient
      class MissingActorError < StandardError; end
      class CommandError      < StandardError
        attr_reader :argv, :status, :stderr
        def initialize(argv, status, stderr)
          @argv, @status, @stderr = argv, status, stderr
          super("bd command failed: #{argv.join(' ')} | exit=#{status.exitstatus} | stderr=#{stderr}")
        end
      end

      def self.for(identity_or_actor)
        actor =
          case identity_or_actor
          when nil           then raise MissingActorError, "Cannot construct CommandClient without an actor"
          when Identity      then identity_or_actor.email_address
          when String        then identity_or_actor
          else raise ArgumentError, "Expected Identity or String, got #{identity_or_actor.class}"
          end
        new(actor: actor)
      end

      def self.current
        actor = Current.actor or raise MissingActorError, "Current.actor is unset; cannot dispatch bd write"
        new(actor: actor)
      end

      def initialize(actor:, bd_bin: "bd")
        raise MissingActorError, "actor required" if actor.nil? || actor.empty?
        @actor  = actor
        @bd_bin = bd_bin
      end

      # — public command surface (one method per bd subcommand used) —
      # def create_issue(title:, description:, priority: nil, labels: [], type: "task")
      # def update_issue(id, **fields)
      # def close_issue(id, reason: nil)
      # def add_label(id, label)
      # def remove_label(id, label)
      # def add_dependency(id, depends_on:, type: "blocks")
      # ...
      # Exact method enumeration is owned by S4 (lifecycle), S5 (labels), S6 (comments).
      # S3 only specifies the dispatch primitive (#invoke!) and class shape.

      private

      def invoke!(argv)
        full_argv = [@bd_bin, "--actor", @actor, *argv]
        stdout, stderr, status = Open3.capture3(*full_argv)
        raise CommandError.new(full_argv, status, stderr) unless status.success?
        stdout
      end
    end
  end
end
```

### B.2 Why explicit `actor:` kwarg (Gemini prior #2)

- Constructor with no `actor:` → `MissingActorError`. No silent defaulting to ENV / `git user.name` / blank.
- `.for(identity_or_actor)` is the convenience factory; it normalizes Identity → string and rejects nil.
- `.current` is the in-request shortcut that reads `Current.actor`; it raises if `Current.actor` is unset (which it never should be after `set_current_actor` ran).

### B.3 Argv prefix is non-negotiable

The `--actor` flag is **always** the first two argv elements after the binary, ahead of any subcommand. This matches `bd --help` precedence: `--actor` (global flag) → `$BEADS_ACTOR` → `git user.name` → `$USER`. Putting `--actor` first means it can't be confused with a subcommand-specific flag.

### B.4 No env-hash form

Per P5 §A.4: never set `ENV["BEADS_ACTOR"]` even per-call via `Open3.capture3`'s env-hash. Argv is scoped to the one process; env can leak to nested children.

### B.5 Test surface (covered in §H)

CommandClient is a thin shell over `Open3.capture3`. Tests should:
- Stub `Open3.capture3` and assert the exact argv composition including `--actor <email>`.
- Verify `MissingActorError` raises on nil/empty actor.
- Verify `CommandError` raises on non-zero exit and includes argv + stderr in the message.

## §C — Web controller integration

### C.1 `ApplicationController` `before_action`

Add to `ApplicationController` (or to the `Authentication` concern, after `require_authentication`):

```ruby
before_action :set_current_actor, if: :authenticated?

private

def set_current_actor
  Current.actor = Current.identity&.email_address || SystemActor.email
end
```

Because `Current.identity=` already populates `Current.actor` per §A.5, this `before_action` is redundant in the common path — but it provides defense-in-depth for code paths that set `Current.identity` directly without going through the setter (rare; mostly tests).

### C.2 `Authentication#require_authentication` interaction

`Authentication#require_authentication` (`app/controllers/concerns/authentication.rb:44-46`) calls `resume_session` (which sets `Current.session` → which sets `Current.identity` → which (post-§A.5) sets `Current.actor`) OR `authenticate_by_bearer_token` (which sets `Current.identity` directly → which sets `Current.actor`).

Either path leaves `Current.actor` populated. The `set_current_actor` `before_action` is purely belt-and-braces.

### C.3 Controller call sites

Any controller action that performs a Beads write uses `CommandClient.current` (which reads `Current.actor`):

```ruby
def create
  Fizzy::Beads::CommandClient.current.create_issue(title: params[:title], ...)
end
```

S2 children that already exist as Beads-touching controllers (per S2 §D.5):
- `fizzy-eq4.8` Cards::BoardsController#update (move card between boards) — uses CommandClient
- `fizzy-eq4.9` Cards::TaggingsController (label add/remove) — uses CommandClient

Both gain a transitive dependency on S3 children that ship `CommandClient` + `Current.actor`. Cross-spec deps wired in §J.

### C.4 Unauthenticated request paths

Some controller paths intentionally `allow_unauthenticated_access` (e.g., login flow itself, public board views). Those paths MUST NOT call CommandClient — there's no actor. If they accidentally do, `CommandClient.current` raises `MissingActorError`, surfacing the bug loudly.

## §D — Background job actor propagation (`BeadsActorTenanted`)

This closes P5 §H Q-S-045 with option (a): a tenanted concern that mirrors `AccountTenanted`.

### D.1 Concern definition

New file `app/jobs/concerns/beads_actor_tenanted.rb`:

```ruby
module BeadsActorTenanted
  extend ActiveSupport::Concern

  prepended do
    attr_reader :beads_actor
    around_perform :with_beads_actor_context
  end

  def initialize(...)
    super
    @beads_actor = Current.actor
  end

  def serialize
    super.merge({ "beads_actor" => @beads_actor })
  end

  def deserialize(job_data)
    super
    @beads_actor = job_data["beads_actor"]
  end

  private
    def with_beads_actor_context(&block)
      if beads_actor.present?
        Current.set(actor: beads_actor, &block)
      else
        yield
      end
    end
end
```

### D.2 Prepending

`FizzyActiveJobExtensions` (per AGENTS.md "Background Jobs") prepends `AccountTenanted` to ActiveJob globally. `BeadsActorTenanted` prepends in the same place.

### D.3 Recurring jobs (no Current.actor at enqueue time)

Recurring jobs (per `config/recurring.yml`) enqueue from outside any request, so `Current.actor` is unset at `initialize`. Two patterns:

(a) **Job assigns system actor in its own logic** (preferred for V1):
```ruby
class AutoPostponeJob < ApplicationJob
  def perform
    Current.actor = SystemActor.email
    Card.due_for_postponement.find_each do |card|
      Fizzy::Beads::CommandClient.current.update_issue(card.id, status: "deferred")
    end
  end
end
```

(b) **Job class declares system-actor at the class level** (deferred — could be added later as a `system_actor!` macro). Not in V1.

### D.4 Synchronous-job path

If a job is enqueued during a request (so `Current.actor` is set), `BeadsActorTenanted#initialize` captures it. The serialized job carries the actor. On execute, `around_perform` restores it. CommandClient sees the right actor.

If multiple jobs are enqueued in the same request, each captures the same `Current.actor` independently — no shared state.

## §E — Bearer-token JSON API future hook

Per P5 §B, the existing bearer-token mechanism survives intact. S3 must NOT preclude it.

### E.1 Existing bearer-token path already populates Current.identity

`Authentication#authenticate_by_bearer_token` (`app/controllers/concerns/authentication.rb:58-70`) sets `Current.identity = identity` after token resolution. Per §A.5, that triggers `Current.actor = identity.email_address` automatically.

### E.2 V1 commitment

V1 ships:
- All web requests use cookie session → `Current.identity` set → `Current.actor` set.
- All JSON API requests use bearer token → `Current.identity` set → `Current.actor` set.
- All background jobs use BeadsActorTenanted → `Current.actor` restored.

There is no V1 path where a Beads write happens with `Current.actor` unset. If one appears, `CommandClient.current` raises.

### E.3 V2+ webhook callback (Q-S-043; not in V1)

If V2 introduces inbound webhook callbacks, the webhook handler must set `Current.actor` (e.g., to `webhook@<install>` or similar) before invoking CommandClient. S3 does not specify this; it is forward-compatible.

## §F — System-actor identity

### F.1 Decision

Per P5 §E.1: every install auto-creates a singleton `Identity` with `email_address: "system@<install-hostname>"` AND a singleton `User` with `role: "system"`, `name: "Fizzy System"`, linked to that Identity.

S3 specifies the **constant accessor** for that email so code can use a stable name without hardcoding the email string in 50 places.

### F.2 `SystemActor` accessor

New file `app/models/system_actor.rb`:

```ruby
class SystemActor
  def self.identity
    Identity.find_by!(email_address: email)
  end

  def self.user
    @user ||= identity.users.find_by!(role: :system)
  end

  def self.email
    "system@#{install_hostname}"
  end

  def self.install_hostname
    Rails.application.config.x.fizzy.install_hostname or
      raise "Rails.application.config.x.fizzy.install_hostname is not set"
  end
end
```

`install_hostname` is configured at install time (e.g., `app.fizzy.localhost` for dev, `fizzy.example.com` for production). Configured via `config/application.rb` or an initializer; not a Beads-visible concept.

### F.3 Bootstrap

The system Identity + User must exist before any recurring job runs. Two-prong approach:

(a) **Migration creates them at install** — a new data migration (post-S1, in I-S3) inserts the system Identity and User if they don't exist.

(b) **Idempotent ensure-helper at boot** — `SystemActor.ensure!` runs in an initializer to create the rows if missing (defensive against fresh-DB scenarios).

For V1 simplicity: ship (a) as the canonical path; (b) is a follow-up if needed.

### F.4 What system actor differs from human Identity

- `Identity#confirmable?` — system Identity is auto-confirmed; cannot be re-confirmed via email.
- `Session` — system Identity has no Sessions; cannot log in via UI.
- `User#role` — `system` (P5 §D); has full Beads-write privileges; cannot be a board owner.

Existing constraints in the User model (e.g., `User#setup?`) need verification that `system` role is handled cleanly. I-S3 must add a test.

## §G — Failure modes

### G.1 `Current.actor` unset when CommandClient is called

`Fizzy::Beads::CommandClient.current` raises `MissingActorError`. The error bubbles up; the request fails with 500 (or the job re-enqueues with backoff per ActiveJob retry policy).

This is the desired behavior — silent fallback to anonymous would corrupt the Beads audit trail.

### G.2 Actor email doesn't exist as a Beads-side known actor

Beads accepts any string as an actor; it does not validate against a known-actor list. So this is not a runtime failure — but it does pollute the Beads `events` audit with arbitrary strings. Mitigation: `Current.actor` is only ever set from `Identity.email_address` (validated email format) or `SystemActor.email` (constant). No other path sets it.

### G.3 `bd` binary missing or unexecutable

`Open3.capture3` raises `Errno::ENOENT`. CommandClient should catch and re-raise as `CommandError` with a useful message (e.g., "bd binary not found at #{bd_bin}; ensure beads is installed").

### G.4 `bd` exits non-zero

`CommandError` carries argv + exit status + stderr. Caller decides whether to retry or surface to user. CommandClient does not retry internally (caller / job retry policy decides).

### G.5 Concurrent CommandClient calls in the same request

`CommandClient` is stateless after construction (only `@actor` and `@bd_bin`). Multiple instances per request are fine. `Open3.capture3` forks a fresh subprocess per call.

### G.6 `Current.identity` set but `email_address` is nil

Cannot happen — `email_address` has `validates :email_address, presence: true` (verify in I-S3). If somehow nil, `CommandClient.current` raises (treat empty string as missing).

## §H — Test strategy

### H.1 Unit tests

`test/models/fizzy/beads/command_client_test.rb`:
- Stubs `Open3.capture3`, asserts argv composition: `["bd", "--actor", "x@y.com", "create", ...]`.
- `MissingActorError` on nil/empty actor.
- `CommandError` on non-zero exit, includes argv+stderr.
- `.for(Identity)` extracts email; `.for(String)` passes through; `.for(nil)` raises.
- `.current` reads `Current.actor`; raises if unset.

`test/models/current_test.rb`:
- `Current.identity = identity` populates `Current.actor`.
- `Current.actor = "x@y.com"` directly works.
- Per-thread isolation (set in thread A, unset in thread B).

`test/models/system_actor_test.rb`:
- `SystemActor.email` returns expected format.
- `SystemActor.identity` returns the singleton Identity row.
- `SystemActor.user` returns the singleton User row with `role: system`.

### H.2 Integration tests (controller)

`test/integration/beads_actor_propagation_test.rb`:
- Authenticated request → controller calls `CommandClient.current` → asserts the stubbed `Open3.capture3` saw `--actor david@example.com` (per fixture).
- Bearer-token request → same assertion with the bearer-Identity email.
- Unauthenticated path → asserts `CommandClient.current` raises `MissingActorError` (controller bug surfaces).

### H.3 Job tests

`test/jobs/beads_actor_tenanted_test.rb`:
- Enqueue a job inside a `Current.with(actor: "x@y.com")` block.
- Job serialized data includes `"beads_actor" => "x@y.com"`.
- Deserialize + execute restores `Current.actor` to `"x@y.com"`.
- Job that calls `CommandClient.current` sees the right actor.

### H.4 Test discipline

Per `skills/test-discipline.md`: integration tests must hit a real CommandClient stub but actual invocation patterns. Job tests use Solid Queue's test adapter to run jobs synchronously and inspect `perform`-time state.

## §I — Open questions deferred to later spec rounds

1) **Exact CommandClient public method enumeration** (`create_issue`, `update_issue`, `close_issue`, `add_label`, etc.): owned by S4 (lifecycle), S5 (labels), S6 (comments). S3 only specifies the dispatch primitive (`#invoke!`) and class shape.
2) **Install bootstrap UX for the SystemActor Identity row creation**: deferred to a future install-setup spec (not S4-S10). For V1, the migration in I-S3 handles it.
3) **`config/recurring.yml` audit for which jobs need `BeadsActorTenanted`**: only `AutoPostponeJob` (or equivalent) touches Beads in V1 per P5 §E.3. S3 defines the concern + recurring-job pattern; S4 (lifecycle) confirms which jobs adopt it.
4) **Token rotation UX for `Identity::AccessToken`**: P5 §H Q-S-044 explicitly v2+. No S3 work.
5) **Owner-only operations enforcement**: P5 §H Q-S-047 explicitly deferred to a future S-roles-authz round. No S3 work.

## §J — Child bead inventory

Child beads (I-S3 implementation tasks) are minted under epic `fizzy-rqx`.

All beads below are wired as:
- parent-child to `fizzy-rqx`
- intra-S3 `blocks` edges reflecting implementation ordering
- cross-spec `blocks` edges to S2 children that consume CommandClient (`fizzy-eq4.8`, `fizzy-eq4.9`)

| Bead | Title | Satisfies | Key dependencies |
|---|---|---|---|
| `fizzy-rqx.1` | Add `:actor` to `Current` + populate via `identity=` setter | §A.5 | none (additive) |
| `fizzy-rqx.2` | Implement `SystemActor` accessor + install_hostname config | §F.2 | none |
| `fizzy-rqx.3` | Migration: bootstrap system Identity + system User at install | §F.3 (a) | `fizzy-rqx.2` |
| `fizzy-rqx.4` | Implement `Fizzy::Beads::CommandClient` class (`#invoke!`, `.for`, `.current`, error classes) | §B.1, §B.2, §B.4 | `fizzy-rqx.1` |
| `fizzy-rqx.5` | `ApplicationController` `before_action :set_current_actor` (defense-in-depth) | §C.1, §C.2 | `fizzy-rqx.1` |
| `fizzy-rqx.6` | `BeadsActorTenanted` concern + prepend in `FizzyActiveJobExtensions` | §D.1, §D.2 | `fizzy-rqx.1` |
| `fizzy-rqx.7` | Unit tests: CommandClient + Current + SystemActor | §H.1 | `fizzy-rqx.4`, `fizzy-rqx.2` |
| `fizzy-rqx.8` | Integration tests: web cookie + bearer-token actor propagation | §H.2 | `fizzy-rqx.5`, `fizzy-rqx.4` |
| `fizzy-rqx.9` | Job tests: BeadsActorTenanted serialize/restore + CommandClient.current in jobs | §H.3 | `fizzy-rqx.6`, `fizzy-rqx.4` |
| `fizzy-rqx.10` | Wire S2 controllers (`fizzy-eq4.8`) to CommandClient.current — unblock S2 implementation | §C.3 | `fizzy-rqx.4`, `fizzy-rqx.5` (cross-spec: blocks `fizzy-eq4.8`) |

## §K — Validation checklist

Pre-lock checklist for S3:
- [x] §A–§I fully drafted (no TODO stubs)
- [x] §B CommandClient signature is locked (constructor, factory, current, errors)
- [x] §B.2 explicit `actor:` kwarg + raise on missing (Gemini prior #2)
- [x] §A.5 `Current` change is concrete + minimal
- [x] §D BeadsActorTenanted mirrors AccountTenanted exactly (Gemini prior #3)
- [x] §F SystemActor accessor + install bootstrap path specified
- [x] §G failure modes enumerated with concrete behaviors
- [x] §H test strategy covers unit + integration + job
- [x] §J child bead inventory has cross-spec dep to `fizzy-eq4.8` (and `fizzy-eq4.9` via §I.1 + S5)
- [ ] `[CLAUDE→CODEX S3 v1 ready]` sent + peer review complete
- [ ] `[FROM→TO S3: agreed]` 3-of-3 lock
