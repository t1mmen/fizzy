# Fizzy

This file provides guidance to AI coding agents working with this repository.

## What is Fizzy?

Fizzy is a collaborative project management and issue tracking application built by 37signals/Basecamp. It's a kanban-style tool for teams to create and manage cards (tasks/issues) across boards, organize work into columns representing workflow stages, and collaborate via comments, mentions, and assignments.

## Development Commands

### Setup and Server
```bash
bin/setup              # Initial setup (installs gems, creates DB, loads schema)
bin/dev                # Start development server (runs on port 3006)
```

Development URL: http://app.fizzy.localhost:3006
Login with: david@example.com (development fixtures), password will appear in the browser console

### Testing
```bash
bin/rails test                    # Run unit tests (fast)
bin/rails test test/path/file_test.rb  # Run single test file
bin/rails test:system             # Run system tests (Capybara + Selenium)
bin/ci                            # Run full CI suite (style, security, tests)

# For parallel test execution issues, use:
PARALLEL_WORKERS=1 bin/rails test
```

CI pipeline (`bin/ci`) runs:
1. Rubocop (style)
2. Bundler audit (gem security)
3. Importmap audit
4. Brakeman (security scan)
5. Application tests
6. System tests

### Database
```bash
bin/rails db:fixtures:load   # Load fixture data
bin/rails db:migrate          # Run migrations
bin/rails db:reset            # Drop, create, and load schema
```

### Other Utilities
```bash
bin/rails dev:email          # Toggle letter_opener for email preview
bin/jobs                     # Manage Solid Queue jobs
bin/kamal deploy             # Deploy (requires 1Password CLI for secrets)
```

## Deploy

Default branch: `main`
Pre-deploy: `bin/rails saas:enable`
Deploy: `bin/kamal deploy -d <destination>`
Destinations: production, staging, beta, beta1, beta2, beta3, beta4
Note: `beta` is a template requiring `BETA_NUMBER` env var; typical targets are `beta1`-`beta4`.

## Architecture Overview

### Multi-Tenancy (URL-Based)

Fizzy uses **URL path-based multi-tenancy**:
- Each Account (tenant) has a unique `external_account_id` (7+ digits)
- URLs are prefixed: `/{account_id}/boards/...`
- Middleware (`AccountSlug::Extractor`) extracts the account ID from the URL and sets `Current.account`
- The slug is moved from `PATH_INFO` to `SCRIPT_NAME`, making Rails think it's "mounted" at that path
- All models include `account_id` for data isolation
- Background jobs automatically serialize and restore account context

**Key insight**: This architecture allows multi-tenancy without subdomains or separate databases, making local development and testing simpler.

### Authentication & Authorization

**Passwordless magic link authentication**:
- Global `Identity` (email-based) can have `Users` in multiple Accounts
- Users belong to an Account and have roles: owner, admin, member, system
- Sessions managed via signed cookies
- Board-level access control via `Access` records

### Core Domain Models

**Account** → The tenant/organization
- Has users, boards, cards, tags, webhooks
- Has entropy configuration for auto-postponement

**Identity** → Global user (email)
- Can have Users in multiple Accounts
- Session management tied to Identity

**User** → Account membership
- Belongs to Account and Identity
- Has role (owner/admin/member/system)
- Board access via explicit `Access` records

**Board** → Primary organizational unit
- Has columns for workflow stages
- Can be "all access" or selective
- Can be published publicly with shareable key

**Card** → Main work item (task/issue)
- Sequential number within each Account
- Rich text description and attachments
- Lifecycle: triage → columns → closed/not_now
- Automatically postpones after inactivity ("entropy")

**Event** → Records all significant actions
- Polymorphic association to changed object
- Drives activity timeline, notifications, webhooks
- Has JSON `particulars` for action-specific data

### Entropy System

