# Card page: usage by archetype, Standard pool and tournament

`/cards/:id` shows, for the card it describes, the share of each archetype's recorded lists that
play it, broken down by Standard pool and by tournament, with the figures
`/archetypes/:slug/analysis` prints for that card under the same sample.

## Decisions (owner, 2026-11-25)

- **A tree, archetype → pool → tournament**, rather than filters over a flat list.
- **The Venue axis is kept**, as a select above the tree (All / Paper / Online), so that every node
  reproduces one state of the analysis page.
- **The card is its fingerprint**, every printing of it, as the analysis report's card row counts it.

## Measurements (development database, a production copy, 2026-11-25)

- 4739 standings, 4720 carrying a list, 84 archetypes with a list, 389 tournaments.
- 749 card keys are played. Per key: archetypes max 82 / median 2; (archetype, pool) pairs max
  195 / median 4; (archetype, tournament) pairs max 1104 / median 11.
- Boss's Orders, the widest: 82 archetypes, 197 (archetype, pool) nodes (194 where it is played),
  1133 (archetype, tournament) pairs, **1104 where it is played**. Iono: 93 pool nodes (39 played),
  500 tournament pairs of which **52** are played.
- The one query below, on Boss's Orders: **4606 rows in 46.6 ms**; Ultra Ball 4652 rows / 25.3 ms;
  Iono 2700 / 11.4 ms. `EXPLAIN QUERY PLAN`: `index_cards_on_fingerprint` (covering),
  `index_deck_cards_on_card_id`, `index_tournament_standings_on_deck_id`,
  `index_tournament_standings_on_archetype_id`.

## Design

### `Cards::ArchetypeUsage` (service)

`Cards::ArchetypeUsage.call(card:, venue_param: nil)` → `Result`.

**The same figure, computed the same way.** The analysis page's card row is
`Archetypes::CardStats::Entry`: over the sample's *listed* standings, `lists_count` is the distinct
deck ids, `inclusion_count` the distinct decks holding a `deck_cards` row whose
`GROUPING_KEY` (`COALESCE(cards.fingerprint, 'card:' || cards.id)`) is this card's, the percentage
`(100.0 * inclusion / lists).round(1)`, and copies the per-deck `SUM(quantity)` of that key — min,
max and modes via `CardStats.modes_of`. This service reproduces each of those, by set arithmetic
over deck ids rather than by `MetagameScope`'s fold, so a node is **exact** even where the selector
labels of the analysis page over-count (a deck at two events; measured 0 such decks).

**One query** fetches, for every listed standing of every archetype that has at least one list
playing the card: `archetype_id`, `tournaments.standard_pool_id`, `tournaments.online`,
`tournament_id`, `tournaments.name`, `tournaments.date`, `deck_id`, and the deck's summed copies of
the card (a `LEFT JOIN` on a per-deck `SUM`, NULL when the deck does not play it). One more loads the
archetypes (for name and slug), and three the pools (`StandardPool.named` preloads the two card-set
bounds `StandardPool#name` reads). **Five once a list plays the card in a Standard pool** (two when it is played only outside Standard, one when no list plays it) — asserted outside the query
cache on a one-pool card and on one spanning three archetypes, both pools and a non-Standard event.

A card with no fingerprint matches by its own id only — the `'card:<id>'` half of `GROUPING_KEY`.

**Venue.** `VENUES = %w[all paper online]`, parsed with `to_s` like `MetagameScope`. A venue in
which no list plays the card clamps to `:all`, recorded in the `Result`. `venue_selectable?` is
true when lists playing the card exist under **both** venues (the analysis's rule: three labels over
one sample is not a choice). Options carry the number of lists playing the card under each venue.

**The tree**, under the resolved venue:

- **Archetypes**: those with at least one list playing the card in the venue, ordered by lists
  playing it (descending), then name. The node's sample is the archetype's lists in the venue,
  every pool — the analysis at `pool=all`.
- **Pools**: every pool in which the archetype has a list in the venue — **0 % included**, because
  "dropped after rotation" is an answer — most recent **listed** event in the venue first, the pool
  id breaking a tie. That is close to, and deliberately not, the analysis selector's order, which
  reads `MAX(date)` over every standing in every venue: the one query here holds listed standings
  only, and matching it exactly would cost a second grouped query to order a handful of nodes. Events with no Standard pool form one last node, **"Other formats"** (Expanded, GLC and the four Japanese Standard events filed as `other`),
  whose figure has no analysis counterpart (the analysis offers no "non-Standard only" sample) and
  which therefore links nowhere.
- **Tournaments**: those of that pool where the card is played, newest first, the id breaking a
  tie, labelled `"<name> (<I18n.l date>)"`. The rest are a count on the pool node
  (`unplayed_tournaments_count`) — 448 of Iono's 500 leaves would otherwise read 0 %.

**Links.** Every node but "Other formats" carries the analysis parameters it reproduces:
archetype `{pool: "all"}`, pool `{pool: id}`, tournament `{pool: id or "all", tournament: id}`,
each plus `venue:` when the venue is not `:all`. Reproduction holds through the analysis's clamps:
a node exists only where the archetype has lists in the venue, so the venue clamp cannot fire, and
the tournament clamp (a selection of one event) only fires where the event *is* the selection.

