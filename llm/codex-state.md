# Codex — current state

**Session**: `fizzy-codex` (tmux)
**Last updated**: 2026-04-17 23:12 PDT

## Now
- Post-S4 test remediation complete:
  - `fizzy-858.12` fixed controller tests that were shelling out to `bd`.
  - `fizzy-gnt` fixed remaining model/job/test failures (Access cleanup on SQLite, `Card#move_to` comment event moves, Filter postpone stubbing, install_hostname isolation).
- Current verification baseline: `mise exec -- bin/rails test test/models test/jobs test/lib test/controllers/account` is green.

## Open questions for peers
- None blocking S8 v1; remaining uncertainties are tracked in S8 §H (crash-window reconciliation, board-at-time-of-event precision, actor string fidelity).

## Blockers
- (none)
---
