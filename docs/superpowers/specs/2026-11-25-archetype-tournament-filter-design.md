# Archetype analysis: a tournament filter

`/archetypes/:slug/analysis` lets the reader choose the sample by Standard pool (**Sample**) and by
venue (**Venue**). This adds a third axis: one tournament.

## Decisions (owner, 2026-11-25)

- **Cascading.** The **Tournament** select lists the tournaments of the current pool + venue
  selection, and choosing one narrows the report *within* that selection. Pool and venue are not
  driven by the tournament.
- **One tournament at a time.** A third `<select>` in the same form, `Ui::FilterSelect`, submitted
  on change by `card-filter` like the other two. No multi-select.

## Measurements (development database, a production copy, 2026-11-25)

- 63 archetypes carry standings; up to **66 tournaments** for one archetype (Ethan's Typhlosion),
  46 archetypes have at least 10.
- Per `(archetype, pool, venue)` cell: at most **20** tournaments, 6.4 on average. Under "All
  formats" + All venues the select can reach 66 options.
- 1022 `(archetype, tournament)` pairs: 16 with no list, **845 with exactly one**, 112 with 2-9, 49
  with 10 or more (max 137). The useful case is a large paper event — Regional Baltimore holds 575
  standings over 43 archetypes, Frankfurt 524, Worlds 2026 278.
- 354 tournaments are online (avg. 2.5 standings), 35 paper.
- 55 tournaments share their name with another one, so a label needs the date.
- **0 decks carry more than one standing**, and 0 decks carry standings at two tournaments under
  one archetype.
- `EXPLAIN QUERY PLAN` of the bucket query grouped by `tournaments.id`: `SEARCH s USING INDEX
  index_tournament_standings_on_archetype_id`, `SEARCH tournaments USING INTEGER PRIMARY KEY` —
  the same access path as today, plus a temp B-tree for the GROUP BY it already needed.

## Design

### `Archetypes::MetagameScope`

- `call(archetype:, pool_param:, venue_param:, tournament_param:)`; `tournament_param` gets the
  same `to_s` as the other two, so an Array or a Hash falls back rather than raising.
- **The bucket query stays one query** and gains `tournaments.id` as its grouping key (pool and
  venue are functionally dependent on it) plus `tournaments.name`. A bucket becomes one tournament;
  every existing pool and venue figure is a fold of buckets, as it already was across venues. The
  controller's 17-query budget is therefore unchanged.
- **The fold now sums tournaments inside a cell**, so a deck holding standings at two tournaments
  of one pool would be counted twice by the selector while `CardStats` counts it once. That is the
  property the venue axis already extended to the default view (one deck under both venues), on a
  third axis; measured 0 such decks. A test names the behaviour, as the venue one does. The
  alternative — a second grouped query for the tournament options, keeping cells exact — costs one
  query on a page pinned at a literal 17 by three assertions, to defend a shape that has zero rows.
- Resolution order is **pool → venue → tournament**. The tournament resolves against
  `selection_rows(pool, venue)`: an id not in that selection — a stale link, a venue change that
  left the tournament behind, junk — **clamps to "All tournaments"**, recorded in the `Result`
  (`tournament` is nil) exactly like the venue clamp, so the select and the report cannot disagree.
- `tournament_selectable?`: the selection holds **at least two** tournaments. One tournament is the
  same sample as "All tournaments" — two labels over one sample, the shape `selectable?` and
  `venue_selectable?` already refuse. When it is false the tournament also clamps to nil, so a URL
  naming the selection's only tournament cannot pin a filter the page offers no control to remove.
- `tournament_options`: "All tournaments — N lists" first (the default, as Venue's "All" is), then
  one option per tournament, **most recent first**, id breaking a tie, labelled
  `"<name> (<I18n.l date>) — N lists"` — the `TournamentEntry#picker_label` spelling, date included
  because 55 tournaments share a name. Counted within the selection: these labels move with pool
  and venue, as Venue's labels move with the pool.
- Under a selected tournament, every figure the `Result` carries about *the sample* narrows to it:
  `lists_count`, `online_lists_count`, `standings`, `listed_standings`, `unpooled_in_sample`, and
  `all_formats_lists_count` (because a pool change carries the tournament along and keeps it — "All
  formats" contains every tournament — so the empty state's "try All formats" must be true of it).
  `options`, `venue_options`, `unpooled?`, `selectable?`, `venue_selectable?` and
  `fuller_sample_available?` do not, for the reasons already written for the venue axis.

### `Archetypes::SampleSelector`

- The form renders when any of the three axes is a choice; each select keeps its own guard.
- A **tournament note** replaces the venue note when a tournament is selected: the Sample and Venue
  labels then count every tournament of the selection while the report covers one. It names only
  the selects actually rendered.
- One CSS rule, found in the browser rather than planned: `.deck-filters` already wraps its
  `.archetype-sample-label` items, but a select is as wide as its longest option and online event
  names made the Tournament label 905px at 500px, scrolling the page sideways; the select is now
  capped at its row (`.archetype-sample-label .deck-filter-select`). Checked on
  bounding boxes at both sweep widths, since a 66-option select carries long labels.

### `Archetypes::CardReport`

- The mode links re-emit `tournament:` off the scope (nil when none), like `venue:`.
- Empty state under a selected tournament: the pool and venue suggestions are both clicks that keep
  the tournament. The pool one withholds itself through the scoped `all_formats_lists_count`; the
  venue one through an explicit guard, since `venue_options` is deliberately not scoped to the
  event. A third suggestion — "All
  tournaments" — is made when the selection holds lists.

### Controller

- `tournament_param: params[:tournament]`. No change to the rate limits, the policy or the legacy
  redirect (`?tournament=` never addressed the front page).

## Out of scope

- A link from the selected tournament to its event page.
- Multiple tournaments, tier filtering, date ranges.
- The tournament axis anywhere but this page.