### `Cards::UsageSection` (component)

Rendered by `Cards::ShowView` under the card's details, for visitors and members alike.

- Heading "Played in recorded lists", and one sentence: the share of each archetype's lists
  recorded in Cartodex that play this card in any printing, the same figures as the archetype's
  analysis. Wording stays *recorded in Cartodex* (no metagame share — see
  `docs/architecture/archetype-metagame.md`).
- Venue select (`Ui::FilterSelect`, `card-filter` form, GET onto `card_path`) when
  `venue_selectable?`.
- Nested `<details>`, collapsed. Each node: its name, then `"96.9% · 95 of 98 lists"` (the
  percentage spelled as `Archetypes::NameGroupRow` spells it) and, when played, the copies text
  (`Archetypes::CopiesText`), then an **"Analysis" link** carrying the node's parameters. The link
  trails the figures instead of wrapping the name because, inside a `<summary>`, a linked name
  takes the tap meant to open the node: the mobile system test (500px, Chrome's floor) clicked the summary's centre and
  navigated away. A 0 % pool reads "not played · 0 of 12 lists". The unplayed tournament count is a
  line inside the pool node.
- Empty state: "No recorded list plays this card." — the card page is reached for every card, and
  749 of the catalogue's cards are played at all.

### Controller

`CardsController#show` calls the service with `params[:venue]`. **A visitor rate limit on `#show`
is added, 120/min under `name: "cards-show"`**, the `ArchetypesController#show` budget and the same
reasoning (`docs/architecture/public-surface.md`): `/cards` renders 48 hover-prefetched links to
this page, and this page now runs an aggregate over up to ~4600 rows. Signed-in members are exempt.

The adversarial review then measured what the "48 links" premise missed: the set view of `/cards`
renders the whole set (191 links on 30C, up to 295), and a visitor hovering 200 of them at 0.15 s
each got 15 answers 429 (13 on a second run). Offered removal (the pre-branch state), 300/min, or
120/min, **the owner kept 120/min** (2026-11-26).

### Cost of the widest card

Measured on the production copy, card page of Boss's Orders (1383 nodes): **476 KB of HTML, 30 KB
gzipped**, about 190 ms warm end to end — of which ~70 ms in the service and ~63 ms rendering the
section (120 ms before the analysis URL was built once per archetype instead of once per node).
Iono: 80 KB, 64 ms. A card no list plays: 14.8 KB, 23 ms.

**The allocation frame's refresh skips the section.** `card_allocation_controller.js` reloads
`card_path` on every collection +/- to extract `#card-allocation`; computing the tree there cost
474 KB and 190 ms per click on Boss's Orders, for a frame of 8 KB. With the `Turbo-Frame` header
naming that frame, `#show` does not call the service: 15 KB, 19 ms. A lazy Turbo Frame for the section was weighed and not taken: it
would keep the hover prefetch from `/cards` off the aggregate, at the price of a new public route,
its policy and rate limit, and a frame-navigated limited action that swallows its 429
(`docs/architecture/deck-odds.md`); the visitor rate limit above bounds the same cost with none of
that.

## Follow-up: the Standard pool and Tournament selects (owner, 2026-11-27)

After the first deploy the owner asked for the analysis's whole cascade, not the Venue axis alone,
and chose **All formats as the default pool**, so the page opens on the tree shipped first. The
analysis defaults to the newest pool because it reports one archetype; this section reports a card
across all of them.

- **Standard pool** — the pools a list plays the card in, most recent playing event first, then
  "All formats"; each label counts the lists playing the card over **both venues**, so it does not
  move when a venue is chosen (the analysis's stable-label rule). A control only where it is a
  choice — where All formats and the one played pool are different samples *of the archetypes'
  lists*, not of the card's: the first rule, copied from the analysis (two played pools, or one
  plus a playing list outside Standard), hid the select on 178 of 259 one-pool cards whose
  archetype lines blend other rotations (truthfulness review, 2026-11-27).
- **Venue** — counted and clamped inside the pool selection.
- **Tournament** — the events of the pool + venue selection where a list plays the card, newest
  first, after "All tournaments"; a control from two such events.
- **The tree loses the level a select fixes.** Under one pool an archetype opens onto its events in
  that pool (its line is the pool's figure, links `{pool: id}`); under one event it is a leaf (links
  `{pool: id|"all", tournament: id}` — the tournament never drives the pool).
- Junk, out-of-selection or unoffered values resolve to "all" — compared as Strings, never `to_i`.

Measured on the production copy: the parity walk over every selection the three selects offer
(capped at 40 events per selection) compared 20846 nodes on 7 cards, 0 differences. Boss's Orders:
517 KB / ~195 ms by default (41 KB more than before, the Tournament select's ~370 events), 319 KB
under TEF-PBL, 56 KB under TEF-PBL + Paper. Still five queries.

## Out of scope

- Any other filter (tier, date range, division) — the analysis's three are now all here.
- The figure for a *name* across fingerprints (the analysis's name group line): the card page
  describes one card.
- Caching.
