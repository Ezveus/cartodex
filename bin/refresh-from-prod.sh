#!/usr/bin/env bash
# Steps 3 and 4 of the post-deploy-cleanup skill, in one run:
#   3. take a post-deploy backup on the host, check it, archive it locally, prune older host backups;
#   4. make that backup the development database and verify it.
# Usage: bin/refresh-from-prod.sh NNN   (NNN = the PR number)
# Every precondition is checked before anything is written to production (the only one that
# reaches it reads the deployed commit), and the host is pruned only
# once the host copy answers `ok` to integrity_check and the local archive is byte-identical to it.
# A run that stops part-way can be rerun as is. The host backup is taken afresh on every run, since
# one an earlier run left may predate a later deploy; a local archive is kept when byte-identical
# to it, and the dev archive is kept once production has been promoted over dev.
set -euo pipefail

HOST=root@cartodex.ezveus.eu
TABLES="cards tournament_standings archetypes decks tournaments"
# Every file db:migrate re-dumps in development: one per database development declares.
SCHEMA_FILES="db/schema.rb db/queue_schema.rb db/cable_schema.rb"

die() { echo "ERROR: $*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }
# Never fails: a malformed file makes sqlite3 exit non-zero, and under set -e that would end the
# run on sqlite's own message instead of the die that says what to do about it.
# The checked files are WAL databases, and macOS's sqlite3 keeps a WAL database's -wal and -shm
# after it closes, so every check left two files beside the archive — under the .part name once
# renamed, where nothing would ever look again. They are removed only once the -wal is empty: on
# closing, sqlite3 checkpoints any frames it found into the file, and a -wal that still holds some
# holds pages the file does not.
integrity() {
  sqlite3 "$1" "PRAGMA integrity_check;" 2>&1 || true
  [ -s "$1-wal" ] || rm -f "$1-wal" "$1-shm"
}
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

NNN=${1:-}
[[ "$NNN" =~ ^[0-9]+$ ]] || die "usage: $0 PR_NUMBER"

# Always the main checkout, even when launched from a worktree: that is where bin/dev runs.
ROOT=$(cd "$(git -C "$(dirname "$0")" rev-parse --path-format=absolute --git-common-dir)/.." && pwd)
cd "$ROOT"
[ -d storage ] || die "$ROOT/storage not found"

TODAY=$(date +%F)
ARCHIVE_DIR="$HOME/Documents/perso/cartodex-backups"
# A file an earlier run left is found by PR number, whatever its date: a rerun after midnight must
# still see it. Only a file that does not exist yet is named after today.
D='[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]'
earlier() {
  [ $# -le 1 ] || die "several files for PR $NNN: $* — keep one, move the others aside"
  echo "${1:-}"
}
shopt -s nullglob
PROD_ARCHIVE=$(earlier "$ARCHIVE_DIR"/prod-$D-post-pr-"$NNN".sqlite3)
DEV_ARCHIVE=$(earlier "$ARCHIVE_DIR"/dev-$D-pre-pr-"$NNN".sqlite3)
DONE_MARKER=$(earlier "$ARCHIVE_DIR"/.refreshed-$D-pr-"$NNN")
PROMOTED_MARKER=$(earlier "$ARCHIVE_DIR"/.promoted-$D-pr-"$NNN")
shopt -u nullglob
PROD_ARCHIVE=${PROD_ARCHIVE:-$ARCHIVE_DIR/prod-$TODAY-post-pr-$NNN.sqlite3}
# Named after the PR too: two deploys on one day mean two refreshes, and the second must not
# collide with the first's archive.
DEV_ARCHIVE=${DEV_ARCHIVE:-$ARCHIVE_DIR/dev-$TODAY-pre-pr-$NNN.sqlite3}
# Written last, once every verification passed. Its absence means an earlier run stopped part-way,
# and the run resumes rather than refusing.
DONE_MARKER=${DONE_MARKER:-$ARCHIVE_DIR/.refreshed-$TODAY-pr-$NNN}
# Written just before production is copied over dev. Only its presence says dev no longer holds
# what DEV_ARCHIVE must keep: an archive alone does not, since a run that stopped between the two
# left dev in use, and it may have been written to since.
PROMOTED_MARKER=${PROMOTED_MARKER:-$ARCHIVE_DIR/.promoted-$TODAY-pr-$NNN}
DEV_DB=storage/development.sqlite3
HOST_BACKUP="post-pr-$NNN.sqlite3"

step "Local preconditions"
mkdir -p "$ARCHIVE_DIR"
[ ! -e "$DONE_MARKER" ] || die "this PR's refresh already completed ($DONE_MARKER) — check the dev database by hand"
# One lsof per file: given several, it exits 1 as soon as any of them is not open, which would
# let a database held open without its -wal slip through.
# Every development database, not only the primary: bin/dev's jobs process holds the queue database
# from boot, while the web process opens the primary only on its first request — a bin/dev nobody
# has browsed yet holds no primary file at all, and db:migrate below migrates all three.
refuse_if_open() {
  local db f holders=""
  for db in "$DEV_DB" storage/development_queue.sqlite3 storage/development_cable.sqlite3; do
    for f in "$db" "$db-wal" "$db-shm"; do
      [ -e "$f" ] || continue
      holders+=$(lsof -t "$f" 2>/dev/null || true)$'\n'
    done
  done
  holders=$(printf '%s' "$holders" | sed '/^$/d' | sort -u | tr '\n' ' ')
  if [ -n "${holders// /}" ]; then
    die "a development database is open by PID ${holders% } (bin/dev, bin/jobs or a console still running) — stop it first"
  fi
}
refuse_if_open
# The schema check after db:migrate compares against HEAD, so HEAD must be what was deployed —
# read off the running image, not assumed from origin/master: deploys are manual, and master can
# be ahead of production. Kamal tags the image with the deployed commit's full SHA. Read-only.
DEPLOYED=$(ssh "$HOST" bash -s <<'REMOTE'
set -euo pipefail
C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1)
[ -n "$C" ] || { echo "ERROR: no running web container" >&2; exit 1; }
docker inspect -f '{{.Config.Image}}' "$C"
REMOTE
)
DEPLOYED=${DEPLOYED##*:}
[[ "$DEPLOYED" =~ ^[0-9a-f]{40}$ ]] \
  || die "production runs image tag '$DEPLOYED', not a commit SHA (deployed from an uncommitted tree?) — its schema is unknown"
if [ "$(git rev-parse HEAD)" != "$DEPLOYED" ]; then
  git fetch -q origin master
  [ "$(git rev-parse origin/master)" = "$DEPLOYED" ] \
    || die "production runs $DEPLOYED, origin/master is $(git rev-parse origin/master) — deploy master first, or wait for the deploy in progress"
  die "production runs $DEPLOYED (origin/master), HEAD is $(git rev-parse HEAD) — check out and pull master first"
fi
# The schema check restores these files from HEAD; uncommitted work in them would be erased.
for f in $SCHEMA_FILES; do
  git diff --quiet HEAD -- "$f" || die "$f has uncommitted changes — commit or set them aside first"
done
bin/rails runner 'nil' >/dev/null || die "bin/rails does not boot — fix the local environment first"
if [ -e "$PROD_ARCHIVE" ]; then
  R=$(integrity "$PROD_ARCHIVE")
  [ "$R" = ok ] || die "$PROD_ARCHIVE exists but integrity_check answered: $R — move it aside and rerun"
fi
echo "ok"

step "3. Host backup $HOST_BACKUP, integrity_check"
# Taken afresh even when an earlier run left one of that name: nothing on the host says whether
# that one predates a later deploy, or hours of traffic, and reusing it promoted exactly such a
# copy into dev. A fresh one costs a .backup; a stale one costs a dev database that lags production.
HOST_SHA=$(ssh "$HOST" bash -s -- "$HOST_BACKUP" <<'REMOTE'
set -euo pipefail
B=/rails/storage/$1
C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1)
[ -n "$C" ] || { echo "ERROR: no running web container" >&2; exit 1; }
# Taken under a temporary name and renamed only once sound, so $B never exists partial.
docker exec "$C" rm -f "$B.part" "$B.part-journal"
docker exec "$C" sqlite3 /rails/storage/production.sqlite3 ".backup $B.part"
R=$(docker exec "$C" sqlite3 "$B.part" "PRAGMA integrity_check;" 2>&1 || true)
[ "$R" = ok ] || { echo "ERROR: integrity_check on the host answered: $R" >&2; exit 1; }
docker exec "$C" mv "$B.part" "$B"
echo "integrity_check: ok" >&2
docker exec "$C" sha256sum "$B" | cut -d' ' -f1
REMOTE
)

step "3. Local archive $PROD_ARCHIVE"
if [ -e "$PROD_ARCHIVE" ] && [ "$(sha "$PROD_ARCHIVE")" = "$HOST_SHA" ]; then
  echo "already present, identical to the host backup"
else
  # Streamed straight out of the container, never staged on the host: a copy left in the host's
  # /tmp by a failed transfer is production data that nothing would ever delete. Fetched under a
  # temporary name: an interrupted transfer leaves a .part, never a truncated archive.
  ssh "$HOST" bash -s -- "$HOST_BACKUP" > "$PROD_ARCHIVE.part" <<'REMOTE' \
    || die "transfer of $HOST_BACKUP interrupted — host left unpruned, rerun"
set -euo pipefail
C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1)
[ -n "$C" ] || { echo "ERROR: no running web container" >&2; exit 1; }
docker exec "$C" cat "/rails/storage/$1"
REMOTE
  R=$(integrity "$PROD_ARCHIVE.part")
  [ "$R" = ok ] || die "integrity_check on the fetched copy answered: $R — host left unpruned, rerun"
  [ "$(sha "$PROD_ARCHIVE.part")" = "$HOST_SHA" ] \
    || die "the fetched copy differs from the host's $HOST_BACKUP — host left unpruned, rerun"
  if [ -e "$PROD_ARCHIVE" ]; then
    # An earlier run's archive of an older backup. Every backup is kept locally, so it is set
    # aside under a name the PR-number lookup above no longer matches, never overwritten.
    SUPERSEDED=${PROD_ARCHIVE%.sqlite3}-superseded-$(date +%H%M%S).sqlite3
    mv "$PROD_ARCHIVE" "$SUPERSEDED"
    echo "earlier archive of an older backup kept as $SUPERSEDED"
  fi
  # Named after today, not after the archive it replaces: the name dates the backup, and this one
  # was taken now — an earlier run's date on it would pass a later snapshot off as that day's.
  NEW_PROD_ARCHIVE=$ARCHIVE_DIR/prod-$TODAY-post-pr-$NNN.sqlite3
  mv "$PROD_ARCHIVE.part" "$NEW_PROD_ARCHIVE"
  PROD_ARCHIVE=$NEW_PROD_ARCHIVE
  echo "$PROD_ARCHIVE, integrity_check: ok"
