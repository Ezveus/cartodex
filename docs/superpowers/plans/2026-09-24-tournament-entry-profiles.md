# Show the Play! Pokémon profile wherever a participation is listed

No spec: view-only change, no table, column, source or public surface.

## Gaps measured

The profile is already printed by `Tournaments::ShowView#entry_action` (one button per entry),
`Tournaments::Entries::ShowView` ("Tournament profile" row), `TournamentEntry#picker_label` (both
result pickers) and `Tournaments::Standings::Row`. Two listings omit it:

1. `/tournaments/mine` (`Tournaments::MineView`) — one row per entry, no profile column. Two
   entries at one event under two profiles print as two identical-looking rows except for the deck.
2. `/tournaments` (`Tournaments::IndexView`) — a bare `"You attended"` span glued to the name
   (no CSS for `.tournament-attended`), with neither how many participations nor whose.

## Decisions

- **Mine**: add a `Profile` column between `Tier` and `Deck`, printing
  `entry.tournament_profile&.player_name || "—"` — the same fallback `Entries::ShowView` uses.
  `tournament_profile` is already in the `includes`.
- **Index** (owner's choice, asked): under the tournament link, on its own line
  (`div.tournament-participations`), a badge `Participations: N` followed by the profile names,
  comma-separated. N counts entries, not distinct profiles. A profile-less entry prints
  `No profile` (the wording `ShowView#entry_label` already uses). Names are ordered
  alphabetically by `player_name`, `No profile` last, so the line is stable across requests.
  Rendered only when N > 0; a visitor never gets it.
- **Controller**: `attended_ids` becomes `my_entries_by_tournament`, returning
  `{ tournament_id => [entries] }` from one query plus one preload of `tournament_profile`, and
  still no query at all for a visitor or an empty page. `IndexView` takes `my_entries:` (Hash,
  default `{}`) in place of `attended_ids:`.
- **CSS**: `.tournament-participations` as a block with a small top margin and a muted colour for
  the names; the badge reuses `.badge` plus a neutral modifier.

## Tests (controller, `TournamentsControllerTest`)

- index: badge text `Participations: 1` and `Ash Ketchum` on Regional Championship; nothing on
  Local League Cup (replaces the "You attended" test).
- index: two entries at one event (ash + misty, second deck) → `Participations: 2`, names in order
  `Ash Ketchum, Misty`; a profile-less entry adds `No profile` last.
- index: visitor gets no `.tournament-participations` (replaces `.tournament-attended` assertion);
  visitor still issues no `tournament_entries` query (existing test).
- index flat cost: extend with entries on each catalogued event under a **distinct** profile each,
  so a missing profile preload cannot hide behind the query cache.
- mine: header has `Profile`; the ash entry's row prints `Ash Ketchum`; a profile-less entry
  prints `—`.

System tests: none touch these listings' markup (`public_navigation_test.rb` only visits
`/tournaments`); both sweeps still run.
