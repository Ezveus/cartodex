---
name: post-deploy-cleanup
description: Use when a cartodex PR has been merged AND deployed to production (not merely merged) — closing out the work, removing the worktree and branches, pruning production backups on the host, or refreshing the development database from production.
---

# Post-deploy cleanup

## Overview

Once a PR is **merged and deployed**, close it out without being asked: verify production,
then remove the working branch everywhere, leave the host exactly one fresh backup, and make
that backup the development database.

**Why:** the branch has no reason to outlive the deploy; the host runs at ~81 % disk with
~1.7 GB free, so backups pile up against a real ceiling; and a dev database older than the last
deploy makes every local measurement describe a state that no longer exists.

Run it after production has been checked — never right after the merge. Deploys are manual
(`gh workflow run ci.yml --ref master`); "deployed" means that run's `deploy` job succeeded —
`gh run watch <run-id>`, or `gh run list --workflow ci.yml --event workflow_dispatch`.

**Steps 3 and 4 are one script, and the user runs it.** Auto mode refuses the production backup
and the promotion of production data (PII) into the dev database, and a refused attempt has
ended a cleanup unfinished. Do not try them by hand. As soon as step 0 passes, hand over the one
line `! /Users/matthieuciappara/Documents/perso/cartodex/bin/refresh-from-prod.sh NNN` with `NNN`
filled in, and carry on with steps 1–2 meanwhile. The script refuses unless the main checkout's `HEAD` is
`origin/master`, its schema dumps carry no uncommitted change and `bin/rails` boots, all checked
before production is touched. It stops on the
first failure and ends on the verifications of step 4 — read its output back rather than
re-running them. **A run that stopped part-way is rerun as is**: it reuses the host's
`post-pr-NNN` backup once sound, a local archive only when it is byte-identical to that backup,
and the dev archive an earlier run took; only a completed run refuses a second one. Sections 3
and 4 below describe what it does.

## 0. Verify production first

`/up` is not enough. Read back out of the container:

- `SELECT MAX(version) FROM schema_migrations` (Rails 8.1 has no `migration_context`);
- the new tables/columns and any partial indexes the deploy shipped
  (`SELECT sql FROM sqlite_master WHERE name = '…'`);
- one probe of the new code itself (a constant, a method that must now exist);
- the public surface (`/archetypes`, `/cards`, `/tournaments`, `/decks/shared` → 200) **plus a
  route that must still refuse** (`/collections` → 302). The 302 is the negative control that
  proves the check is not vacuous.

Running a command in the container:

```bash
ssh root@cartodex.ezveus.eu 'C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1); docker exec -i $C bin/rails runner -' < script.rb
```

The SSH user is `root`. Pipe scripts over stdin (note `-i`) rather than fighting two layers of
quoting. Grep out the `image_processing` warning on stderr.

## 1. Local worktree and branch

```bash
git worktree remove <path> && git branch -d <branch>
```

- From a worktree-isolated session, `ExitWorktree` first.
- **`git worktree remove` destroys the worktree's gitignored `tmp/`** — copy out any note first.
- Agent worktrees (`.claude/worktrees/agent-*`) hold *uncommitted* lane output: diff each against
  `origin/master` before `--force`; their `worktree-agent-*` branches need their own `git branch -D`.
- Worktrees from *other* work are not part of this. `git status` each before touching it.

## 2. Remote branch

```bash
git push origin --delete <branch>
```

## 3. Host: exactly one backup, taken after the deploy

The backup is taken **now, after the deploy** — so it holds the deployed schema. Name it after
the PR:

```bash
ssh root@cartodex.ezveus.eu 'C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1); docker exec $C sqlite3 /rails/storage/production.sqlite3 ".backup /rails/storage/post-pr-NNN.sqlite3"; docker exec $C sqlite3 /rails/storage/post-pr-NNN.sqlite3 "PRAGMA integrity_check;"; docker cp $C:/rails/storage/post-pr-NNN.sqlite3 /tmp/'
```

- `integrity_check` must answer `ok`. Use `.backup`, never `cp` (WAL mode can tear a copy).
- Archive locally as `~/Documents/perso/cartodex-backups/prod-YYYY-MM-DD-post-pr-NNN.sqlite3`.
- Only then delete every **older** backup in `/rails/storage/` (list it first; only
  `production*.sqlite3` must stay). Every backup is kept locally; only the host is pruned.

## 4. Development database = that backup

1. Stop `bin/dev`. Archive the current dev database as
   `~/Documents/perso/cartodex-backups/dev-YYYY-MM-DD-pre-pr-NNN.sqlite3` — the overwrite is not
   reversible, and two deploys on one day mean two refreshes.
2. Copy the backup over `storage/development.sqlite3` and delete any
   `storage/development.sqlite3-wal`/`-shm` left beside it.
3. `bin/rails db:environment:set RAILS_ENV=development` — the dump is stamped `production` and
   every destructive task refuses it otherwise.
4. `bin/rails db:migrate` — expected to be a no-op, since the backup is post-deploy. If it is
   not, the backup was taken from the wrong moment.
5. Verify both ends agree on `MAX(version)` **and row counts** (cards, standings, archetypes,
   decks, tournaments), plus `db:migrate:status` showing zero `down`.

Step 4 is legitimately skipped when dev already matches production on those counts and version —
decide on counts, never on file size.

## Common mistakes

| Mistake | Consequence |
|---|---|
| Cleaning up after the merge, before the deploy | Branch and backup disappear while the deploy can still fail |
| Reusing an older host backup for step 4 | Dev lags production by everything merged since |
| Promoting `./tmp/db-backup/` | Not the backup directory: a 2026-08-30 copy predating `tournament_standings` — destroys the imported sample |
| Skipping `db:environment:set` | Every destructive task refuses the database |
| Pruning the host before `integrity_check` answers `ok` | The only good backup may be the one just deleted |
| Committing the `db/schema.rb` / `db/cable_schema.rb` rewrite after step 4's `db:migrate` | Same lines, reordered to prod's physical column order. For each of the two files, restore it with `git show HEAD:<file> > <file>` only when its sorted lines equal `HEAD`'s sorted lines; any other difference is a real change — leave the file alone and look at it |