fi
echo "identical to the host backup (sha256 $HOST_SHA)"

step "3. Host prune (everything in /rails/storage but production* and $HOST_BACKUP)"
ssh "$HOST" bash -s -- "$HOST_BACKUP" <<'REMOTE'
set -euo pipefail
C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1)
docker exec "$C" test -e "/rails/storage/$1" || { echo "ERROR: $1 vanished from the host, not pruning" >&2; exit 1; }
docker exec -e KEEP="$1" "$C" sh -c '
  cd /rails/storage
  # *.part too: a run interrupted mid-backup and never rerun for that PR leaves one, and nothing
  # else would ever remove it. The .part of this run was renamed before the prune was reached.
  for f in *.sqlite3 *.sqlite3.part; do
    [ -e "$f" ] || continue
    case "$f" in production*|"$KEEP") ;; *) echo "deleting $f"; rm -f -- "$f" "$f-wal" "$f-shm" "$f-journal" ;; esac
  done
  echo "left on the host:"; ls -la /rails/storage
'
REMOTE

step "4. Archive the current dev database"
if [ -e "$PROMOTED_MARKER" ]; then
  # An earlier run promoted production over dev and stopped later: $DEV_DB holds production now,
  # and archiving it would overwrite the only copy of what dev was.
  echo "an earlier run already promoted production over $DEV_DB; dev is archived as $DEV_ARCHIVE"