Cards automatically "postpone" (move to "not now") after inactivity:
- Account-level default entropy period
- Board-level entropy override
- Prevents endless todo lists from accumulating
- Configurable via Account/Board settings

### UUID Primary Keys

All tables use UUIDs (UUIDv7 format, base36-encoded as 25-char strings):
- Custom fixture UUID generation maintains deterministic ordering for tests
- Fixtures are always "older" than runtime records
- `.first`/`.last` work correctly in tests

### Background Jobs (Solid Queue)

Database-backed job queue (no Redis):
- Custom `FizzyActiveJobExtensions` prepended to ActiveJob
- Jobs automatically capture/restore `Current.account`
- Mission Control::Jobs for monitoring

Key recurring tasks (via `config/recurring.yml`):
- Deliver bundled notifications (every 30 min)
- Auto-postpone stale cards (hourly)
- Cleanup jobs for expired links, deliveries

### Sharded Full-Text Search

16-shard MySQL full-text search instead of Elasticsearch:
- Shards determined by account ID hash (CRC32)
- Search records denormalized for performance
- Models in `app/models/search/`

### Imports and exports

Allow people to move between OSS and SAAS Fizzy instances:
- Exports/Imports can be written to/read from local or S3 storage depending on the config of the instance (both must be supported)
- Must be able to handle very large ZIP files (500+GB)
- Models in `app/models/account/data_transfer/`, `app/models/zip_file`

## Tools

### Chrome MCP (Local Dev)

URL: `http://app.fizzy.localhost:3006`
Login: david@example.com (passwordless magic link auth - check rails console for link)

Use Chrome MCP tools to interact with the running dev app for UI testing and debugging.

## Coding style

@STYLE.md

## Multi-Agent File Ownership

This repository is operated by three coordinating agents: `fizzy-claude`, `fizzy-codex`, and `fizzy-gemini`. To prevent accidental data loss when working trees show unexpected diffs, the following rules are non-negotiable.

### Owned files (do NOT touch unless you are the owner)

| File | Owner |
|---|---|
| `llm/claude-state.md` | `fizzy-claude` only |
| `llm/codex-state.md` | `fizzy-codex` only |
| `llm/gemini-state.md` | `fizzy-gemini` only |

If a peer's state file has uncommitted modifications in your working tree:
1. **Do not revert.** That destroys peer work-in-progress.
2. **Commit it on their behalf** with a message like `<round>: persist <peer>-state.md (peer's progress tracking)` and push.
3. Ping the owner via tmux so they pull and continue from a clean tree.

### Unknown files (do NOT touch)

If you encounter a file in your tree that you do not recognize and cannot trace to your current round's writable scope:
- Leave it alone.
- Do not delete, revert, edit, or "clean up" it.
- Ping the responsible agent or the CEO and ask before any destructive action.

This rule applies even when the file looks like junk. "Looks like junk" has historically been peer in-progress work or CEO-staged context. Verify before destroying.

### Shared files (open to all agents, but follow protocol)

- `llm/LOG.md` — append-only by all agents per `llm/README.md`
- `.beads/issues.jsonl` — produced by `bd` commands; commit but do not hand-edit
- `llm/notes/<round>-*.md` — round artifacts; only the drafter edits during draft phase, peers only when reviewing per `skills/round-protocol.md`
- Code files — owned by the implementation round currently consuming them (per round writable-scope declaration)

### Commit discipline (added 2026-04-18 per CEO directive)

Multi-agent shared working tree means uncommitted changes are visible to and may interfere with peers. To prevent loss-of-work + cross-attribution + ownership confusion, follow these rules strictly:

1. **Each agent only commits its OWN work.** If your `git status` shows files you didn't author, do NOT include them in your commit. Either commit-on-behalf with a clear "persist <peer> work on their behalf" message, OR wait for the owning peer to commit (preferred: ping them via tmux first).

