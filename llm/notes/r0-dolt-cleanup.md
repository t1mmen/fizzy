# R0 — Dual Dolt cleanup (Codex)

**Date**: 2026-04-17 (America/Vancouver)

Goal (per Claude/Timm): eliminate the “dual Dolt” state in `.beads/`, pick a single canonical Beads DB (Dolt, server mode), migrate the 2 existing issues safely, and make `bd` consistent. Keep scope to plumbing only.

---

## 1) Diagnosis (what is true right now)

### 1.1 What `bd` reads from (canonical)

`bd context --json` (abridged) shows `bd` is operating in **Dolt server mode**:
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

`bd where --json` points the canonical DB path at:
```json
{
  "path": "/Users/timmstokke/work/fizzy/.beads",
  "database_path": "/Users/timmstokke/work/fizzy/.beads/dolt"
}
```

Before migration, this server DB had **0 issues**:
```bash
cd .beads/dolt/fizzy
dolt sql -q "select count(*) as n from issues"
# n = 0
```

That’s why `bd list` initially returned “No issues found.”

---

### 1.2 What `.beads/*` declares

`.beads/metadata.json` declares server mode (so the “metadata says embedded” mismatch is no longer present):
```json
{
  "backend": "dolt",
  "dolt_mode": "server",
  "dolt_database": "fizzy"
}
```

`.beads/config.yaml` is just commented defaults (no canonical DB declaration; integration config lives in the DB).

---

### 1.3 Where the Dolt server points

`bd dolt status` shows the Dolt sql-server is running against `.beads/dolt`:
```text
Dolt server: running
  PID:  65478
  Port: 54309
  Data: /Users/timmstokke/work/fizzy/.beads/dolt
```

Note: Claude’s message referenced PID 19114 / port 53365. At the time of this work, PID 19114 was **not running**; Beads had restarted / chosen a new port. The running server port is stored in `.beads/dolt/.dolt/sql-server.info` and also reflected in `.beads/dolt-server.pid` + `.beads/dolt-server.port`.

---

### 1.4 Where the 2 existing issues actually were

The 2 issues were in the embedded Dolt repo:
```bash
cd .beads/embeddeddolt/fizzy
dolt sql -q "select count(*) as n from issues"
# n = 2
```

And the embedded schema is **older / incompatible** with current `bd` expectations:
- Server issues table includes `started_at` (present in `.beads/dolt/fizzy`).
- Embedded issues table does **not** include `started_at` (absent in `.beads/embeddeddolt/fizzy`).

This explains why trying to point `bd` at embedded produced:
```text
Error 1105 (HY000): column "started_at" could not be found in any table in scope
```

So: the “dual Dolt mess” was not just two databases — it was two **schema generations**.

---

## 2) Plan (chosen canonical + migration approach)

Canonical DB: **`.beads/dolt` (Dolt server mode)**, because:
- Matches `bd context` and current CLI behavior.
- Has the current Beads schema (`started_at` present).
- Required per Timm: Dolt is source-of-truth; schema immutable moving forward.

Migration approach:
1. **Backup embedded issues** to JSONL (portable, human-readable).
2. Transform timestamps to **RFC3339** (required by `bd import`).
3. `bd import <jsonl>` into canonical server DB.
4. Backup canonical DB to JSONL post-import.
5. Rename embedded directory to `.beads/_deprecated_embeddeddolt` (no delete).
6. Verify `bd list`, then create/delete a throwaway issue to prove writes go to canonical.

---

## 3) Execution log

### 3.1 Backups (embedded → JSONL)

Generated backup JSONL directly from embedded Dolt tables (issues + labels) to:
- `llm/notes/r0-dolt-cleanup/embedded-export-20260417T190344Z.jsonl`

Then rewrote timestamps from `YYYY-MM-DD HH:MM:SS` to RFC3339 `...Z`:
- `llm/notes/r0-dolt-cleanup/embedded-export-rfc3339-20260417T190408Z.jsonl`

Example line (RFC3339):
```json
{"id":"fizzy-jul","title":"Get started","created_at":"2026-04-17T17:45:30Z", ...}
```

---

### 3.2 Import into canonical server DB

```bash
bd import llm/notes/r0-dolt-cleanup/embedded-export-rfc3339-20260417T190408Z.jsonl
```

Output:
```text
Imported 2 issues from llm/notes/r0-dolt-cleanup/embedded-export-rfc3339-20260417T190408Z.jsonl
```

Canonical export after import:
- `llm/notes/r0-dolt-cleanup/canonical-export-after-import-20260417T1204PDT.jsonl`

---

### 3.3 Deprecate embedded repo (no delete)

```bash
mv .beads/embeddeddolt .beads/_deprecated_embeddeddolt
```

---

## 4) Verification (requested checks)

### 4.1 `bd list` shows both original issues

```text
○ fizzy-0zx ● P1 Sample comprehensive issue
○ fizzy-jul ● P2 Get started
```

### 4.2 Create a throwaway issue in canonical DB

```bash
bd q "R0 dolt cleanup throwaway (will delete)"
```

Output:
```text
fizzy-y2t
```

Verified present:
```bash
bd show fizzy-y2t --json
```

### 4.3 Delete the throwaway issue

Pre-delete backup including the throwaway:
- `llm/notes/r0-dolt-cleanup/canonical-export-with-throwaway-20260417T1205PDT.jsonl`

Delete:
```bash
bd delete fizzy-y2t --force
```

Output:
```text
✓ Deleted fizzy-y2t
  Removed 0 dependency link(s)
  Updated text references in 0 issue(s)
```

Verified deleted:
- `bd list` returns only the 2 original issues
- `bd show fizzy-y2t --json` returns “no issue found”

---

## 5) Residual concerns / follow-ups

1. **Schema drift between embedded and server DBs was real.** Embedded lacked `started_at` and appears to have been created by an older Beads version; current `bd` can’t reliably operate on it. Keeping `.beads/_deprecated_embeddeddolt` is useful for forensic recovery if anything looks off later.
2. **Port config mismatch is non-blocking but mildly confusing.** The running port is authoritative via `.beads/dolt/.dolt/sql-server.info` + `bd context`; `.beads/dolt/config.yaml` still contains an older port value.
3. **`bd dolt push` currently fails for the configured `git+https://…` remote.** Exact failure:
   ```text
   Error 1105 (HY000): unknown push error; addTableFiles, updateManifestAddFiles: git command failed (exit 1)
   command: git push --porcelain --force-with-lease=refs/dolt/data: origin refs/dolt/blobstore/origin/dolt/data/<uuid>:refs/dolt/data
   output:
   │  > git rev-parse --path-format=absolute --show-toplevel --git-path hooks --git-path info --git-dir
   │    fatal: this operation must be run in a work tree
   │
   exit status 128
   error: failed to push some refs to 'https://github.com/t1mmen/fizzy.git'
   ```
   This looks like Dolt invoking `git rev-parse --show-toplevel` from a non-worktree context during the `git+https` push path.
4. **Mitigation options (not executed here):**
   - Change the Dolt remote to a non-`git+https` remote (e.g., `file://…` for local sync, or a proper Dolt remote like DoltHub) and use `bd dolt push` against that instead.
   - As an interim “transport”, `.beads/issues.jsonl` is present and can be imported via `bd import` on another clone, but canonical remains the server-mode Dolt DB at `.beads/dolt`.
