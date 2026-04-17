# P1 — Foundational Gap Inventory: Fizzy ↔ Beads

**Status**: drafting (P1 round in flight)
**Bead**: `fizzy-08o`
**Drafter**: `fizzy-claude`
**Reviewers**: `fizzy-codex` (peer), `fizzy-gemini` (third-lens)
**Brief**: see `llm/notes/p1-brief.md` for scope and AC

This is the foundational input for all S1-S10 spec rounds. Every assertion is grounded with a `path:line` reference or a quoted command output. No paraphrase.

---

## §A — Fizzy domain entities

> **Status**: TODO — Claude to populate from `app/models/`, `db/schema.rb`, `config/initializers/tenanting/account_slug.rb`, `config/routes.rb`, `app/views/**/*.json.jbuilder`.

Each entity gets:
- Model file path + class name
- Schema table + key columns (type, constraints)
- Associations
- State semantics (if any — e.g., Card closure/not_now/entropy)
- Public JSON shape (if exposed via Jbuilder)
- One-line "what this is for"

(To be filled in.)

---

## §B — Beads schema (verified from Dolt)

> **Status**: in progress — Codex to populate from Dolt (`.beads/dolt/fizzy/`).

### Canonical DB location (verified)

Beads task data lives in Dolt at:

- `.beads/dolt/fizzy` (Dolt repo; DB name `fizzy`)

### Tables (verbatim)

Command + output:

```text
$ cd .beads/dolt/fizzy
$ dolt sql -q "show full tables"
+----------------------+------------+
| Tables_in_fizzy      | Table_type |
+----------------------+------------+
| blocked_issues       | VIEW       |
| child_counters       | BASE TABLE |
| comments             | BASE TABLE |
| compaction_snapshots | BASE TABLE |
| config               | BASE TABLE |
| custom_statuses      | BASE TABLE |
| custom_types         | BASE TABLE |
| dependencies         | BASE TABLE |
| events               | BASE TABLE |
| federation_peers     | BASE TABLE |
| interactions         | BASE TABLE |
| issue_counter        | BASE TABLE |
| issue_snapshots      | BASE TABLE |
| issues               | BASE TABLE |
| labels               | BASE TABLE |
| local_metadata       | BASE TABLE |
| metadata             | BASE TABLE |
| ready_issues         | VIEW       |
| repo_mtimes          | BASE TABLE |
| routes               | BASE TABLE |
| schema_migrations    | BASE TABLE |
| wisp_comments        | BASE TABLE |
| wisp_dependencies    | BASE TABLE |
| wisp_events          | BASE TABLE |
| wisp_labels          | BASE TABLE |
| wisps                | BASE TABLE |
+----------------------+------------+
```

### Table purposes (one-line; inferred from schema names/columns)

These are “best effort” inferences. The DDL immediately below is the source of truth.

- `blocked_issues` (VIEW): issues currently blocked (adds `blocked_by_count`) based on `dependencies` + `issues` status.
- `child_counters`: tracks per-parent child numbering (`last_child`) for parent/child relationships.
- `comments`: issue comments (author + text) attached to an `issues.id`.
- `compaction_snapshots`: stores compacted issue JSON blobs per compaction level (audit/restore).
- `config`: key/value config for beads runtime.
- `custom_statuses`: defines custom statuses with a `category` (used by views like `blocked_issues` / `ready_issues`).
- `custom_types`: defines custom `issue_type` values.
- `dependencies`: dependency edges between issues (10 dependency types live in the `type` column).
- `events`: event log for issue changes (field/value changes + comments).
- `federation_peers`: federation peer definitions (cross-repo / cross-project peer config).
- `interactions`: stores tool/LLM interaction logs (prompt/response/errors + issue linkage).
- `issue_counter`: per-prefix monotonically increasing issue id counter (id generation).
- `issue_snapshots`: stores compaction snapshots including `original_content` + archived events.
- `issues`: primary issue/task table (title/description/design/AC/notes/status/type/priority/etc).
- `labels`: join table mapping issue → label strings.
- `local_metadata`: key/value metadata scoped locally (machine/workspace; distinct from `metadata`).
- `metadata`: global key/value metadata (workspace-level).
- `ready_issues` (VIEW): issues “ready to work” (not blocked + not deferred + active/open statuses).
- `repo_mtimes`: caches repo JSONL mtimes (incremental import/export bookkeeping).
- `routes`: prefix → path mapping (routing/integration table; used by beads CLI).
- `schema_migrations`: schema versioning for beads (Dolt SQL migrations).
- `wisp_comments`: comments on `wisps` (wisp analog of `comments`).
- `wisp_dependencies`: dependencies on `wisps` (wisp analog of `dependencies`).
- `wisp_events`: events on `wisps` (wisp analog of `events`).
- `wisp_labels`: labels on `wisps` (wisp analog of `labels`).
- `wisps`: “wisp” issues (infrastructure/agent/molecule/gate/etc; parallel schema to `issues`).

