# Test Discipline — what we test, when, and how

**Status**: draft (RoE-6 pending)
**Applies to**: `fizzy-claude`, `fizzy-codex`, `fizzy-gemini`, and any human contributor.
**Scope**: testing standards for the Fizzy/Beads fork. What kinds of tests we write, when they run, what blocks merge, and how we iterate visually on the UI.

This file does not define how to write a single test (use Rails idioms + `STYLE.md`); it defines the *discipline* — what coverage we owe, what gates we honor, and how we recover when tests fail.

Cross-links:
- `skills/round-protocol.md` — Implementation rounds (`I*`) must include tests as part of their AC
- `skills/bd-discipline.md` — every implementation bead's AC must specify which tests demonstrate "done"
- `skills/workflow-templates.md` — brief AC bullets are file-grounded; "test X passes" is a valid AC

---

## 1) Quality bar (non-negotiable per CEO)

Per CEO Q9:

> The quality bar is Fizzy as it stands in UI plus the functionality natively integrated into the UI. Match Fizzy's existing standards exactly. No more, no less.

Operationalized:

- We do not raise the bar above what current Fizzy ships with.
- We do not lower the bar below it.
- New UI features (driven by the beads data model) require end-to-end system coverage: **Capybara today** (since Playwright/Chromia does not exist yet in this repo), and **Playwright/Chromia once it lands** (target state). New UI work before Playwright exists must file a follow-up bead to migrate/supplement coverage once the framework is available.

---

## 2) The test taxonomy in this repo

| Layer | Tooling | Location | Run via | Speed |
|---|---|---|---|---|
| Unit + integration | Minitest + Rails fixtures | `test/{models,controllers,jobs,channels,helpers,mailers,middleware,integration,lib}/` | `bin/rails test` | fast |
| System (current upstream) | Capybara + Selenium | `test/system/` | `bin/rails test:system` | slow (browser) |
| **System (this fork)** | **Playwright/Chromia** | TBD via Spec round | TBD via Spec round | TBD |
| Style | Rubocop (omakase + Rails overrides) | repo-wide | `bin/rubocop` | fast |
| Gem security | `bin/bundler-audit check --update` | `Gemfile.lock` | `bin/ci` step | fast |
| Importmap security | `bin/importmap audit` | importmap | `bin/ci` step | fast |
| Application security | Brakeman | repo-wide | `bin/brakeman ...` | medium |
| Secret scanning | Gitleaks | repo-wide | `bin/gitleaks-audit` | fast |
| Gemfile drift | `bin/bundle-drift check` | `Gemfile.lock` | `bin/ci` step | fast |

**Note on Playwright/Chromia**: Fizzy ships with Capybara+Selenium. Adding Playwright/Chromia is itself a Spec round + Implementation round (it does not exist yet). Until that lands, system tests use Capybara; new UI features still owe Playwright/Chromia coverage as soon as the framework is in place. The discipline below assumes Playwright/Chromia once available; in the interim, Capybara coverage is acceptable for upstream-derived surfaces but not sufficient for new beads-driven surfaces.

---

## 3) The `bin/ci` pipeline (canonical, do not bypass)

`bin/ci` runs the following (mirrors `config/ci.rb` exactly):

```
1.  Setup                       bin/setup --skip-server
2.  Style: Ruby                 bin/rubocop
3.  Gemfile: Drift check        bin/bundle-drift check
4.  Security: Gem audit         bin/bundler-audit check --update
5.  Security: Importmap audit   bin/importmap audit
6.  Security: Brakeman audit    bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
7.  Security: Gitleaks audit    bin/gitleaks-audit

If Fizzy.saas?:
  8a. Tests: SaaS               SAAS=true BUNDLE_GEMFILE=Gemfile.saas bin/rails test
  8b. Tests: SaaS System        SAAS=true BUNDLE_GEMFILE=Gemfile.saas PARALLEL_WORKERS=1 bin/rails test:system
  8c. Tests: OSS                SAAS=false BUNDLE_GEMFILE=Gemfile bin/rails test
  8d. Tests: OSS System         SAAS=false BUNDLE_GEMFILE=Gemfile PARALLEL_WORKERS=1 bin/rails test:system
Else:
  8a. Tests: SQLite             SAAS=false BUNDLE_GEMFILE=Gemfile bin/rails test
  8b. Tests: SQLite System      SAAS=false BUNDLE_GEMFILE=Gemfile PARALLEL_WORKERS=1 bin/rails test:system

9.  Signoff (success only)      gh signoff
   On failure: prints "Signoff: CI failed. Do not merge or deploy." and stops.
```

