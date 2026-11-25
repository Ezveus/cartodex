# Archetype tournament filter — plan

Spec: `docs/superpowers/specs/2026-11-25-archetype-tournament-filter-design.md`.

One lane, implemented in this session: the service, the two components and the controller are one
contract (`MetagameScope::Result`) read by everything else, and the whole change is a few hundred
lines — dispatching lanes would cost more than it returns.

## 1. `Archetypes::MetagameScope` (TDD, `test/services/archetypes/metagame_scope_test.rb`)

- `Bucket` gains `tournament_id`, `tournament_name`; `buckets` groups by `tournaments.id` and plucks
  `tournaments.id, tournaments.name, tournaments.standard_pool_id, tournaments.online, COUNT(*),
  COUNT(DISTINCT deck_id), MAX(tournaments.date)`.
- `Result` gains `tournament` (`SelectedTournament`, a Struct carrying the id alone — its name and
  date were dropped once the mutation pass showed nothing read them; nil = all),
  `tournament_options`, `tournament_selectable`.
- `selected_tournament(pool, venue)`; `selection_rows(pool, venue, tournament = nil)`.
- `standings_scope(pool, venue, tournament)` adds `where(tournament_id:)`.

Tests:

1. options list tournaments of the selection, most recent first, labelled with date and count,
   "All tournaments" first with the selection total.
2. selecting a tournament narrows `lists_count`, `standings`, `listed_standings`, `online_lists_count`.
3. a tournament outside the pool+venue selection clamps to nil (Result and relation).
4. junk / Array / Hash / unknown id clamps to nil without raising.
5. one-tournament selection: not selectable, and a param naming it clamps to nil.
6. tournament labels move with the venue (cascade): under Online only online tournaments are listed.
7. pool options and venue options do not move when a tournament is selected.
8. two tournaments sharing a name are told apart by date; same date ties broken by id.
9. `all_formats_lists_count` and `unpooled_in_sample?` narrow to the tournament.
10. fold over-count across two tournaments of one pool is named (a deck at two tournaments).

## 2. `Archetypes::SampleSelector` (component test)

- tournament select rendered iff `tournament_selectable?`, `selected:` is the tournament id or ALL.
- the form renders when only the tournament axis is a choice.
- the tournament note replaces the venue note, names only rendered selects, carries the count.

## 3. `Archetypes::CardReport` (component test)

- mode links carry `tournament=` when one is selected, and none otherwise.
- empty state under a tournament suggests "All tournaments" only when the selection has lists.

## 4. Controller (`test/controllers/archetypes_controller_test.rb`)

- `?tournament=<id>` narrows the report; junk does not 500; the 17-query budget holds with a
  tournament selected.

## 5. System (`test/system/archetype_metagame_test.rb`)

- choosing a tournament in the select reloads the report on that tournament; geometry of three
  labels at both sweep widths.

## 6. Docs

- `docs/architecture/archetype-metagame.md`: the tournament axis paragraph.
- `CLAUDE.md`: the `MetagameScope.call` signature where it is quoted.
