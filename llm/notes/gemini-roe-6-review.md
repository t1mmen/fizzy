# Gemini Third-Lens Review: RoE-6 (Test Discipline)

**Date**: 2026-04-17
**Status**: Completed
**Scope**: Review of `skills/test-discipline.md` (RoE-6) v1.

---

## (a) Gaps/Contradictions

- **Playwright vs Capybara Transition**: §2 correctly identifies the interim status of Capybara. There is a potential contradiction in §4.1: "A system test (Playwright/Chromia preferred, Capybara acceptable until Playwright lands)". This is clear, but we should ensure that *once* the Playwright Spec round (S-TBD) is ratified, this document is updated or the "acceptable" clause is deprecated.
- **`bin/ci` step 9**: §3 explicitly sets `PARALLEL_WORKERS=1` for system tests. This is a common and necessary constraint for Rails system tests to avoid database locking/transaction issues. Good catch.

## (b) Improvements (non-blocking)

- **Chromia/Chrome MCP Usage**: §5 mentions Chrome MCP as an alternative for visual inspection. Since Gemini is an interactive CLI agent, I can leverage Chrome MCP tools directly to verify UI states during my "Act" phase. I will follow this loop.
- **Fixture Generation**: §6 mentions deterministic UUIDv7 generation for fixtures. Suggest adding a code pointer (e.g., `lib/fizzy/test_helpers/uuid_fixtures.rb` or similar) once we locate the exact helper, to make it easier for agents to copy the pattern.
- **Security Audit Failure**: §3 step 4 (`bundler-audit --update`) and step 10 (`gh signoff`). If `gh signoff` requires a specific environment (e.g. GitHub Actions), we should clarify if this step is only for the CI server or if agents running `bin/ci` locally are expected to simulate/skip it.

## (c) Verdict

- **[ratify-as-is]**

The taxonomy is comprehensive and the `bin/ci` 10-step pipeline provides the necessary rigor for a "10-year-business" quality bar. The distinction between interim Capybara and target Playwright for beads-driven surfaces is a crucial architectural guardrail.

---
Ratification signals a 3-of-3 lock for RoE-6. Ready for Topic 7 (`session-lifecycle.md`).
