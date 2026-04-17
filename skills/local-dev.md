# Local Development — Fizzy (Rails) + Beads (bd + Dolt)

**Purpose**: a canonical, reproducible local-dev procedure for anyone working on this repo.

This repo includes two “datastores”:
- **Fizzy app DB** (Rails): defaults to **SQLite** for OSS dev; can use MySQL if `DATABASE_ADAPTER=mysql`.
- **Beads task DB**: always **Dolt** in **server mode** under `.beads/dolt/` (managed by `bd dolt …`).

If you are new, do these in order:
1) `bin/setup`
2) Activate the repo Ruby (`mise`)
3) `bin/dev`
4) `bd context --json` + run a probe script

---

## 1) Prereqs

### 1.1 OS packages

`bin/setup` installs what it can. If you’re on macOS, make sure Homebrew is installed. If you’re on Linux, ensure you can `sudo` install packages (Arch: `pacman` path is supported in `bin/setup`).

Beads uses Dolt; on macOS `bin/setup` installs `dolt` via Homebrew. If `dolt` is missing on your machine, install it before debugging Beads:

```bash
brew install dolt
```

### 1.2 Docker (optional)

Only required if you want **MySQL** (`DATABASE_ADAPTER=mysql`). SQLite is the default in OSS.

---

## 2) Initial setup

Run:

```bash
bin/setup
```

Notes:
- `bin/setup` installs `gum`, `mise`, and `gh` if missing, then runs `bundle install`, then `rails db:prepare`, then seeds if needed.
- `bin/setup --reset` will reset the Rails DB (`rails db:reset`).

---

## 3) Activate the repo Ruby in your shell (required)

`bin/setup` installs Ruby via `mise`, but that activation does not persist into new shells.

Before running any `bin/rails` / `bin/dev` / `bundle` commands in a fresh shell, run:

```bash
eval "$(mise hook-env -s zsh)"   # if you use zsh
# or:
eval "$(mise hook-env -s bash)"  # if you use bash
```

Sanity check:

```bash
ruby -v
```

Expected: `ruby 3.4.8` (matches `.ruby-version`).

---

## 4) Boot the app

Run:

```bash
bin/dev
```

Expected:
- URL: `http://app.fizzy.localhost:3006/`
- Login: `david@example.com`

HTTP check:

```bash
curl -I http://app.fizzy.localhost:3006/
```

(A `302` to `/session/menu` is normal.)

---

## 5) Beads + Dolt: status + basic queries

### 5.1 Confirm Beads context

```bash
bd context --json
bd dolt status
```

Expected (shape):
- `backend: dolt`
- `dolt_mode: server`
- server host/port printed (port is typically recorded in `.beads/dolt-server.port`)

### 5.2 Direct Dolt SQL (optional)

```bash
cd .beads/dolt/fizzy
dolt sql -q "select count(*) from issues"
```

---

## 6) Rails ↔ Beads probes (P2 proof scripts)

These scripts exist to prove connectivity and to serve as a reference for P3 (data-path decision).

### 6.1 Rails shells out to `bd` (CLI path)

```bash
bin/rails runner bin/p2-rails-bd-probe.rb
```

### 6.2 Rails connects to Dolt SQL server via `trilogy` (SQL path)

```bash
bin/rails runner bin/p2-rails-dolt-probe.rb
```

---

## 7) Troubleshooting

### 7.1 “Run `bundle install` first” but you already did

If `bin/dev` or `bin/rails` complains that Rails git deps are not checked out, you are almost certainly running with **system Ruby** instead of the repo Ruby.

Fix:

```bash
eval "$(mise hook-env -s zsh)"
```

Then retry `bin/dev`.

### 7.2 Dolt server not running

If Beads commands fail due to Dolt server not running:

```bash
bd dolt start
bd dolt status
```

---

## 8) Related skills

- Session bookends + security posture: `skills/session-lifecycle.md`
- Beads workflow rules: `skills/bd-discipline.md`