elif [ -e "$DEV_DB" ]; then
  # Archived again even when an earlier run left DEV_ARCHIVE: that run stopped before the
  # promotion, so $DEV_DB is still dev, and whatever was written to it since exists nowhere else.
  # .backup, not cp: a -wal beside the file may hold pages cp would leave behind. Written under a
  # temporary name and checked before it takes the final one: the next step overwrites the only
  # other copy of dev.
  # Named after today for the reason the prod archive is: the name dates what it holds.
  NEW_DEV_ARCHIVE=$ARCHIVE_DIR/dev-$TODAY-pre-pr-$NNN.sqlite3
  rm -f "$NEW_DEV_ARCHIVE.part"
  sqlite3 "$DEV_DB" ".backup '$NEW_DEV_ARCHIVE.part'"
  R=$(integrity "$NEW_DEV_ARCHIVE.part")
  [ "$R" = ok ] || die "integrity_check on the dev archive answered: $R — $DEV_DB left untouched, rerun"
  if [ -e "$DEV_ARCHIVE" ]; then
    echo "replacing $DEV_ARCHIVE: an earlier run archived dev but never promoted over it"
    rm -f "$DEV_ARCHIVE"
  fi
  mv -f "$NEW_DEV_ARCHIVE.part" "$NEW_DEV_ARCHIVE"
  DEV_ARCHIVE=$NEW_DEV_ARCHIVE
  echo "$DEV_ARCHIVE, integrity_check: ok"