2. **Don't interfere with a peer's mid-commit.** If you see staged or recently-modified files belonging to another agent, do NOT `git reset HEAD`, do NOT `git stash`, do NOT `git restore`. Wait. Ping the owning agent via tmux: "I see uncommitted X — yours? Commit when ready, blocking my Y."

3. **Commit happens IMMEDIATELY after edit — no long staging periods.** Edit → test → commit → push. Aim for <2 minutes between first save and `git push`. Never leave files unstaged on disk while you go work on something else.

4. **Stage ONLY your own files explicitly by path.** Avoid `git add .`, `git add -A`, `git add -u` — these sweep up peer work + auto-generated drift (e.g. `db/cable_schema.rb` regression from cross-adapter migrations). Always `git add path/to/your/file.rb path/to/your/test.rb`.

5. **`git stash` is destructive across agents.** A stashed-on-behalf-of-peer is the equivalent of "I revert your work into a sidekick storage." Per rule 2: don't do this; commit-on-behalf instead.

6. **If a commit fails (lefthook gripe, conflict, etc.) — debug and retry within minutes, not hours.** Long-pending failures leave the tree dirty for peers.

### Failure mode log

- **2026-04-18**: Codex investigated uncommitted `llm/gemini-state.md` and almost reverted it as "stray junk". CEO intervened. Recovery: Claude committed gemini-state on Gemini's behalf and pushed; Codex pulled. Lesson encoded above.

- **2026-04-18**: Claude shipped fizzy-7ka + fizzy-ml5 drop migrations (Card::Goldness/ActivitySpike tables) but did not also ship the corresponding model + concern + JS removal. Test suite + app boot broke via `load_schema!` "Could not find table" errors. Recovery: forward-restore migrations (`f3828d4d4`) re-created the tables; both beads reopened with detailed cleanup-prerequisite notes. Lesson: when a migration drops a table, confirm via grep that NO model class references it; if any do, the table-drop bead requires a code-cleanup prerequisite bead.

- **2026-04-18**: Claude attempted fizzy-c3z (Storage quota enforcement) work spanning 4 files, left them uncommitted on disk while doing other work. Codex pulled, saw "stray uncommitted code" not theirs, stashed it for safekeeping. Claude's stash recovery was incomplete (mixed with Codex's CommandClient files); CEO intervened. Recovery: stash dropped; c3z stays open for a re-attempt with strict commit discipline (per rules above). Lesson: codified rules 1-6 above.

<!-- BEGIN BEADS INTEGRATION v:1 profile:minimal hash:ca08a54f -->
## Beads Issue Tracker

This project uses **bd (beads)** for issue tracking. Run `bd prime` to see full workflow context and commands.

### Quick Reference

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> --claim  # Claim work
bd close <id>         # Complete work
```

### Rules

- Use `bd` for ALL task tracking — do NOT use TodoWrite, TaskCreate, or markdown TODO lists
- Run `bd prime` for detailed command reference and session close protocol
- Use `bd remember` for persistent knowledge — do NOT use MEMORY.md files

## Session Completion

**When ending a work session**, you MUST complete ALL steps below. Work is NOT complete until `git push` succeeds.

**MANDATORY WORKFLOW:**

1. **File issues for remaining work** - Create issues for anything that needs follow-up
2. **Run quality gates** (if code changed) - Tests, linters, builds
3. **Update issue status** - Close finished work, update in-progress items
4. **PUSH TO REMOTE** - This is MANDATORY:
   ```bash
   git pull --rebase
   bd dolt push
   git push
   git status  # MUST show "up to date with origin"
   ```
5. **Clean up** - Clear stashes, prune remote branches
6. **Verify** - All changes committed AND pushed
7. **Hand off** - Provide context for next session

**CRITICAL RULES:**
- Work is NOT complete until `git push` succeeds
- NEVER stop before pushing - that leaves work stranded locally
- NEVER say "ready to push when you are" - YOU must push
- If push fails, resolve and retry until it succeeds
<!-- END BEADS INTEGRATION -->