### Schema definitions (verbatim)

Each block below is verbatim output from either:
- `dolt schema show <table>` (BASE TABLE), or
- `dolt sql -q "show create view <view>"` (VIEW).

### `blocked_issues`

```sql
+----------------+---------------------------------------------------------------------------+----------------------+----------------------+
| View           | Create View                                                               | character_set_client | collation_connection |
+----------------+---------------------------------------------------------------------------+----------------------+----------------------+
| blocked_issues | CREATE VIEW `blocked_issues` AS WITH done_frozen AS (                     | utf8mb4              | utf8mb4_0900_bin     |
|                |     SELECT name FROM custom_statuses WHERE category IN ('done', 'frozen') |                      |                      |
|                | )                                                                         |                      |                      |
|                | SELECT                                                                    |                      |                      |
|                |     i.*,                                                                  |                      |                      |
|                |     (SELECT COUNT(*)                                                      |                      |                      |
|                |      FROM dependencies d                                                  |                      |                      |
|                |      WHERE d.issue_id = i.id                                              |                      |                      |
|                |        AND d.type = 'blocks'                                              |                      |                      |
|                |        AND EXISTS (                                                       |                      |                      |
|                |          SELECT 1 FROM issues blocker                                     |                      |                      |
|                |          WHERE blocker.id = d.depends_on_id                               |                      |                      |
|                |            AND blocker.status NOT IN ('closed', 'pinned')                 |                      |                      |
|                |            AND blocker.status NOT IN (SELECT name FROM done_frozen)       |                      |                      |
|                |        )                                                                  |                      |                      |
|                |     ) as blocked_by_count                                                 |                      |                      |
|                | FROM issues i                                                             |                      |                      |
|                | WHERE i.status NOT IN ('closed', 'pinned')                                |                      |                      |
|                |   AND i.status NOT IN (SELECT name FROM done_frozen)                      |                      |                      |
|                |   AND EXISTS (                                                            |                      |                      |
|                |     SELECT 1 FROM dependencies d                                          |                      |                      |
|                |     WHERE d.issue_id = i.id                                               |                      |                      |
|                |       AND d.type = 'blocks'                                               |                      |                      |
|                |       AND EXISTS (                                                        |                      |                      |
|                |         SELECT 1 FROM issues blocker                                      |                      |                      |
|                |         WHERE blocker.id = d.depends_on_id                                |                      |                      |
|                |           AND blocker.status NOT IN ('closed', 'pinned')                  |                      |                      |
|                |           AND blocker.status NOT IN (SELECT name FROM done_frozen)        |                      |                      |
|                |       )                                                                   |                      |                      |
|                |   )                                                                       |                      |                      |
+----------------+---------------------------------------------------------------------------+----------------------+----------------------+
```

### `child_counters`

```sql
child_counters @ working
CREATE TABLE `child_counters` (
  `parent_id` varchar(255) NOT NULL,
  `last_child` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `comments`

```sql
comments @ working
CREATE TABLE `comments` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `author` varchar(255) NOT NULL,
  `text` text NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_comments_created_at` (`created_at`),
  KEY `idx_comments_issue` (`issue_id`),
  CONSTRAINT `fk_comments_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `compaction_snapshots`