else
  echo "no $DEV_DB, nothing to archive"
fi

step "4. Promote the backup to $DEV_DB"
# Again: the remote steps take minutes, and a process that opened dev meanwhile would keep writing
# to its own -wal through the cp, losing those writes and reading pages that no longer exist.
refuse_if_open
# Before the cp, not after: once the cp has begun, $DEV_DB no longer holds what the archive must
# keep, and a run stopped between the two would otherwise archive production over it on a rerun.
touch "$PROMOTED_MARKER"
cp "$PROD_ARCHIVE" "$DEV_DB"
rm -f "$DEV_DB-wal" "$DEV_DB-shm"
bin/rails db:environment:set RAILS_ENV=development

# Every version, not MAX: a pending migration older than the latest leaves MAX where it was.
versions() { sqlite3 "$1" "SELECT version FROM schema_migrations ORDER BY version;"; }
# db:migrate re-dumps every schema file, and a run that stops before the step below would leave
# them rewritten — which the preconditions then refuse on every rerun. Restoring from HEAD is safe
# for the same reason it is below: the preconditions refused any uncommitted change in them.
restore_schema_files() { for f in $SCHEMA_FILES; do git show "HEAD:$f" > "$f"; done; }
BEFORE=$(versions "$DEV_DB")
bin/rails db:migrate || { restore_schema_files; die "db:migrate failed — schema dumps restored from HEAD"; }
APPLIED=$(comm -13 <(printf '%s\n' "$BEFORE") <(versions "$DEV_DB") | tr '\n' ' ')
if [ -n "$APPLIED" ]; then
  restore_schema_files
  die "db:migrate was not a no-op (applied ${APPLIED% }): the backup predates the deploy — schema dumps restored from HEAD"
fi
AFTER=$(sqlite3 "$DEV_DB" "SELECT MAX(version) FROM schema_migrations;")

