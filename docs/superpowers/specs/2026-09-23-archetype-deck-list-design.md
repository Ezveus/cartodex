# The archetype page lists its decks; the metagame report moves to its own page

## Goal

`/archetypes/:slug` answers "which decks are this archetype?" first. The deck list is the first
thing on the page: the reader's own decks (private and shared) when signed in, then every public
deck of the archetype, paginated. The existing metagame report (sample selector, performance
panel, card report, method note, identity block) moves unchanged to `/archetypes/:slug/analysis`,
linked from the list.

Decided with the owner, one question at a time (2026-09-23):

1. **Membership, rule A.** A field-list deck (ownerless, attached to a standing) belongs to the
   archetype of its **standing**. A member's deck belongs to the archetype in `decks.archetype_id`.
2. **No variants.** The page of a parent archetype lists that archetype's decks only, the way
   `Archetypes::MetagameScope` counts its standings. Variants stay one click away through the
   identity block on the analysis page.
3. **"Your decks" first.** A signed-in reader's own decks of this archetype come in their own
   section, above the public list, unpaginated. The public list never repeats them.
4. **Most recent event first.** The public list is ordered by event date descending, then
   placement ascending. A deck with no standing sorts at the date it was created.
5. **No filters in v1.** Each field list carries a caption naming its event and placement, which
   is what makes the ordering readable.

Follow-ups filed: #195 (realign `Decks::ArchetypeDetector` with standings and migrate existing
field lists) and #196 (move this listing from rule A to reading `decks.archetype_id` alone, once
#195 has landed).

## Why rule A and not `decks.archetype_id`

Measured on the development database, a copy of production (2026-09-23):

- 1270 decks. 1192 of them are ownerless field lists that carry an archetype; 43 are members'
  private decks that carry one; 2 are members' shared decks that carry one.
- 1223 standings carry a deck. **405** of those decks carry an archetype that differs from their
  standing's, and 31 carry none. The largest disagreements are the detector's documented failure
  (`docs/architecture/limitless-imports.md`): 62 *Dragapult ex* standings whose deck says
  *Dragapult ex / Dusknoir*, 37 *Slowking* standings whose deck says *Lillie's Clefairy ex*.
- Every ownerless deck belongs to exactly one standing today (0 decks in more than one, 0 ownerless
  decks in none). `index_tournament_standings_on_deck_id` is **not** unique, though, and
  `docs/architecture/archetype-metagame.md` records that two standings may legitimately point at
  one deck. The listing must therefore not multiply a deck by its standings.

Listing by `decks.archetype_id` would show most *Slowking* lists on the *Lillie's Clefairy ex*
page, and the list would disagree with the analysis one click away, whose population is keyed on
the standing.

## Behaviour

### `/archetypes/:slug` — `ArchetypesController#show`

In order:

1. **Header.** The archetype's name, its `Ui::ArchetypeBadge`, an **Analysis** button
   (`analysis_archetype_path`) and **Back to Archetypes**.
2. **Your decks.** Rendered only for a signed-in reader who owns at least one deck whose
   `archetype_id` is this archetype. Every such deck, private or shared, ordered by name, with no
   pagination. Each card's caption says `Private` or `Shared`.