```sql
compaction_snapshots @ working
CREATE TABLE `compaction_snapshots` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `compaction_level` int NOT NULL,
  `snapshot_json` blob NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_comp_snap_issue` (`issue_id`,`compaction_level`,`created_at`),
  CONSTRAINT `fk_comp_snap_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `config`

```sql
config @ working
CREATE TABLE `config` (
  `key` varchar(255) NOT NULL,
  `value` text NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `custom_statuses`

```sql
custom_statuses @ working
CREATE TABLE `custom_statuses` (
  `name` varchar(64) NOT NULL,
  `category` varchar(32) NOT NULL DEFAULT 'unspecified',
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `custom_types`

```sql
custom_types @ working
CREATE TABLE `custom_types` (
  `name` varchar(64) NOT NULL,
  PRIMARY KEY (`name`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `dependencies`

```sql
dependencies @ working
CREATE TABLE `dependencies` (
  `issue_id` varchar(255) NOT NULL,
  `depends_on_id` varchar(255) NOT NULL,
  `type` varchar(32) NOT NULL DEFAULT 'blocks',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(255) NOT NULL,
  `metadata` json DEFAULT (json_object()),
  `thread_id` varchar(255) DEFAULT '',
  PRIMARY KEY (`issue_id`,`depends_on_id`),
  KEY `idx_dependencies_depends_on` (`depends_on_id`),
  KEY `idx_dependencies_depends_on_type` (`depends_on_id`,`type`),
  KEY `idx_dependencies_issue` (`issue_id`),
  KEY `idx_dependencies_thread` (`thread_id`),
  CONSTRAINT `fk_dep_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `events`

```sql
events @ working
CREATE TABLE `events` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `event_type` varchar(32) NOT NULL,
  `actor` varchar(255) NOT NULL,
  `old_value` text,
  `new_value` text,
  `comment` text,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_events_created_at` (`created_at`),
  KEY `idx_events_issue` (`issue_id`),
  CONSTRAINT `fk_events_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `federation_peers`

```sql
federation_peers @ working
CREATE TABLE `federation_peers` (
  `name` varchar(255) NOT NULL,
  `repo` varchar(512) NOT NULL,
  `branch` varchar(255) NOT NULL DEFAULT 'main',
  `remote` varchar(255) NOT NULL DEFAULT 'origin',
  `enabled` tinyint(1) NOT NULL DEFAULT '1',
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`name`),
  KEY `idx_fed_enabled` (`enabled`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `interactions`

```sql
interactions @ working
CREATE TABLE `interactions` (
  `id` varchar(32) NOT NULL,
  `kind` varchar(64) NOT NULL,
  `created_at` datetime NOT NULL,
  `actor` varchar(255),
  `issue_id` varchar(255),
  `model` varchar(255),
  `prompt` text,
  `response` text,
  `error` text,
  `tool_name` varchar(255),
  `exit_code` int,
  `parent_id` varchar(32),
  `label` varchar(64),
  `reason` text,
  `extra` json,
  PRIMARY KEY (`id`),
  KEY `idx_interactions_created_at` (`created_at`),
  KEY `idx_interactions_issue_id` (`issue_id`),
  KEY `idx_interactions_kind` (`kind`),
  KEY `idx_interactions_parent_id` (`parent_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `issue_counter`

```sql
issue_counter @ working
CREATE TABLE `issue_counter` (
  `prefix` varchar(255) NOT NULL,
  `last_id` int NOT NULL DEFAULT '0',
  PRIMARY KEY (`prefix`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `issue_snapshots`

```sql
issue_snapshots @ working
CREATE TABLE `issue_snapshots` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `snapshot_time` datetime NOT NULL,
  `compaction_level` int NOT NULL,
  `original_size` int NOT NULL,
  `compressed_size` int NOT NULL,
  `original_content` text NOT NULL,
  `archived_events` text,
  PRIMARY KEY (`id`),
  KEY `idx_snapshots_issue` (`issue_id`),
  KEY `idx_snapshots_level` (`compaction_level`),
  CONSTRAINT `fk_snapshots_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `issues`

```sql
issues @ working
CREATE TABLE `issues` (
  `id` varchar(255) NOT NULL,
  `content_hash` varchar(64),
  `title` varchar(500) NOT NULL,
  `description` text NOT NULL,
  `design` text NOT NULL,
  `acceptance_criteria` text NOT NULL,
  `notes` text NOT NULL,
  `status` varchar(32) NOT NULL DEFAULT 'open',
  `priority` int NOT NULL DEFAULT '2',
  `issue_type` varchar(32) NOT NULL DEFAULT 'task',
  `assignee` varchar(255),
  `estimated_minutes` int,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(255) DEFAULT '',
  `owner` varchar(255) DEFAULT '',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `closed_at` datetime,
  `closed_by_session` varchar(255) DEFAULT '',
  `external_ref` varchar(255),
  `spec_id` varchar(1024),
  `compaction_level` int DEFAULT '0',
  `compacted_at` datetime,
  `compacted_at_commit` varchar(64),
  `original_size` int,
  `sender` varchar(255) DEFAULT '',
  `ephemeral` tinyint(1) DEFAULT '0',
  `no_history` tinyint(1) DEFAULT '0',
  `wisp_type` varchar(32) DEFAULT '',
  `pinned` tinyint(1) DEFAULT '0',
  `is_template` tinyint(1) DEFAULT '0',
  `mol_type` varchar(32) DEFAULT '',
  `work_type` varchar(32) DEFAULT 'mutex',
  `source_system` varchar(255) DEFAULT '',
  `metadata` json DEFAULT (json_object()),
  `source_repo` varchar(512) DEFAULT '',
  `close_reason` text DEFAULT '',
  `event_kind` varchar(32) DEFAULT '',
  `actor` varchar(255) DEFAULT '',
  `target` varchar(255) DEFAULT '',
  `payload` text DEFAULT '',
  `await_type` varchar(32) DEFAULT '',
  `await_id` varchar(255) DEFAULT '',
  `timeout_ns` bigint DEFAULT '0',
  `waiters` text DEFAULT '',
  `due_at` datetime,
  `defer_until` datetime,
  `started_at` datetime,
  PRIMARY KEY (`id`),
  KEY `idx_issues_assignee` (`assignee`),
  KEY `idx_issues_created_at` (`created_at`),
  KEY `idx_issues_external_ref` (`external_ref`),
  KEY `idx_issues_issue_type` (`issue_type`),
  KEY `idx_issues_priority` (`priority`),
  KEY `idx_issues_spec_id` (`spec_id`),
  KEY `idx_issues_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `labels`

```sql
labels @ working
CREATE TABLE `labels` (
  `issue_id` varchar(255) NOT NULL,
  `label` varchar(255) NOT NULL,
  PRIMARY KEY (`issue_id`,`label`),
  KEY `idx_labels_label` (`label`),
  CONSTRAINT `fk_labels_issue` FOREIGN KEY (`issue_id`) REFERENCES `issues` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `local_metadata`

```sql
local_metadata @ working
CREATE TABLE `local_metadata` (
  `key` varchar(255) NOT NULL,
  `value` text NOT NULL DEFAULT '',
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `metadata`

```sql
metadata @ working
CREATE TABLE `metadata` (
  `key` varchar(255) NOT NULL,
  `value` text NOT NULL,
  PRIMARY KEY (`key`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `ready_issues`

```sql
+--------------+---------------------------------------------------------------------------------+----------------------+----------------------+
| View         | Create View                                                                     | character_set_client | collation_connection |
+--------------+---------------------------------------------------------------------------------+----------------------+----------------------+
| ready_issues | CREATE VIEW `ready_issues` AS WITH RECURSIVE                                    | utf8mb4              | utf8mb4_0900_bin     |
|              |   blocked_directly AS (                                                         |                      |                      |
|              |     SELECT DISTINCT d.issue_id                                                  |                      |                      |
|              |     FROM dependencies d                                                         |                      |                      |
|              |     WHERE d.type = 'blocks'                                                     |                      |                      |
|              |       AND EXISTS (                                                              |                      |                      |
|              |         SELECT 1 FROM issues blocker                                            |                      |                      |
|              |         WHERE blocker.id = d.depends_on_id                                      |                      |                      |
|              |           AND blocker.status NOT IN ('closed', 'pinned')                        |                      |                      |
|              |       )                                                                         |                      |                      |
|              |   ),                                                                            |                      |                      |
|              |   blocked_transitively AS (                                                     |                      |                      |
|              |     SELECT issue_id, 0 as depth                                                 |                      |                      |
|              |     FROM blocked_directly                                                       |                      |                      |
|              |     UNION ALL                                                                   |                      |                      |
|              |     SELECT d.issue_id, bt.depth + 1                                             |                      |                      |
|              |     FROM blocked_transitively bt                                                |                      |                      |
|              |     JOIN dependencies d ON d.depends_on_id = bt.issue_id                        |                      |                      |
|              |     WHERE d.type = 'parent-child'                                               |                      |                      |
|              |       AND bt.depth < 50                                                         |                      |                      |
|              |   )                                                                             |                      |                      |
|              | SELECT i.*                                                                      |                      |                      |
|              | FROM issues i                                                                   |                      |                      |
|              | LEFT JOIN blocked_transitively bt ON bt.issue_id = i.id                         |                      |                      |
|              | WHERE (                                                                         |                      |                      |
|              |     i.status = 'open'                                                           |                      |                      |
|              |     OR i.status IN (SELECT name FROM custom_statuses WHERE category = 'active') |                      |                      |
|              |   )                                                                             |                      |                      |
|              |   AND (i.ephemeral = 0 OR i.ephemeral IS NULL)                                  |                      |                      |
|              |   AND bt.issue_id IS NULL                                                       |                      |                      |
|              |   AND (i.defer_until IS NULL OR i.defer_until <= UTC_TIMESTAMP())               |                      |                      |
|              |   AND NOT EXISTS (                                                              |                      |                      |
|              |     SELECT 1 FROM dependencies d_parent                                         |                      |                      |
|              |     JOIN issues parent ON parent.id = d_parent.depends_on_id                    |                      |                      |
|              |     WHERE d_parent.issue_id = i.id                                              |                      |                      |
|              |       AND d_parent.type = 'parent-child'                                        |                      |                      |
|              |       AND parent.defer_until IS NOT NULL                                        |                      |                      |
|              |       AND parent.defer_until > UTC_TIMESTAMP()                                  |                      |                      |
|              |   )                                                                             |                      |                      |
+--------------+---------------------------------------------------------------------------------+----------------------+----------------------+
```

### `repo_mtimes`

```sql
repo_mtimes @ working
CREATE TABLE `repo_mtimes` (
  `repo_path` varchar(512) NOT NULL,
  `jsonl_path` varchar(512) NOT NULL,
  `mtime_ns` bigint NOT NULL,
  `last_checked` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`repo_path`),
  KEY `idx_repo_mtimes_checked` (`last_checked`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `routes`

```sql
routes @ working
CREATE TABLE `routes` (
  `prefix` varchar(32) NOT NULL,
  `path` varchar(512) NOT NULL,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`prefix`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `schema_migrations`

```sql
schema_migrations @ working
CREATE TABLE `schema_migrations` (
  `version` varchar(255) NOT NULL,
  PRIMARY KEY (`version`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `wisp_comments`

```sql
wisp_comments @ working
CREATE TABLE `wisp_comments` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `author` varchar(255) NOT NULL DEFAULT '',
  `text` text NOT NULL DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_wisp_comments_created_at` (`created_at`),
  KEY `idx_wisp_comments_issue` (`issue_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `wisp_dependencies`

```sql
wisp_dependencies @ working
CREATE TABLE `wisp_dependencies` (
  `issue_id` varchar(255) NOT NULL,
  `depends_on_id` varchar(255) NOT NULL,
  `type` varchar(32) NOT NULL DEFAULT 'blocks',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(255) NOT NULL DEFAULT '',
  `metadata` json DEFAULT (json_object()),
  PRIMARY KEY (`issue_id`,`depends_on_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `wisp_events`

```sql
wisp_events @ working
CREATE TABLE `wisp_events` (
  `id` char(36) NOT NULL DEFAULT (uuid()),
  `issue_id` varchar(255) NOT NULL,
  `event_type` varchar(32) NOT NULL,
  `actor` varchar(255) DEFAULT '',
  `old_value` text DEFAULT '',
  `new_value` text DEFAULT '',
  `comment` text DEFAULT '',
  `created_at` datetime DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_wisp_events_created_at` (`created_at`),
  KEY `idx_wisp_events_issue` (`issue_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `wisp_labels`

```sql
wisp_labels @ working
CREATE TABLE `wisp_labels` (
  `issue_id` varchar(255) NOT NULL,
  `label` varchar(255) NOT NULL,
  PRIMARY KEY (`issue_id`,`label`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

### `wisps`

```sql
wisps @ working
CREATE TABLE `wisps` (
  `id` varchar(255) NOT NULL,
  `content_hash` varchar(64),
  `title` varchar(500) NOT NULL,
  `description` text NOT NULL DEFAULT '',
  `design` text NOT NULL DEFAULT '',
  `acceptance_criteria` text NOT NULL DEFAULT '',
  `notes` text NOT NULL DEFAULT '',
  `status` varchar(32) NOT NULL DEFAULT 'open',
  `priority` int NOT NULL DEFAULT '2',
  `issue_type` varchar(32) NOT NULL DEFAULT 'task',
  `assignee` varchar(255),
  `estimated_minutes` int,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(255) DEFAULT '',
  `owner` varchar(255) DEFAULT '',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `closed_at` datetime,
  `closed_by_session` varchar(255) DEFAULT '',
  `external_ref` varchar(255),
  `spec_id` varchar(1024),
  `compaction_level` int DEFAULT '0',
  `compacted_at` datetime,
  `compacted_at_commit` varchar(64),
  `original_size` int,
  `sender` varchar(255) DEFAULT '',
  `ephemeral` tinyint(1) DEFAULT '0',
  `no_history` tinyint(1) DEFAULT '0',
  `wisp_type` varchar(32) DEFAULT '',
  `pinned` tinyint(1) DEFAULT '0',
  `is_template` tinyint(1) DEFAULT '0',
  `mol_type` varchar(32) DEFAULT '',
  `work_type` varchar(32) DEFAULT 'mutex',
  `source_system` varchar(255) DEFAULT '',
  `metadata` json DEFAULT (json_object()),
  `source_repo` varchar(512) DEFAULT '',
  `close_reason` text DEFAULT '',
  `event_kind` varchar(32) DEFAULT '',
  `actor` varchar(255) DEFAULT '',
  `target` varchar(255) DEFAULT '',
  `payload` text DEFAULT '',
  `await_type` varchar(32) DEFAULT '',
  `await_id` varchar(255) DEFAULT '',
  `timeout_ns` bigint DEFAULT '0',
  `waiters` text DEFAULT '',
  `hook_bead` varchar(255) DEFAULT '',
  `role_bead` varchar(255) DEFAULT '',
  `agent_state` varchar(32) DEFAULT '',
  `last_activity` datetime,
  `role_type` varchar(32) DEFAULT '',
  `rig` varchar(255) DEFAULT '',
  `due_at` datetime,
  `defer_until` datetime,
  `started_at` datetime,
  PRIMARY KEY (`id`),
  KEY `idx_wisps_assignee` (`assignee`),
  KEY `idx_wisps_created_at` (`created_at`),
  KEY `idx_wisps_external_ref` (`external_ref`),
  KEY `idx_wisps_issue_type` (`issue_type`),
  KEY `idx_wisps_priority` (`priority`),
  KEY `idx_wisps_spec_id` (`spec_id`),
  KEY `idx_wisps_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

---

## §C — Mapping table (Fizzy ↔ Beads)

> **Status**: TODO — built from §A + §B. Each row marked with one of:
> - `[Beads-native]` — beads field exists; Fizzy maps directly
> - `[Beads-equivalent (with adapter)]` — beads concept exists but field shape differs; needs an adapter
> - `[Fizzy-only]` — no beads equivalent; stays in Fizzy MySQL with FK to beads issue id
> - `[Hybrid]` — split across beads + Fizzy (e.g., beads holds plaintext description, Fizzy holds rich-text version with FK)
> - `[Drop in fork]` — feature does not survive the fork (e.g., Fizzy multi-tenancy retired per Q3 ii)

| Fizzy entity / field | Beads target | Mapping | Adapter needed | Notes |
|---|---|---|---|---|
| (TBD — populated row-by-row) | | | | |

---

## §D — Verified assumptions (CEO-flagged + emergent)

> **Status**: in progress — Beads-side verification populated (items 1–7, 10). Fizzy-side items (8–9) to be populated by Claude with `path:line` evidence.

### Evidence (verbatim command outputs)

**D-1 — `issues.description` is a plain `text` column (storage is not “rich text typed”).**

```sql
$ cd .beads/dolt/fizzy
$ dolt schema show issues
issues @ working
CREATE TABLE `issues` (
  `id` varchar(255) NOT NULL,
  `content_hash` varchar(64),
  `title` varchar(500) NOT NULL,
  `description` text NOT NULL,
  `design` text NOT NULL,
  `acceptance_criteria` text NOT NULL,
  `notes` text NOT NULL,
  `status` varchar(32) NOT NULL DEFAULT 'open',
  `priority` int NOT NULL DEFAULT '2',
  `issue_type` varchar(32) NOT NULL DEFAULT 'task',
  `assignee` varchar(255),
  `estimated_minutes` int,
  `created_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_by` varchar(255) DEFAULT '',
  `owner` varchar(255) DEFAULT '',
  `updated_at` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `closed_at` datetime,
  `closed_by_session` varchar(255) DEFAULT '',
  `external_ref` varchar(255),
  `spec_id` varchar(1024),
  `compaction_level` int DEFAULT '0',
  `compacted_at` datetime,
  `compacted_at_commit` varchar(64),
  `original_size` int,
  `sender` varchar(255) DEFAULT '',
  `ephemeral` tinyint(1) DEFAULT '0',
  `no_history` tinyint(1) DEFAULT '0',
  `wisp_type` varchar(32) DEFAULT '',
  `pinned` tinyint(1) DEFAULT '0',
  `is_template` tinyint(1) DEFAULT '0',
  `mol_type` varchar(32) DEFAULT '',
  `work_type` varchar(32) DEFAULT 'mutex',
  `source_system` varchar(255) DEFAULT '',
  `metadata` json DEFAULT (json_object()),
  `source_repo` varchar(512) DEFAULT '',
  `close_reason` text DEFAULT '',
  `event_kind` varchar(32) DEFAULT '',
  `actor` varchar(255) DEFAULT '',
  `target` varchar(255) DEFAULT '',
  `payload` text DEFAULT '',
  `await_type` varchar(32) DEFAULT '',
  `await_id` varchar(255) DEFAULT '',
  `timeout_ns` bigint DEFAULT '0',
  `waiters` text DEFAULT '',
  `due_at` datetime,
  `defer_until` datetime,
  `started_at` datetime,
  PRIMARY KEY (`id`),
  KEY `idx_issues_assignee` (`assignee`),
  KEY `idx_issues_created_at` (`created_at`),
  KEY `idx_issues_external_ref` (`external_ref`),
  KEY `idx_issues_issue_type` (`issue_type`),
  KEY `idx_issues_priority` (`priority`),
  KEY `idx_issues_spec_id` (`spec_id`),
  KEY `idx_issues_status` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_bin;
```

**D-2 — Current issues in this repo have empty JSON metadata.**

```sql
$ cd .beads/dolt/fizzy
$ dolt sql -q "select id, JSON_LENGTH(metadata) as metadata_len, metadata from issues"
+-----------+--------------+----------+
| id        | metadata_len | metadata |
+-----------+--------------+----------+
| fizzy-08o | 0            | {}       |
| fizzy-0zx | 0            | {}       |
| fizzy-jul | 0            | {}       |
+-----------+--------------+----------+
```

**D-3 — Beads export is JSONL; the exported “issue object” shape is not 1:1 with raw Dolt columns.**

```json
$ bd export --no-memories | head -n 2
{"id":"fizzy-08o","title":"P1: Foundational Gap Inventory — Fizzy ↔ Beads","description":"First Planning round of the 20-round program. Produces a comprehensive single source of truth at llm/notes/p1-foundational-gap-inventory.md covering five sections: A) every Fizzy domain entity + field with file:line refs; B) every beads schema field; C) mapping table (Fizzy → beads OR Fizzy-only OR hybrid); D) verified-assumption table for CEO-flagged items (rich text, attachments, mentions, reactions, search, deps); E) numbered architectural questions surfaced for S* rounds. This is the foundational input for all S1-S10 spec rounds.","acceptance_criteria":"Five sections (A-E) populated; quoted command outputs / file:line refs throughout; no vague AC; ratified by Claude+Codex+Gemini via [P1: agreed] signals.","status":"open","priority":1,"issue_type":"task","assignee":"fizzy-claude","owner":"timm@stokke.me","created_at":"2026-04-17T20:41:13Z","created_by":"Timm Stokke","updated_at":"2026-04-17T20:41:13Z","labels":["foundational","gap-analysis","planning"],"dependency_count":0,"dependent_count":0,"comment_count":0}
{"id":"fizzy-0zx","title":"Sample comprehensive issue","description":"This is a detailed description to test the data model","design":"Using MVC pattern","acceptance_criteria":"All tests pass","status":"open","priority":1,"issue_type":"task","assignee":"timm@stokke.me","owner":"timm@stokke.me","estimated_minutes":480,"created_at":"2026-04-17T18:16:54Z","created_by":"Timm Stokke","updated_at":"2026-04-17T18:16:54Z","labels":["data-model","test"],"dependency_count":0,"dependent_count":0,"comment_count":0}
```

**D-4 — Beads search exists, but the help describes title/ID search + substring filters; no dedicated FTS schema is visible in Dolt.**

```text
$ bd search --help | sed -n '1,12p'
Search issues across title and ID (excludes closed issues by default).

ID-like queries (e.g., "bd-123", "hq-319") use fast exact/prefix matching.
Text queries search titles. Use --desc-contains for description search.
Use --status all to include closed issues.
```

**D-5 — 10 dependency types are supported by `bd dep add --type`.**

```text
$ bd dep add --help | grep -F "Dependency type"
  -t, --type string         Dependency type (blocks|tracks|related|parent-child|discovered-from|until|caused-by|validates|relates-to|supersedes) (default "blocks")
```

**D-6 — `bd link` is a shorthand that supports only 5 dependency types.**

```text
$ bd link --help | grep -F "Dependency type"
  -t, --type string   Dependency type (blocks|tracks|related|parent-child|discovered-from) (default "blocks")
```

### Verdict table

| Assumption | Verdict | Evidence | Implication for §C mapping |
|---|---|---|---|
| 1) Beads description supports rich text / markdown | `PARTIAL` | D-1 (storage is `text`); D-3 (export shows plain strings) | Any “markdown” is a rendering convention. If Fizzy needs rich text (attachments/mentions), it likely lives in Fizzy tables keyed by `issues.id`, or in `issues.metadata` as a convention. |
| 2) Beads supports attachments | `REFUTED` (native) / `PARTIAL` (possible via `metadata`) | §B shows no attachment/blob tables; D-1 shows only `metadata json` as an extension point; D-2 shows `{}` currently | Attachments likely remain Fizzy-side (ActiveStorage) with FK to beads `issues.id`. If we ever store attachment refs in beads, it’s via `issues.metadata` (convention) not a first-class schema. |
| 3) Beads supports mentions | `REFUTED` (native) | §B: no mentions table; D-1 shows only `description`/`notes` text and `metadata json` | Mentions are Fizzy-side behavior (parse + render) and likely stored in Fizzy-only tables or computed at render time. |
| 4) Beads supports reactions | `REFUTED` (native) | §B: no reactions table; comments are plain `text` (see §B `comments`) | Reactions are Fizzy-only unless we invent a convention in `issues.metadata` (not recommended without spec). |
| 5) Beads has search / FTS | `CONFIRMED` (basic), `REFUTED` (schema-level FTS) | D-4; §B has no obvious FTS index/tables beyond normal secondary indexes | Expect basic search (title/ID) and filters. Anything like Fizzy’s 16-shard MySQL FTS is not present in beads schema. |
| 6) Beads has 10 dependency types | `CONFIRMED` | D-5 | Dependency semantics are beads-native; Fizzy UI should map its relationships onto this set rather than invent new ones. |
| 7) Beads `bd link` supports 5 dependency types | `CONFIRMED` | D-6 | Documentation/templates should use `bd link` only for the five simple types; all others must use `bd dep add --type`. |
| 8) Fizzy has bearer-token JSON API | `TODO (Claude)` | (pending `path:line` in §A) | Mapping needs to decide whether bead-backed API endpoints stay or get deprecated. |
| 9) Fizzy multi-tenancy via path prefix middleware | `TODO (Claude)` | (pending `path:line` in §A) | CEO said multi-tenancy retired; mapping should mark tenanting code as `[Drop in fork]` or “dead” in fork. |
| 10) Beads schema is immutable | `CONFIRMED` (operating constraint) | CEO ground truth; RoE-4 §1 | All feature gaps get handled in adapter + Fizzy-side tables; never by altering Dolt schema. |

---

## §E — Architectural questions for spec phase (S1-S10)

> **Status**: TODO — populated after §A-§D are sufficiently complete.

Numbered questions the spec rounds must answer before implementation. Each:
- ID (`Q-S-001`, `Q-S-002`, …)
- Question (one sentence)
- Affected entities (from §A/§B/§C)
- Why it matters (one sentence)
- Candidate options (if any are obvious)

Seed questions to refine + add to:

- **Q-S-001**: How does Fizzy read beads issues at runtime — shell out to `bd` per request, connect to embedded Dolt server via MySQL protocol, or both?
- **Q-S-002**: Where do Fizzy-side concerns (rich text, attachments, mentions, reactions) physically live — separate MySQL tables FK'd to beads `id`, or stuffed into beads `metadata` JSON?
- **Q-S-003**: How does the kanban "board" + "column" concept project onto beads (which has `labels` + `status` but no native column primitive)?
- **Q-S-004**: How does Fizzy's `Identity::AccessToken` (bearer-token JSON API) coexist with beads' git-identity `actor` model?
- **Q-S-005**: How do Fizzy webhook events get triggered when state changes happen via `bd` CLI rather than via the Fizzy controller?
- (more emerge from §C drafting)

(To be expanded.)

---

## Convergence signal (P1)

When all three agents agree P1 is complete, each sends:

`[FROM→TO P1: agreed]`

After all signals land in `llm/LOG.md`, this file is locked, the bead `fizzy-08o` is closed, and we open P2 with a handoff entry.
