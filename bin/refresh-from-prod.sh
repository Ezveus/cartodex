#!/usr/bin/env bash
# Steps 3 and 4 of the post-deploy-cleanup skill, in one run:
#   3. take a post-deploy backup on the host, check it, archive it locally, prune older host backups;
#   4. make that backup the development database and verify it.
# Usage: bin/refresh-from-prod.sh NNN   (NNN = the PR number)
# Every local precondition is checked before production is touched, and the host is pruned only
# once both the host copy and the local archive answer `ok` to integrity_check.
set -euo pipefail

HOST=root@cartodex.ezveus.eu
TABLES="cards tournament_standings archetypes decks tournaments"
SCHEMA_FILES="db/schema.rb db/cable_schema.rb"

die() { echo "ERROR: $*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }

NNN=${1:-}
[[ "$NNN" =~ ^[0-9]+$ ]] || die "usage: $0 PR_NUMBER"

# Always the main checkout, even when launched from a worktree: that is where bin/dev runs.
ROOT=$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)
cd "$ROOT"
[ -d storage ] || die "$ROOT/storage not found"

TODAY=$(date +%F)
ARCHIVE_DIR="$HOME/Documents/perso/cartodex-backups"
PROD_ARCHIVE="$ARCHIVE_DIR/prod-$TODAY-post-pr-$NNN.sqlite3"
# Named after the PR too: two deploys on one day mean two refreshes, and the second must not
# collide with the first's archive.
DEV_ARCHIVE="$ARCHIVE_DIR/dev-$TODAY-pre-pr-$NNN.sqlite3"
DEV_DB=storage/development.sqlite3
HOST_BACKUP="post-pr-$NNN.sqlite3"

step "Local preconditions"
mkdir -p "$ARCHIVE_DIR"
[ ! -e "$DEV_ARCHIVE" ] || die "$DEV_ARCHIVE already exists — this PR's refresh already ran, check the dev database by hand"
if lsof "$DEV_DB" "$DEV_DB-wal" >/dev/null 2>&1; then
  die "$DEV_DB is open (bin/dev or a console still running) — stop it first"
fi
# An archive already taken for this PR (by hand, or by a run that failed later) is reused rather
# than retaken, provided it is sound.
REUSE_ARCHIVE=false
if [ -e "$PROD_ARCHIVE" ]; then
  R=$(sqlite3 "$PROD_ARCHIVE" "PRAGMA integrity_check;")
  [ "$R" = ok ] || die "$PROD_ARCHIVE exists but integrity_check answered: $R — move it aside and rerun"
  REUSE_ARCHIVE=true
fi
echo "ok"

if $REUSE_ARCHIVE; then
  step "3. Reusing $PROD_ARCHIVE (integrity_check: ok) — host backup skipped"
else # body left unindented: the heredocs' REMOTE terminators must start their line
step "3. Host backup $HOST_BACKUP, integrity_check"
ssh "$HOST" bash -s -- "$HOST_BACKUP" <<'REMOTE'
set -euo pipefail
B=/rails/storage/$1
C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1)
[ -n "$C" ] || { echo "ERROR: no running web container" >&2; exit 1; }
if docker exec "$C" test -e "$B"; then echo "ERROR: $B already exists on the host" >&2; exit 1; fi
docker exec "$C" sqlite3 /rails/storage/production.sqlite3 ".backup $B"
R=$(docker exec "$C" sqlite3 "$B" "PRAGMA integrity_check;")
[ "$R" = ok ] || { echo "ERROR: integrity_check on the host answered: $R" >&2; exit 1; }
echo "integrity_check: ok"
docker cp "$C:$B" "/tmp/$1"
REMOTE

step "3. Local archive $PROD_ARCHIVE"
scp -q "$HOST:/tmp/$HOST_BACKUP" "$PROD_ARCHIVE"
ssh "$HOST" rm -f "/tmp/$HOST_BACKUP"
R=$(sqlite3 "$PROD_ARCHIVE" "PRAGMA integrity_check;")
[ "$R" = ok ] || die "integrity_check on the local archive answered: $R — host left unpruned"
echo "integrity_check: ok"
fi

step "3. Host prune (everything in /rails/storage but production* and $HOST_BACKUP)"
ssh "$HOST" bash -s -- "$HOST_BACKUP" <<'REMOTE'
set -euo pipefail
C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1)
docker exec -e KEEP="$1" "$C" sh -c '
  cd /rails/storage
  for f in *.sqlite3; do
    case "$f" in production*|"$KEEP") ;; *) echo "deleting $f"; rm -f -- "$f" "$f-wal" "$f-shm" ;; esac
  done
  echo "left on the host:"; ls -la /rails/storage
'
REMOTE

step "4. Archive the current dev database"
if [ -e "$DEV_DB" ]; then
  # .backup, not cp: a -wal beside the file may hold pages cp would leave behind.
  sqlite3 "$DEV_DB" ".backup '$DEV_ARCHIVE'"
  echo "$DEV_ARCHIVE"
else
  echo "no $DEV_DB, nothing to archive"
fi

step "4. Promote the backup to $DEV_DB"
cp "$PROD_ARCHIVE" "$DEV_DB"
rm -f "$DEV_DB-wal" "$DEV_DB-shm"
bin/rails db:environment:set RAILS_ENV=development

version() { sqlite3 "$1" "SELECT MAX(version) FROM schema_migrations;"; }
BEFORE=$(version "$DEV_DB")
bin/rails db:migrate
AFTER=$(version "$DEV_DB")
[ "$BEFORE" = "$AFTER" ] || die "db:migrate was not a no-op ($BEFORE -> $AFTER): the backup predates the deploy"

step "4. Schema dumps rewritten by db:migrate"
# db:migrate re-dumps the schema in prod's physical column order. Restore a file only when its
# sorted lines equal HEAD's, i.e. the rewrite is a pure reordering; anything else is a real change.
for f in $SCHEMA_FILES; do
  if git diff --quiet -- "$f"; then
    echo "$f: unchanged"
  elif diff <(git show "HEAD:$f" | sort) <(sort "$f") >/dev/null; then
    git show "HEAD:$f" > "$f"
    echo "$f: reordering only, restored from HEAD"
  else
    die "$f differs from HEAD by more than line order — left as is, inspect it"
  fi
done

step "4. Verification"
DOWN=$(bin/rails db:migrate:status | grep -cE '^[[:space:]]*down' || true)
[ "$DOWN" = 0 ] || die "db:migrate:status shows $DOWN migration(s) down"
echo "migrations down: 0"

PROD_VERSION=$(ssh "$HOST" 'C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1); docker exec $C sqlite3 /rails/storage/production.sqlite3 "SELECT MAX(version) FROM schema_migrations;"')
[ "$PROD_VERSION" = "$AFTER" ] || die "MAX(version): production $PROD_VERSION, dev $AFTER"
echo "MAX(version): $AFTER on both ends"

for t in $TABLES; do
  P=$(sqlite3 "$PROD_ARCHIVE" "SELECT COUNT(*) FROM $t;")
  D=$(sqlite3 "$DEV_DB" "SELECT COUNT(*) FROM $t;")
  [ "$P" = "$D" ] || die "$t: backup $P rows, dev $D rows"
  printf '%-22s %s\n' "$t" "$D"
done

step "Done — restart bin/dev"
