# P2 — Local Dev Grounding (bd + Dolt + Rails)

**Status**: in progress
**Bead**: `fizzy-3zi`
**Owner**: `fizzy-codex`

This is the command transcript + gotchas log for P2. The canonical procedure extracted from this goes into `skills/local-dev.md`.

---

## 0) Baseline context

- Repo: `/Users/timmstokke/work/fizzy`
- Date: 2026-04-17

## 1) Prereqs (as observed on this machine)

### 1.1 Commands checked

See `llm/notes/p2-artifacts/prereqs.txt`.

Notable:
- `gum` and `mise` were missing initially; `bin/setup` installed them via Homebrew.
- `docker` exists (only needed if `DATABASE_ADAPTER=mysql`).
- `jq` exists (only needed for `bin/dev --tailscale` path).

---

## 2) `bin/setup` (what happened, failures, fixes)

### 2.1 First run failure: Ruby build failed due to missing libyaml headers (psych)

Symptoms (excerpt from `llm/notes/p2-artifacts/bin-setup.log`):
- `psych` extension failed to compile.

Root cause evidence (from the ruby-build mkmf log):

```text
pkg_config: checking for pkg-config for yaml-0.1... not found
find_header: checking for yaml.h... no
fatal error: 'yaml.h' file not found
```

Fix applied:
- Updated `bin/setup` to install `libyaml` + `pkg-config` (brew) / `libyaml` + `pkgconf` (pacman), and crucially to do it **before** `mise install`.

### 2.2 Second run failure: `bundle` was a Nix wrapper function

Symptoms (end of `llm/notes/p2-artifacts/bin-setup-2.log`):

```text
path '/Users/timmstokke/work/fizzy' does not contain a 'flake.nix', searching up
error: path '/Users/timmstokke/work/fizzy' is not part of a flake
```

Root cause (on this machine):

```bash
type bundle
# bundle is a function
# bundle () { nix develop --command bundle "$@"; }
```

Fix applied:
- Updated `bin/setup` to `unset -f bundle` if `bundle` is a shell function, so setup uses real Bundler.

### 2.3 Successful run

`bin/setup --skip-server` succeeded after the above fixes.

Evidence:
- `llm/notes/p2-artifacts/bin-setup-3.log` ends with:
  - `✓ Done (...)`
  - `bin/setup exit=0`

---

## 3) Activate the repo Ruby (mise) in your shell

Even after `bin/setup` succeeds, **new shells** do not automatically pick up the repo’s Ruby. Without this, `bin/rails` will run with system Ruby (2.6 on this machine) and fail with Bundler git/path errors.

Working pattern (bash):

```bash
eval "$(mise hook-env -s bash)"
```

For zsh:

```bash
eval "$(mise hook-env -s zsh)"
```

---

## 4) Boot the app (`bin/dev`) + verify HTTP

### 4.1 Boot command (works)

```bash
eval "$(mise hook-env -s bash)"
bin/dev
```

### 4.2 HTTP verification (works)

```bash
curl -I http://app.fizzy.localhost:3006/
```

Observed response (excerpt):

```text
HTTP/1.1 302 Found
location: http://app.fizzy.localhost:3006/session/menu
```

---

## 5) Beads + Dolt server status (ground truth)

### 5.1 `bd context --json`

```json
{
  "backend": "dolt",
  "dolt_mode": "server",
  "server_host": "127.0.0.1",
  "server_port": 54309,
  "database": "fizzy",
  "bd_version": "1.0.2"
}
```

### 5.2 `bd dolt status`

```text
Dolt server: running
  PID:  65478
  Port: 54309
  Data: /Users/timmstokke/work/fizzy/.beads/dolt
  Logs: /Users/timmstokke/work/fizzy/.beads/dolt-server.log
```

### 5.3 Direct Dolt SQL proof

```sql
$ cd .beads/dolt/fizzy
$ dolt sql -q "select count(*) as issues_count from issues"
+--------------+
| issues_count |
+--------------+
| 4            |
+--------------+
```

---

## 6) Rails ↔ Beads connection proofs (CLI and SQL)

### 6.1 Rails → `bd` CLI shell-out (proof of CLI path)

Script:
- `bin/p2-rails-bd-probe.rb`

Run:

```bash
eval "$(mise hook-env -s bash)"
bin/rails runner bin/p2-rails-bd-probe.rb
```

Output (verbatim):

```text
OK: bd context backend=dolt dolt_mode=server host=127.0.0.1 port=54309 db=fizzy
OK: bd export issues=4
  1. fizzy-3zi — P2: Local Development Environment Grounding (bd+Dolt+Rails)
  2. fizzy-08o — P1: Foundational Gap Inventory — Fizzy ↔ Beads
  3. fizzy-0zx — Sample comprehensive issue
  4. fizzy-jul — Get started
```

### 6.2 Rails → Dolt SQL server via `trilogy` (proof of SQL path)

Script:
- `bin/p2-rails-dolt-probe.rb`

Run:

```bash
eval "$(mise hook-env -s bash)"
bin/rails runner bin/p2-rails-dolt-probe.rb
```

Output (verbatim):

```text
OK: connected to Dolt SQL server (trilogy) at 127.0.0.1:54309/fizzy
OK: issues.count=4
Sample (most recently updated):
  1. fizzy-jul [closed P2] — Get started
  2. fizzy-0zx [closed P1] — Sample comprehensive issue
  3. fizzy-3zi [open P1] — P2: Local Development Environment Grounding (bd+Dolt+Rails)
  4. fizzy-08o [closed P1] — P1: Foundational Gap Inventory — Fizzy ↔ Beads
```

---

## 7) Gotchas / notes

### 7.1 `bin/setup` piped output hides failures if you don’t use `pipefail`

When capturing logs with `tee`, ensure you preserve exit status:

```bash
bash -lc 'set -o pipefail; bin/setup 2>&1 | tee setup.log; echo exit=$?'
```

### 7.2 `bin/dev` requires mise activation in the calling shell

If you run `bin/dev` without `mise hook-env`, you may see:

```text
https://github.com/rails/rails.git (...) is not yet checked out. Run `bundle install` first.
```

The actual issue is: system Ruby is being used, not the mise Ruby.

---

## 8) Feeds into P3 (data-path decision evidence)

Evidence we now have for Q-S-001 / Q-S-001a:
- CLI path is viable: Rails can call `bd context` + `bd export` successfully (see §6.1).
- SQL path is viable: Rails can connect directly to the Dolt SQL server via `adapter: trilogy` and query `issues` (see §6.2).

What P2 does *not* decide:
- Which path becomes canonical in the fork (P3 owns that decision).
- How writes should attribute actors / emit events / preserve beads hooks (P3 should weigh CLI vs SQL for mutations).
