# Archetype index and per-archetype metagame stats

A member-facing catalogue of archetypes (`/archetypes`) and, for each one, a page that turns the
tournament field lists Cartodex already holds into a deck report (`/archetypes/:id`): which cards
the archetype's recorded lists play, how often, and in how many copies.

This is the aggregation that `CLAUDE.md` names as the obvious next issue after #148 and #150 —
"no per-event metagame breakdown, no cross-event metagame page. The archetype FK and the
`division` column are chosen so that a breakdown is a `group` over one table when it ships." It
ships here, and it needs **no migration**: every column it reads already exists.

## Audience

The page is written for a player who will **face** the archetype, not for one who pilots it. That
framing is borrowed from the deck-report work this design started from, and it decides what earns
a place: inclusion rates and copy counts are what let an opponent know what is coming and, once
they have seen the second copy of a two-of, know it is gone. A pilot's concerns — the draw engine's
internal logic, which variant a list is — are not what the page leads with.

It does **not** try to reproduce that report's hand-curated functional categories. See below.

## What the page refuses to say, and why

Each of these was measured against the production data, not assumed. All three are absences a
later reader will be tempted to fill; the measurement is recorded so they can weigh it.

**No metagame share.** A standings sheet imported from one archetype's Limitless page contains
only that archetype's rows. Cartodex never sees the rest of the field, so "12 % of the meta" is
not a number this database can produce. Every figure is worded as *recorded in Cartodex*. The
index page's ordering is "most recorded", which is a statement about who has run an import, not
about what people play. `CLAUDE.md` already says an imported sheet is partial and that nothing
marks it as such; this page must not quietly imply otherwise.

**No win rate from standings.** `Tournaments::StandingsImporter` writes `player_name`, `division`,
`placement`, `archetype` and `created_by` — never `wins`/`losses`/`ties`. Measured on the
production database: **1 of 94 standings carries a W/L/T**, the one that was typed by hand. A win
rate computed from that column would describe the single hand-typed row and nothing else.