3. **Decks.** The public list: shared decks of this archetype under rule A, excluding the reader's
   own, 24 per page (`ArchetypesController::PER_PAGE`, the catalog's number). A field list's
   caption reads `<event name> — <placement ordinal> · <Division>`, for example
   `EUIC 2026 — 12th · Masters`. A standing with no placement drops the ordinal. A member's shared
   deck carries no caption.
4. **Empty state.** No public deck: `No public deck of this archetype yet.` When the archetype has
   recorded standings, the sentence adds that its results are in the analysis, with a link.

The pager is `Ui::Pagination` **without** a Turbo Frame and without `turbo_action`. It makes full
page visits. Two reasons: the page has no live filter for a frame to serve, and a frame-navigated
action under a `rate_limit` swallows its 429 in silence (the trap `docs/architecture/deck-odds.md`
records for `decks#odds`). `?page=` is clamped to `1..pages`, as `#index` clamps it, and read
through `to_s.to_i` for the same malformed-shape reason.

The deck cards are `Decks::DeckCard` with `with_actions: false, public_listing: true`, for the
reader's own decks too. The owner's badges (Physical, Proxies…) read the collection and belong on
`/decks`; this page answers a different question. Two keywords are added to `Decks::DeckCard`:

- `caption:` — an optional String printed under the deck name, inside the link;
- `archetype_badge:` — default `true`; this page passes `false`. The badge is redundant on the
  archetype's own page, and on a field list it names the deck's own tag, which is the column that
  disagrees with the standing in 405 cases. `Decks::PublicBadges` gains the same keyword.

The type stripe still reads `deck.archetype.energy_types`, as it does on every other listing, so a
mis-tagged field list keeps the stripe of its own tag here too. #195 is what fixes the data. This
page does not paper over it.

**Legacy report URLs.** A request to `/archetypes/:slug` carrying `pool`, `venue` or `group`
redirects with 301 to `/archetypes/:slug/analysis` with the same query parameters. Those three
parameters only ever meant something to the report, and links to them have been shared since the
report became public. A request with none of them renders the list. The redirect runs after
`authorize`, which it depends on for nothing, but the rule that nothing runs before `authorize`
holds everywhere in this controller.

### `/archetypes/:slug/analysis` — `ArchetypesController#analysis`

This is today's `#show`, moved verbatim. It keeps the same preloads, the same `MetagameScope`,
`CardStats`, `Performance` and `Og::ArchetypePayload` calls, and the same 17-query budget, now
pinned on this action. `Archetypes::ShowView` is renamed `Archetypes::AnalysisView`. Its header
keeps **Back to Archetypes** and gains a link back to the deck list (**Decks**). Every self-link
of the report moves to `analysis_archetype_path`: `Archetypes::SampleSelector`'s form action and
`Archetypes::CardReport#path_for`. `Archetypes::Identity`'s parent and variant links keep
`archetype_path`: they go to another archetype, and its front page is now the list.

Route: `resources :archetypes, only: [ :index, :show ] { member { get :analysis } }`. It is
nested under `:id`, so no new entry in `Archetype::RESERVED_SLUGS`.

## Data

`Archetypes::DeckList.call(archetype:, viewer:, page:)` returns a `Result` with `own_decks`
(Array), `decks` (Array, one page), `page`, `pages` and `total`.

**Public relation.**

```ruby
member_ids = TournamentStanding.where(archetype_id: a.id).where.not(deck_id: nil).select(:deck_id)
Deck.shared
    .where(user_id: nil, id: member_ids)
    .or(Deck.shared.where.not(user_id: nil).where(archetype_id: a.id))
```

Minus the viewer's decks, written as `where(user_id: nil).or(where.not(user_id: viewer.id))` and
never as `where.not(user_id: viewer.id)` alone: SQL evaluates `NULL != ?` to NULL, so that form
drops every field list for a signed-in reader. `Search::Global#shared_deck_scope` already fell
into this trap once (CLAUDE.md, *A Deck may belong to no member*).

**Order.** Two correlated sort keys, not a JOIN. A JOIN on `tournament_standings` would repeat a
deck once per standing, and the index does not forbid two:

```sql
COALESCE((SELECT MAX(t.date) FROM tournament_standings s JOIN tournaments t ON t.id = s.tournament_id
          WHERE s.deck_id = decks.id), date(decks.created_at)) DESC,
(SELECT MIN(s.placement) FROM tournament_standings s WHERE s.deck_id = decks.id) ASC NULLS LAST,
decks.id DESC
```

`decks.id DESC` makes the order total, so a page boundary never moves between two requests.

**Own decks.** `viewer.decks.where(archetype_id: a.id).order(:name)`. The table holds 43 private
tagged decks in total, so no pagination.

**Preloads**, for both lists: `deck_cards` (card count), `Deck.with_standard_pool` (the format
badge reads the pool name and its two bounds), `archetype: [ :primary_card, :secondary_card ]`
(the stripe) and `tournament_standing: :tournament` (the caption). The caption reads the
`has_one`, so a deck held by two standings is captioned from one of them. No such deck exists
today, and the listing is unaffected either way.

**Measured cost** on the development database, for *Dragapult ex*, the largest archetype (174
public decks, 8 pages): the page query costs 0.3 ms of CPU in the `IN (…)` form above and 0.9 ms
as a LEFT JOIN over every shared deck. `EXPLAIN QUERY PLAN` for the `IN` form searches
`index_tournament_standings_on_archetype_id` and the decks primary key, where the JOIN form scans
all 1225 shared decks through `index_decks_on_shared_and_created_at`.

**Query budget.** `#show` has a flat cost, independent of the number of decks and pinned by a
test that grows the list. Estimated at 14 statements before implementation, **measured at 11** for
a visitor: the archetype and its member card, the count, the page, then one preload each for the
pools, their two bounds (a single `card_sets` read), the deck cards, the decks' own archetypes and
their member cards, the standings and their events. An archetype with a secondary card adds one
read. A member pays one page query plus the same preloads again for "Your decks", flat in the number
of their decks. Counted inside `ActiveRecord::Base.uncached`, which is how `Groups`' flat-cost test
avoids being fooled by the query cache.

## Public surface

- `publicly_reachable :index, :show, :analysis`. `ArchetypePolicy#analysis?` is written out as
  `true`, one by one like the other reads, rather than aliased.
- Rate limits: `#show` keeps `SHOW_RATE_LIMIT_TO = 120` under the name `"archetypes-show"`. The
  amplifier that sized it, hover prefetch over the index's 24 row links, still points at `#show`.
  `#analysis` gets its own limiter, `ANALYSIS_RATE_LIMIT_TO = 60`, named `"archetypes-analysis"`,
  exempt when signed in. The report is now reached by one link from the list, plus its own
  controls (sample select, mode links), which are deliberate clicks. 60 is the number the app gives
  to a page driven by deliberate navigation (`tournaments#index`, `decks#shared`). Separate names
  keep the budgets apart, the reason `ArchetypesRateLimitTest` exists.
- A member's private deck appears only in that member's own "Your decks". The public relation
  starts from `Deck.shared`, and the viewer's own list is scoped by `viewer.decks`.
- `Og::ArchetypePayload` is assigned on both actions. It reads the two preloaded member cards and
  costs nothing. `og:url` stays `archetype_url`, which is now the list page.
- Neither page is indexed. `XRobotsTagMiddleware` covers both, unchanged.

## Out of scope

- Filters, search, and a pool selector on the list (decision 5).
- Variants' decks on a parent's page (decision 2).
- Fixing field lists' `decks.archetype_id` (#195) and the switch to it (#196).
- The owner's collection badges on "Your decks".

## Testing

- **Service** (`Archetypes::DeckListTest`): rule A in both directions. A field list whose deck tag
  is X but whose standing is Y appears under Y, not under X. A member's shared deck tagged X
  appears under X. A member's private deck of another member never appears. The viewer's decks are
  excluded from the public list while field lists remain (the NULL trap). The order holds across
  event date, placement, a deck with no standing, and ties. A deck held by two standings is listed
  once. Pagination and the clamp.
- **Controller**: the list renders before any report markup. "Your decks" appears for the owner
  and not for a visitor. Captions. The empty state and its analysis link. The legacy parameters
  redirect with 301, and a request without them does not. Flat cost for `#show`. Every existing
  report test moves to `analysis_archetype_path`, including the 17-query literal.
- **Public access, rate limit, navbar**: `#analysis` is reachable without a session, has its own
  budget in both directions, and lights "Archetypes".
- **System**: the existing metagame system test navigates to the analysis through the list's
  button. One new test covers the list and its link, on both viewports.
