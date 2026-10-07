#!/usr/bin/env bash
# Steps 3 and 4 of the post-deploy-cleanup skill, in one run:
#   3. take a post-deploy backup on the host, check it, archive it locally, prune older host backups;
#   4. make that backup the development database and verify it.
# Usage: bin/refresh-from-prod.sh NNN   (NNN = the PR number)
# Every local precondition is checked before production is touched, and the host is pruned only
# once the host copy answers `ok` to integrity_check and the local archive is byte-identical to it.
# A run that stops part-way can be rerun as is: each step reuses what an earlier run left behind.
set -euo pipefail

HOST=root@cartodex.ezveus.eu
TABLES="cards tournament_standings archetypes decks tournaments"
SCHEMA_FILES="db/schema.rb db/cable_schema.rb"

die() { echo "ERROR: $*" >&2; exit 1; }
step() { printf '\n== %s\n' "$*"; }
# Never fails: a malformed file makes sqlite3 exit non-zero, and under set -e that would end the
# run on sqlite's own message instead of the die that says what to do about it.
integrity() { sqlite3 "$1" "PRAGMA integrity_check;" 2>&1 || true; }
sha() { shasum -a 256 "$1" | cut -d' ' -f1; }

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
# Written last, once every verification passed. Its absence beside DEV_ARCHIVE means an earlier
# run stopped after archiving dev, and the run resumes rather than refusing.
DONE_MARKER="$ARCHIVE_DIR/.refreshed-$TODAY-pr-$NNN"
DEV_DB=storage/development.sqlite3
HOST_BACKUP="post-pr-$NNN.sqlite3"

step "Local preconditions"
mkdir -p "$ARCHIVE_DIR"
[ ! -e "$DONE_MARKER" ] || die "this PR's refresh already completed ($DONE_MARKER) — check the dev database by hand"
# One lsof per file: given several, it exits 1 as soon as any of them is not open, which would
# let a database held open without its -wal slip through.
HOLDERS=""
for f in "$DEV_DB" "$DEV_DB-wal" "$DEV_DB-shm"; do
  [ -e "$f" ] || continue
  HOLDERS+=$(lsof -t "$f" 2>/dev/null || true)$'\n'
done
HOLDERS=$(printf '%s' "$HOLDERS" | sort -u | tr '\n' ' ')
if [ -n "${HOLDERS// /}" ]; then
  die "$DEV_DB is open by PID ${HOLDERS% } (bin/dev or a console still running) — stop it first"
fi
# The schema check after db:migrate compares against HEAD, so HEAD must be what was deployed.
git fetch -q origin master
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/master)" ] \
  || die "HEAD is not origin/master — check out and pull master first (the deploy ships origin/master)"
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
# An existing backup of that name was taken for this PR, after its deploy, by an earlier run that
# stopped later: it is reused once sound, so a rerun never needs a hand-made rm on the host.
HOST_SHA=$(ssh "$HOST" bash -s -- "$HOST_BACKUP" <<'REMOTE'
set -euo pipefail
B=/rails/storage/$1
C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1)
[ -n "$C" ] || { echo "ERROR: no running web container" >&2; exit 1; }
# Taken under a temporary name and renamed only once sound, so $B never exists partial: an
# interrupted .backup would otherwise be reused, fail integrity_check, and stop every rerun.
if docker exec "$C" test -e "$B"; then
  echo "reusing $B, taken by an earlier run" >&2
  T=$B
else
  docker exec "$C" rm -f "$B.part" "$B.part-journal"
  docker exec "$C" sqlite3 /rails/storage/production.sqlite3 ".backup $B.part"
  T=$B.part
fi
R=$(docker exec "$C" sqlite3 "$T" "PRAGMA integrity_check;" 2>&1 || true)
[ "$R" = ok ] || { echo "ERROR: integrity_check on the host answered: $R" >&2; exit 1; }
[ "$T" = "$B" ] || docker exec "$C" mv "$T" "$B"
echo "integrity_check: ok" >&2
docker exec "$C" sha256sum "$B" | cut -d' ' -f1
REMOTE
)

step "3. Local archive $PROD_ARCHIVE"
if [ -e "$PROD_ARCHIVE" ]; then
  echo "already present, integrity_check: ok"
else
  # Fetched under a temporary name: an interrupted scp leaves a .part, never a truncated archive.
  ssh "$HOST" bash -s -- "$HOST_BACKUP" <<'REMOTE'
set -euo pipefail
C=$(docker ps -q --filter label=service=cartodex --filter label=role=web --filter status=running | head -1)
docker cp "$C:/rails/storage/$1" "/tmp/$1"
REMOTE
  scp -q "$HOST:/tmp/$HOST_BACKUP" "$PROD_ARCHIVE.part"
  ssh "$HOST" rm -f "/tmp/$HOST_BACKUP"
  R=$(integrity "$PROD_ARCHIVE.part")
  [ "$R" = ok ] || die "integrity_check on the fetched copy answered: $R — host left unpruned, rerun"
  mv "$PROD_ARCHIVE.part" "$PROD_ARCHIVE"
  echo "integrity_check: ok"
fi
# A reused archive must be the host backup, byte for byte: same name is not same content.
[ "$(sha "$PROD_ARCHIVE")" = "$HOST_SHA" ] \
  || die "$PROD_ARCHIVE differs from the host's $HOST_BACKUP — move it aside and rerun; host left unpruned"
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
if [ -e "$DEV_ARCHIVE" ]; then
  # An earlier run archived dev and stopped later; what is in $DEV_DB now is its promoted copy.
  echo "already archived by an earlier run: $DEV_ARCHIVE"
elif [ -e "$DEV_DB" ]; then
  # .backup, not cp: a -wal beside the file may hold pages cp would leave behind. Written under a
  # temporary name and checked before it takes the final one: a rerun reads the archive's presence
  # as done, and the next step overwrites the only other copy of dev.
  rm -f "$DEV_ARCHIVE.part"
  sqlite3 "$DEV_DB" ".backup '$DEV_ARCHIVE.part'"
  R=$(integrity "$DEV_ARCHIVE.part")
  [ "$R" = ok ] || die "integrity_check on the dev archive answered: $R — $DEV_DB left untouched, rerun"
  mv "$DEV_ARCHIVE.part" "$DEV_ARCHIVE"
  echo "$DEV_ARCHIVE, integrity_check: ok"
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
# Restoring is safe: the preconditions refused any uncommitted change in these files.
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