**No ACE SPEC category.** Not derivable. Every ACE SPEC carries `rarity = "Ultra"`, but so do 93
ordinary Trainers in the catalogue (Boss's Orders, Carmine, Buddy-Buddy Poffin…), and the string
"ACE SPEC" appears in `effect` on **0 of 4720 cards**. There is no column that isolates them.

**No functional categories** — Gust, Switch, Recovery, Disrupt. These describe what a card *does*,
which the scraper does not record. The reference deck reports get them from a hand-maintained
per-archetype table; an app cannot maintain one per archetype and must not guess from a name. The
page groups by the structure the database does know (below) and leaves the roles to the reader.

## The sample

### Scoping is not optional

`Archetypes::MetagameScope` is the single place that answers "which standings count". It takes an
archetype and an optional Standard pool, and yields the standings of that archetype that carry a
deck, plus the pool options to offer.

Scoping matters more than it looks. Measured on the production data for
*Raging Bolt ex / Teal Mask Ogerpon ex*, 93 recorded lists spanning three rotations:

| sample | lists | distinct cards | played by every list | fixed core |
|---|---|---|---|---|
| all rotations | 93 | **72** | 11 | 1 card / 1 copy |
| SVI-DRI | 68 | 46 | 19 | 6 cards / 11 copies |
| TEF-CRI | 22 | 48 | 14 | 3 / 9 |
| TEF-PBL | 3 | 28 | 25 | 21 / 50 |

Blended, the archetype presents a 72-card pool that no 60-card deck resembles, and the inclusion
percentages describe no list anyone played. This is why the pool selector exists, and why it
exists in v1 rather than being deferred: the very first real import already spans three rotations.

`tournaments.standard_pool_id` is the axis because it is the one already modelled and the one
players name (`TEF-PBL`). `Tournaments::StandingsImportPlan` writes
`standard_pool: StandardPool.at(date)` whenever the derived format is `standard`, and **refuses**
a Standard event it cannot anchor — so imported Standard events always carry a pool.

### The selector and its default

Options are the Standard pools actually present among this archetype's standings, plus
"All formats". Non-Standard events (`format` other than `standard`) carry no pool and therefore
appear only under "All formats" — stated on the page rather than left to be discovered.

**Each option is labelled with its list count** (`TEF-PBL (3 lists)`, `TEF-CRI (22)`, …). Without
that, the choice between rotations is blind.

**The default is the most recent pool present, not the best-populated one.** For Raging Bolt that
is TEF-PBL with 3 lists — the least informative view. That is deliberate: defaulting to the
best-populated pool would silently answer "what does this deck play?" with 2025 data under a
heading that says nothing about the year. Telling the truth about the current rotation, and
putting the fuller samples one labelled click away, is the honest trade.

An unknown or malformed `?pool=` falls back to the default rather than 404ing.

### Small samples say so

A sample below `SMALL_SAMPLE` (10 lists) renders a notice: percentages over 3 lists are 33/67/100
and mean nothing. This is not decoration — the default view of the measured archetype is exactly
such a sample.

## The card report

### Aggregation key: `cards.fingerprint`, not the card name

`Card#fingerprint` is the repo's "same card, whichever printing" key: for a Trainer or an Energy
it hashes the name; for a Pokémon it hashes name, HP, type, attacks and abilities. Grouping on it
is both more correct and more useful than grouping on the name, and the production data
demonstrates both halves at once. Across the 93 measured lists: **81 distinct `card_id`,
72 distinct fingerprints, 70 distinct names.**

- 81 → 72 is the fingerprint doing its job: nine reprints folded into the card they are.
- 72 → 70 is the fingerprint *refusing* to fold: **Hoothoot** appears as three genuinely different
  cards (TEF 126 at 70 HP, PRE 77 at 80 HP, SCR 114 at 70 HP with different attacks). A player
  chooses between them. Aggregating by name would have printed "Hoothoot 100 %, 1-2 copies" and
  hidden the choice — the same conflation `Decks::ArchetypeDetector` was fixed for when it moved
  off names and onto fingerprints.

### Quantities are summed per list before they are counted

One list may hold two rows for one fingerprint — two printings of the same card. `(deck_id,
card_id)` is UNIQUE, so those are two legal `DeckCard` rows. They are one card in the list, so the
quantities are summed per `(deck, fingerprint)` **before** the histogram sees them. Measured
occurrences in the production data: **zero** — Limitless normalises its lists. The step stays,
because a hand-typed list is under no such discipline and the failure would be silent (a card
counted twice at half its copies).

### Statistics

`Archetypes::CardStats` runs one grouped query returning `(deck_id, fingerprint, name, SUM(quantity))`
and derives everything in Ruby from that single pass:

- inclusion count and percentage of lists,
- range of copies **when played** (the zero case is excluded — that is what "when played" means),
- the mode when played, reported as a tie when it is one, never silently resolved,
- a `core` marker for 100 % inclusion,
- the **fixed core**: cards at 100 % inclusion with a single quantity across every list, and the
  copies they account for — "N of 60 are settled, 60 − N are the list's own".

Measured cost: 2675 intermediate rows for 93 lists in **23 ms**. See *Performance* below.

### Categories

Derived from `card_type` and the scraped `subtype`, in this display order: Pokémon, Supporter,
Item, Tool, Stadium, Special Energy, Basic Energy, **Other**.

`subtype` is a free scraped string, not an enum. Two spellings of the tool bucket exist —
`Cards::Fetcher#parse_subtype` can emit `"Pokémon Tool"`, while all 76 tools in the catalogue
carry `"Tool"` — and both map to Tool, as `Decks::ShowView::TRAINER_SUBTYPE_LABELS` already does.

**Other** is unreachable on today's data (all 4720 cards categorise) and exists anyway, **rendered
visibly** rather than dropped. A new Trainer subtype must surface as a labelled bucket, not vanish
from a report that still sums to a plausible-looking 60.

### Presentation: variants of one name stay together

Grouping by fingerprint means Hoothoot is three rows. Sorted by inclusion, they scatter. The
report therefore groups rows by card **name**, orders the groups by the share of lists playing
*any* version of that name, and renders one sub-row per printing when a group holds more than one.
The name-level share is a distinct count of lists, not the sum of the per-printing shares — a list
may play two versions.

## The performance panel

Counts, never rates: standings and events recorded, lists held, the period covered, the best
placement, and breakdowns by placement band, by tier and by division. Divisions are ordered
junior / senior / masters via `TournamentStanding.division_order`, the same business order the
standings sheet uses — not alphabetically.

The bands are fixed (1st, 2-4, 5-8, 9-16, 17-32, 33-64, 65+) and deliberately **not**
`Tournament::TOP_CUT_BANDS`. That constant maps an *attendance* to a top-cut size — it is what
`TournamentEntry#top_cut_size` reads — so answering "did this placement make the cut" needs the
event's field size, and `Tournaments::StandingsImporter` never writes one: all three
`*_participant_count` columns are nil on every imported event, measured. A cut-aware band would
therefore be nil for every row the import produces.

Note that the panel counts **all** standings in scope, including those with no list attached,
while the card report counts only the listed ones. A recorded placement is a result whether or not
anybody typed the decklist, so `Archetypes::MetagameScope` exposes both relations rather than
letting one number stand for the other.

## `/archetypes` — the index

The shape `tournaments#index` established: a debounced search field **outside** a Turbo Frame,
table and pager **inside**, row links carrying `data-turbo-frame="_top"`, `requested_page` clamped
to the last page, `.to_a` on the page of rows.

Columns: Archetype (the coloured badge), Cards (both `printing_label`s), Standings, Events, Lists,
Last event. Ordered by recorded standings descending, then name — archetypes with none stay listed,
at the bottom, because they are what members tag their own decks with.

The three counts come from one grouped query (`Archetypes::IndexCounts`), not a `counter_cache`
and not a per-row count. A flat-cost test holds that down.

## Controller, policy, routes

`ArchetypesController#index`/`#show`, declared **inside** the `authenticate :user` block.
`ArchetypePolicy#index?`/`#show?` answer `user.present?`. `after_action :verify_authorized` on
every action, and `authorize` in each.

**Opening the pages to visitors later is three edits**, and the controller carries a comment
saying so: move the resource out of the `authenticate :user` block; `include PubliclyReachable` and
`publicly_reachable :index, :show`; flip the policy to `true`. A fourth step belongs to that day
and not to this one — a per-IP `rate_limit … unless: -> { user_signed_in? }` sized like
`tournaments#index`'s 60/min. It is not added now: no anonymous request can reach the route, and a
limiter that no test can exercise is a limiter nobody knows works.

`/archetypes/:id` keys on the id, not a slug: archetype names contain `/`
(`Froslass / Munkidori`), and unlike a deck there is nothing here to keep from being enumerated.

## Entry points

1. **`Ui::AppNavbar`** — `nav_link "Archetypes", archetypes_path, "archetypes"`. The member navbar
   only; the visitor navbar gets none while the pages need a session.
2. **`Ui::ArchetypeBadge`** gains an optional `href:`. Passed from `Decks::ClassificationBadges`
   (an owner-only surface) and from `Tournaments::Standings::Row` **only when `viewer:` is
   present** — that row already receives the viewer, so no component learns to call a policy.
   `Decks::PublicBadges` is deliberately left alone: it renders on a page a visitor can reach, and
   a link to a sign-in wall is worse than no link.
3. **`Search::Global`** gains a fifth group. `Archetype.none` for a visitor, exactly as
   `deck_scope` already does, so a visitor's spotlight never offers a link they cannot follow.
   Option ids are prefixed `spotlight-option-archetype-` — `Search::ResultsList` derives ids from
   the record id, and two groups sharing a prefix would emit duplicate ids and break keyboard
   navigation, the bug `shared_decks` already carries a fix for.

## Performance

One grouped query for the report, one for the pool options, one for the performance panel, one for
the index counts — all flat in the size of the collection. Measured: 93 lists → 2675 rows → 23 ms.

**No caching in v1**, and the threshold was set before the measurement rather than after it: the
honest version-key for a cache entry is a `MAX(updated_at)` over the archetype's standings, which
is the kind of unindexed aggregate `Card.filter_values` had to be corrected away from, and the
repo's own rule is to make the endpoint cheap before wrapping it. The stated test was "if a
synthetic 1500-list archetype renders above ~200 ms, add caching".

Measured, on a synthetic 1500-list archetype (39 000 `deck_cards` rows) built and rolled back in
one transaction:

| service | queries | time |
|---|---|---|
| `MetagameScope` | 4 | 15.6 ms |
| `CardStats` | 3 | 137.3 ms |
| `Performance` | 4 | 6.1 ms |
| `IndexCounts` | 1 | 2.0 ms |

≈161 ms for twelve queries, and the query count does not move with the sample. Under the
threshold, so no cache — and the next person to wonder has the number rather than the argument.
`CardStats` is 85 % of it and is where a cache would go if the collection grows past roughly twice
this size.

## Testing

**No new fixtures.** Fixtures are global: the sample this feature needs is large, and adding
standings to `tournaments(:one)` or a third tournament would move the counts that the standings
sheet's pagination tests and the tournament catalogue's tests assert on. The metagame sample is
built per test, the way `catalog_event` and `grow_collection` already are.

Coverage: controller tests (content, filter, frame, pager, `?page[]=1`, `?page=99`, flat cost),
`ArchetypePolicy` including the `nil` user, lines in `public_access_test.rb` and
`navbar_active_section_test.rb`, unit tests per service — including the two cases the production
data proved matter (a name split across fingerprints must stay split; two printings of one
fingerprint in one list must be summed, not counted twice) and the two it proved are silent (an
uncategorised card must surface, a small sample must be labelled) — and a system test on both
viewports: navbar → index → filter → archetype → switch pool.

Every test that locks a mechanism is verified by sabotage: break the mechanism, watch the test go
red, restore, watch it go green.

## Out of scope

Cross-archetype comparison; a metagame page spanning archetypes (it would need a complete field,
which no import produces); per-division card statistics (junior and senior hold 3 and 2 of the 94
measured standings); matchup data; exporting the report; opening the pages to visitors (specified
above as three edits, not performed); and anything that writes — this feature reads.