step "4. Schema dumps rewritten by db:migrate"
# db:migrate re-dumps the schema in prod's physical column order. Restore a file only when its
# sorted lines equal HEAD's, i.e. the rewrite is a pure reordering; anything else is a real change.
# Restoring is safe: the preconditions refused any uncommitted change in these files.
# Each line is prefixed with its create_table before sorting: a column that moved from one table to
# another sorts identically otherwise, and would be restored away as a mere reordering.
by_table() { awk '/^  create_table "/ { split($0, q, "\""); t = q[2] } { print t "\t" $0 } /^  end$/ { t = "" }'; }
KEPT=""
for f in $SCHEMA_FILES; do
  if git diff --quiet -- "$f"; then
    echo "$f: unchanged"
  elif diff <(git show "HEAD:$f" | by_table | sort) <(by_table < "$f" | sort) >/dev/null; then
    git show "HEAD:$f" > "$f"
    echo "$f: reordering only, restored from HEAD"
  else
    # Set aside, then restored below like the two db:migrate stops above: left in place, the rewrite
    # made every later run refuse on the uncommitted-changes precondition, this PR's rerun included.
    mkdir -p tmp
    cp "$f" "tmp/$(basename "$f").post-migrate-pr-$NNN"
    KEPT+=" tmp/$(basename "$f").post-migrate-pr-$NNN"
    echo "$f: differs from HEAD by more than line order"
  fi
done
if [ -n "$KEPT" ]; then
  restore_schema_files
  die "db:migrate's dump differs from HEAD by more than line order — dev is promoted but unverified. The rewrite is kept as$KEPT (diff it against HEAD) and the dumps are restored from HEAD. A rerun stops here again until that difference is understood"
fi

step "4. Verification"
# Captured on its own: piped into grep, a failing status task read as zero migrations down.
MIGRATE_STATUS=$(bin/rails db:migrate:status) || die "bin/rails db:migrate:status failed — migrations unverified"
DOWN=$(grep -cE '^[[:space:]]*down' <<<"$MIGRATE_STATUS" || true)
[ "$DOWN" = 0 ] || die "db:migrate:status shows $DOWN migration(s) down"
echo "migrations down: 0"

COUNTS="SELECT MAX(version) FROM schema_migrations;"
for t in $TABLES; do COUNTS+=" SELECT COUNT(*) FROM $t;"; done
# Production itself, not the archive dev was just copied from: comparing those two is a tautology.
# ssh joins its arguments into one string the remote shell re-parses, so the query's ( * ; must
# be escaped once more; %q's backslashes parse the same under sh, dash, bash and zsh. The other
# ssh calls pass only post-pr-NNN.sqlite3, digits checked above, which needs no quoting.
PROD_COUNTS=$(ssh "$HOST" bash -s -- "$(printf %q "$COUNTS")" <<'REMOTE'
set -euo pipefail
C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1)
docker exec "$C" sqlite3 /rails/storage/production.sqlite3 "$1"
REMOTE
)
DEV_COUNTS=$(sqlite3 "$DEV_DB" "$COUNTS")
PROD_VERSION=$(sed -n 1p <<<"$PROD_COUNTS")
[ "$PROD_VERSION" = "$AFTER" ] || die "MAX(version): production $PROD_VERSION, dev $AFTER"
echo "MAX(version): $AFTER on both ends"
# Rows written in production since the backup are legitimate, so a count that differs is reported
# rather than fatal; read the table, a gap larger than a few minutes of traffic is not one.
printf '%-22s %10s %10s\n' table dev production
i=2
for t in $TABLES; do
  D=$(sed -n "${i}p" <<<"$DEV_COUNTS"); P=$(sed -n "${i}p" <<<"$PROD_COUNTS")
  printf '%-22s %10s %10s%s\n' "$t" "$D" "$P" "$([ "$D" = "$P" ] || echo '   <- differs')"
  i=$((i + 1))
done

touch "$DONE_MARKER"
step "Done — restart bin/dev"