**Rules:**
- `bin/ci` is the canonical pre-merge gate **for code changes**. Code commits do not land on `dev` or `main` without `bin/ci` passing.
- **Docs-only changes** (`skills/`, `llm/`, `docs/`, `AGENTS.md`, `STYLE.md`, `README.md`, etc.) require only a clean `git status` and a peer-ratified review per the round protocol — no test gate. RoE artifacts have been landing this way since session start.
- Do **not** skip steps in `config/ci.rb`. Do not pass `--skip-tests` or comment out steps. If a step is genuinely broken in a way unrelated to your work, file a bd issue + ping CEO.
- `PARALLEL_WORKERS=1` for system tests is intentional (system tests can't run reliably in parallel). Keep it.
- Step 9 (`gh signoff`) requires GitHub CLI auth; agents running `bin/ci` locally should treat a missing/failing `gh signoff` as non-blocking — the upstream CI server is what gates merge in practice.

---

## 4) When tests are required

### 4.1 Implementation rounds (`I*`)

Every `I*` round's AC must include at least:

- A unit/integration test that exercises the new behavior
- A system test for any UI surface touched. **Until Playwright/Chromia lands, this is Capybara coverage** (existing repo tooling). When new UI is added now, the `I*` round must also file a follow-up bead to migrate or supplement that coverage with Playwright/Chromia once the framework exists.
- A passing `bin/ci` run before signoff

If a feature has no testable surface (truly internal refactor, no behavior change), the AC must explicitly say "no behavior change; existing tests cover regression"—and a peer must concur.

### 4.2 Spec rounds (`S*`)

Spec rounds **define** the AC for `I*` rounds. Every spec'd bead's AC must name the specific test(s) that demonstrate "done" — file path, test name, expected output. This is part of the "perfect bead" requirement (`bd-discipline.md` §5).

### 4.3 Plumbing rounds (`R*`)

Plumbing fixes need:

- A reproducer (or at least a written description of the broken state)
- Verification commands in the signoff
- A test if the fix is reproducible in code (e.g., not just "rebooted Dolt")

### 4.4 Planning rounds (`P*`)

Planning rounds produce notes/decisions, not code. No test requirement, but the planning output may identify coverage gaps to file as `discovered-from` beads.

---

## 5) Visual iteration loop (UI work)

For any UI work, the loop is:

```
1. boot dev server                  bin/dev   (URL: http://app.fizzy.localhost:3006)
2. log in                           magic link from console (david@example.com)
3. navigate to the surface          via UI or directly to /:account/...
4. iterate on code                  Hotwire hot-swap or full reload
5. visual check                     Playwright/Chromia screenshot or Chrome MCP
6. run bin/rails test for fast feedback
7. run bin/rails test:system before commit
8. run bin/ci before push
```

**Browser automation tooling** for visual checks varies by agent (Claude uses Chrome MCP today; Codex uses Playwright MCP today; Gemini may use either). Use whichever your session has available for one-off visual inspection during iteration. **Commit-gating system tests** still need to live in `test/system/` and run under `bin/rails test:system` (Capybara now; Playwright/Chromia as the target).

---

## 6) Test data conventions

- Fixtures live in `test/fixtures/`. Fizzy uses **deterministic UUIDv7 generation** for fixtures via the `FixturesTestHelper` module in `test/test_helper.rb:94` (prepended to `ActiveRecord::FixtureSet`; converts UUIDs to base36 25-char strings). Fixtures are always "older" than runtime records, so `.first`/`.last` ordering works correctly.
- Do **not** introduce factories (FactoryBot etc.). Fizzy is fixture-based by convention.
- Fixtures may be added/extended for new beads-driven models, but follow the existing UUID generator pattern so deterministic ordering holds.

---

## 7) Multi-agent test coordination

- A test file is owned by whoever owns the bead that introduced the behavior under test.
- Two agents must not edit the same test file in parallel without ping-ACK.
- If a test fails on `dev` after a recent commit, the committer is responsible for fix-or-revert within a reasonable window. Document in `llm/LOG.md` if you take over because the original committer is unavailable.

---

## 8) Failure modes (what NOT to do)

- ❌ Commenting out failing tests to "make CI green". Fix the test or the underlying behavior.
- ❌ Adding `skip "TODO"` without a bd issue id and a follow-up bead.
- ❌ Pushing without running `bin/ci`. Local pass = clean push.
- ❌ Using factories instead of fixtures. Fixtures are the convention.
- ❌ Using mocks for the database in integration/system tests. Real DB or it doesn't count.
- ❌ Adding system tests in parallel-unsafe ways. `PARALLEL_WORKERS=1` is preserved.
- ❌ Lowering Brakeman / bundler-audit severity thresholds to silence warnings. Fix or document with explicit CEO sign-off.
- ❌ Adding new UI features without Playwright/Chromia coverage (once Playwright exists). Capybara coverage is the *interim* bar, not the *target*.
- ❌ Editing `config/ci.rb` to skip steps without a bd issue + CEO sign-off.

---

## 9) Convergence signal (RoE-6)

When all active agents agree RoE-6 is complete, each sends the others:

`[FROM→TO RoE-6: agreed]`

After all signals are present in `llm/LOG.md`, this file is locked and we move to topic 7 (`session-lifecycle.md`) — the final RoE topic.
