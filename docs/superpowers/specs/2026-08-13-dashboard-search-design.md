# Dashboard Text Search (decks, cards, tournaments) — Design

**Date:** 2026-08-13
**Status:** Approved
**Issue:** [#86](https://github.com/Ezveus/cartodex/issues/86)

## Goal

The dashboard offers no way to reach a record by name — you have to walk to an index page first.
Add one text field on the dashboard that searches by name across the three things users look for:
**decks**, **cards** and **tournaments**, with grouped, live results.

## Confirmed decisions (from the brainstorming interview)

1. **Spotlight panel.** The field sits under the dashboard heading; results render in a floating
   panel overlaid below the input (`position: absolute`), so the dashboard cards never move.
2. **Full keyboard navigation.** `↑`/`↓` move a highlighted selection, `Enter` opens it, `Escape`
   closes, `⌘K` / `/` focus the field, with combobox/listbox ARIA wiring.
3. **5 results per group, and a real "see all" link per group.** Which means `q` gets added to the
   decks and tournaments indexes (only `/cards?q=` exists today).
4. **Unicode-correct matching everywhere.** `name_normalized` is extended to `decks`,
   `tournaments` and `archetypes`, behind a shared `NameNormalizable` concern.
5. **Query orchestration in a service**, `Search::Global`; **`q` handling and every use of that
   service in a controller concern**, `Searchable`.

## Vocabulary

- **Query** — the trimmed `q` param.
- **Group** — one of the three result buckets: Decks, Cards, Tournaments.
- **Cap** — the maximum rows rendered per group (5). **Total** — the unrestricted match count for
  that group, used both for the group header and the "see all" link label.

## Matching rules

### Why normalization

SQLite's `LIKE` folds ASCII `A–Z` and nothing else, so `name LIKE '%FLABÉBÉ%'` never matches
"Flabébé". `Card` already solves this by matching against `name_normalized` (a Unicode-downcased
mirror of `name`, maintained by a `before_save` callback). `Deck`, `Tournament` and `Archetype` have
no such column, so today an accented query in the wrong case silently returns nothing for them.

### `NameNormalizable`

New `app/models/concerns/name_normalizable.rb`, holding what is currently spelled out on `Card`:

```ruby
module NameNormalizable
  extend ActiveSupport::Concern

  included do
    before_save :normalize_name

    scope :name_matching, ->(query) {
      where("#{table_name}.name_normalized LIKE ? ESCAPE '\\'", "%#{normalize_for_match(query)}%")
    }
  end

  class_methods do
    # The escaping is two rules stacked, both required:
    # - sanitize_sql_like turns a user-typed % or _ into a literal
    # - ESCAPE '\' is what makes SQLite honour that backslash (it has no default
    #   escape character, so without the clause the backslash matches itself).
    # ESCAPE is standard SQL, so this survives the PostgreSQL move in #62.
    def normalize_for_match(query)
      sanitize_sql_like(query.to_s.downcase)
    end
  end

  def normalize_name
    self.name_normalized = name&.downcase
  end
end
```

Included by `Card` (column already present; its inline scope, callback and comments move into the
concern), `Deck`, `Tournament` and `Archetype`.

No index on `name_normalized`: a leading-wildcard `LIKE` cannot use one, which is why `cards`
never got one either.

### `Archetype.search`

Keeps its shape — three columns, one `ESCAPE` clause per `LIKE` — but reads the `*_normalized`
columns and builds its pattern with `normalize_for_match`, so an accented archetype or Pokémon name
matches in any case:

```ruby
scope :search, ->(q) {
  like = "LIKE :q ESCAPE '\\'"
  left_joins(:primary_pokemon, :secondary_pokemon)
    .where(
      "archetypes.name_normalized #{like} OR cards.name_normalized #{like} " \
      "OR secondary_pokemons_archetypes.name_normalized #{like}",
      q: "%#{normalize_for_match(q)}%"
    )
    .distinct
}
```

### `Deck.search`

A deck matches on its own name **or** through its archetype (so a deck tagged `Gardevoir ex`
surfaces for "Gardevoir" whatever it is named). The archetype side goes in as a subquery rather
than a join: `Archetype.search` carries its own `left_joins` and `distinct`, which `.or` refuses to
merge, and the subquery keeps the deck rows unduplicated.

```ruby
scope :search, ->(q) {
  name_matching(q).or(where(archetype_id: Archetype.search(q).select(:id)))
}
```

### `Tournament`

`name_matching` only — per the issue, a tournament matches on its own name.

### Migration

`add_column :decks, :name_normalized, :string` (same for `tournaments`, `archetypes`), then a
backfill in the same migration. `LOWER()` in SQL would only fold ASCII, so the backfill runs in
Ruby to match what the callback produces:

```ruby
[ Deck, Tournament, Archetype ].each do |model|
  model.unscoped.select(:id, :name).find_each do |record|
    model.unscoped.where(id: record.id).update_all(name_normalized: record.name&.downcase)
  end
end
```

The migration declares its own minimal AR classes rather than referencing the app models, so a
later model change can't break a replay of this migration.

### Fixtures

Fixtures are inserted without callbacks, so `decks.yml`, `tournaments.yml` and `archetypes.yml`
spell `name_normalized` out by hand — exactly as `cards.yml` does. One test per model asserts the
column is in step with `name`, mirroring the existing `CardTest` guard.

## `Search::Global`

`app/services/search/global.rb`, an `ApplicationService`. Read-only, so no
`serialized_transaction`.

```ruby
Search::Global.call(user:, query:, limit: DEFAULT_LIMIT)
# → Search::Global::Result
```

- `MIN_QUERY_LENGTH = 2`, `DEFAULT_LIMIT = 5`.
- Below `MIN_QUERY_LENGTH` (including a blank query) it returns an empty result **without touching
  the database** — this is what keeps a one-letter query cheap.
- `Result` is a `Data.define(:query, :decks, :deck_total, :cards, :card_total, :tournaments,
  :tournament_total)` with `blank?` (query too short) and `any?` (at least one match) predicates,
  so the view never re-derives either.

Per group:

| Group | Scope | Order | Eager-loaded |
|---|---|---|---|
| Decks | `user.decks.search(q)` | `name` | `archetype: :primary_pokemon` |
| Cards | `apply_card_name_filter(Card.all, q)` | `name`, `set_name` | `card_set` |
| Tournaments | `user.tournaments.name_matching(q)` | `date DESC` | `deck` |

Decks and tournaments are scoped to the user (both are user-owned); **cards search the whole
catalog**, not just the user's collection.

Cards reuse `CardSearchable#apply_card_name_filter` — the same matcher the cards page uses — so
"Pikachu SVI 25" behaves identically in the spotlight and on `/cards`, and the "see all N cards"
count is the count that page will actually show. `CardSearchable` lives in
`app/controllers/concerns/` but is a plain module with no controller dependency; including it in
the service is deliberate and noted in a comment rather than duplicating the tokenizer.

Each group costs a `count` plus a capped fetch: 6 queries for a non-blank query, 0 for a blank one.

## `Searchable` (controller concern)

`app/controllers/concerns/searchable.rb` owns the `q` param and every call into `Search::Global`,
so the three entry points cannot drift on the param name or on trimming:

```ruby
module Searchable
  extend ActiveSupport::Concern

  private

  # The `q` param, trimmed; "" when absent.
  def search_query
    @search_query ||= params[:q].to_s.strip
  end

  # Grouped decks/cards/tournaments matches for the current user.
  def search_results(limit: Search::Global::DEFAULT_LIMIT)
    Search::Global.call(user: current_user, query: search_query, limit: limit)
  end
end
```

The 2-character cut-off is the service's alone. The index pages filter as soon as `q` is present:
they render a full, unrestricted page, so a one-letter filter there is harmless.

## Routes and controllers

```ruby
get "search", to: "search#show"   # inside the `authenticate :user` block
```

`SearchController#show` — `include Searchable`, `layout false` (the response only ever needs to
carry the frame, and it is re-fetched on every keystroke):

```ruby
def show
  @query   = search_query
  @results = search_results
end
```

`DecksController` — `include Searchable`; `q: search_query.presence` joins `filter_params`, and
`filter_decks` applies `scope.merge(Deck.search(filters[:q]))`. Same scope as the spotlight, so
"See all 12 decks" lands on a page showing 12 decks. The index filter bar gains a search input.

`TournamentsController#index` — `include Searchable`; filters with `Tournament.name_matching` when
`search_query` is present, exposes `@query` for the input value, and its index gains the same
input.

`/cards?q=` already exists and is untouched.

## Views (Phlex)

| Component | Responsibility |
|---|---|
| `Search::Spotlight` | Positioned wrapper: the `GET /search` form targeting the frame, the combobox input, and the (initially empty) frame. Rendered by the dashboard. |
| `Search::ResultsView` | `turbo_frame_tag(FRAME_ID)` wrapping the listbox: the three groups, or a "no matches" line, or nothing at all when the query is blank. |
| `Search::ResultGroup` | One group: header, its rows, and the "see all" link. |

Group rendering rules, so the three groups stay predictable:

- An **empty group renders nothing at all** — no header, no "0 matches" line. When every group is
  empty (and the query is long enough), `Search::ResultsView` renders a single "No matches" line
  instead.
- The header carries the count: `TOURNAMENTS · 3` when everything fits, `DECKS · 5 of 12` when the
  cap truncated it.
- The "see all" link renders for **every non-empty group**, truncated or not — `See all 12 decks`,
  `See all 3 tournaments` — because it is also the way to reach that index pre-filtered.

`FRAME_ID = "search_results"` is defined on `Search::ResultsView` and referenced by
`Search::Spotlight`, so the two can't disagree.

Row content and destination:

| Group | Row | Links to |
|---|---|---|
| Deck | name · format label · archetype name | `deck_path` |
| Card | name · `set_name #set_number` (+ thumbnail) | `card_path` |
| Tournament | name · date · tier label | `tournament_path` |

Rows are `<a>` elements carrying `role="option"` and a stable `id` (`search-option-<n>`), so the
keyboard controller can point `aria-activedescendant` at one while `Enter` and `Tab` keep their
native link behaviour.

ARIA wiring: the input is `role="combobox"` with `aria-controls`, `aria-expanded`,
`aria-autocomplete="list"`; the results container is `role="listbox"`. Only the panel's open state
is toggled — the frame's content is whatever the last response put there.

`Home::DashboardView` renders `Search::Spotlight` under its `h1`. `Styleguide::PageView` gains a
"Spotlight search" section showing the field and a static, pre-populated results panel (no live
frame), per the styleguide rule in CLAUDE.md.

## Stimulus

`app/javascript/controllers/dashboard_search_controller.js`, targets `input`, `panel`.

| Trigger | Behaviour |
|---|---|
| `input` | debounce 300 ms, then `requestSubmit()` on the form (Turbo swaps the frame) |
| `keydown.down` / `keydown.up` | move `activeIndex` with wrap-around, set `aria-activedescendant`, `scrollIntoView({ block: "nearest" })` |
| `keydown.enter` | `click()` the active option; falls through to native submit when nothing is active |
| `keydown.esc` | clear the input, empty the panel, collapse |
| `turbo:frame-load` | re-collect options, reset `activeIndex`, set `aria-expanded` |
| document `click` outside | collapse |
| document `keydown` `⌘K` / `/` | focus the input — ignored when the event target is already an input, textarea, select or `contenteditable`, so `/` stays typable |

The debounce delay is a Stimulus value (`delay`, default 300) to match
`card_filter_controller.js`. Below the minimum length the controller skips the request and empties
the panel locally, so the service's cut-off is never reached by a wasted round-trip. That minimum
is **not** duplicated in JavaScript: `Search::Spotlight` passes it down as a Stimulus value
(`min_length: Search::Global::MIN_QUERY_LENGTH`), keeping the service the single source of truth.

## CSS

A `.spotlight-*` block appended to `app/assets/stylesheets/application.css`, using existing tokens
only: `--surface` for the panel, `--e2` for its elevation, `--flare` for the active option,
`--font-*` for the group headers. `position: absolute; z-index: 50` mirrors
`.card-search-results`, and the mobile media query at the bottom of the file takes the panel to
`width: 100%`.

## Testing

**Models**
- `Deck` / `Tournament`: `name_matching` folds accented case; `%` and `_` in the query stay
  literal.
- `Deck.search`: matches through the archetype (deck named otherwise, archetype `Gardevoir ex`,
  query "gardevoir"); returns each deck once; doesn't match another user's decks when chained off
  `user.decks`.
- `Archetype.search`: accented case folding through all three columns.
- One "fixture carries the normalization its name implies" test per newly-normalized model.

**Service** (`test/services/search/global_test.rb`)
- Groups and caps: 7 matching decks → 5 rows, `deck_total == 7`.
- `blank?` for `""` and for a 1-character query, with no rows in any group.
- Another user's decks and tournaments are excluded; cards outside the user's collection are
  included.
- A card query with a set code and number ("Pikachu SVI 25") resolves through
  `apply_card_name_filter`.

**Controllers**
- `/search` requires authentication; renders the frame; a 1-character query renders an empty
  panel; a matching query renders one row per group.
- `/decks?q=` and `/tournaments?q=` filter, and their counts agree with the spotlight totals for
  the same query.

**Not covered automatically:** keyboard navigation and the floating panel have no system test —
the repo has none, and adding the first Capybara suite is out of scope for this issue. Verified by
hand in the running app before the branch is proposed.

## Out of scope

- A global search field in the navbar (this issue is the dashboard).
- Searching anything beyond names: card text, attacks, deck contents.
- Fuzzy matching, ranking or relevance ordering — substring match, deterministic order.
- Pagination inside the panel; the "see all" links are the escape hatch.
