# Dashboard Text Search Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add one text field on the dashboard that searches decks, cards and tournaments by name, showing grouped live results in a keyboard-navigable floating panel.

**Architecture:** A shared `NameNormalizable` model concern carries the Unicode-safe `LIKE`
matching (already proven on `Card`) to `Deck`, `Tournament` and `Archetype`. `Search::Global`
composes the three scopes into a capped, counted result object. A `Searchable` controller concern
owns the `q` param and every call into that service, and is included by `SearchController` (the
Turbo Frame endpoint) as well as the decks and tournaments indexes. Phlex components render the
combobox and the frame; one Stimulus controller handles debounce and keyboard navigation.

**Tech Stack:** Rails 8.1, Ruby 3.4.1, SQLite3, Phlex 2.4 (all views), Hotwire (Turbo + Stimulus
3.2 via importmap), Minitest with fixtures, rubocop-rails-omakase.

**Spec:** `docs/superpowers/specs/2026-08-13-dashboard-search-design.md` — read it before starting.

**Issue:** [#86](https://github.com/Ezveus/cartodex/issues/86)

## Global Constraints

- **All views are Phlex.** ERB files are one-line wrappers that render a component. Never put view
  logic in ERB. See the `phlex-architecture` skill.
- **`tokens()` is not available in Phlex 2.4.** For conditional classes use
  `[ "a", ("b" if cond) ].compact.join(" ")`.
- **Never call `raw()`** in a Phlex component; use markup methods.
- **Every `LIKE` needs its own `ESCAPE '\'` clause** and its query run through `sanitize_sql_like`.
  SQLite has no default escape character, so without the clause the backslash matches itself.
- **A test for accent folding must store an uppercase accented name** (`"FLABÉBÉ"`, not
  `"Flabébé"`) and query it in lowercase. With the accent already lowercase in the stored value,
  SQLite's ASCII fold alone makes the query match, and the test passes even when the scope stops
  reading `name_normalized` — proving nothing. This bit the first draft of Tasks 2 and 3.
- **Comments and code in English.** Documents committed to the repo are in English.
- **CSS uses design-system tokens only** (`var(--surface)`, `var(--flare)`, `var(--e2)`, …) — no
  literal hex colours. Tokens live at the top of `app/assets/stylesheets/application.css`.
- **Business logic lives in `app/services/`**, inheriting `ApplicationService` (which provides
  `.call(...)`). This feature is read-only, so no `serialized_transaction`.
- **Update `/styleguide`** (`Styleguide::PageView`) when adding a UI component.
- Run `bin/rubocop` before each commit; CI runs `bin/brakeman --no-pager`, `bin/importmap audit`,
  `bin/rubocop -f github` and `bin/rails db:test:prepare test test:system`.
- Work on the existing branch `feature/86-dashboard-search`.

---

## File Structure

**Created**

| File | Responsibility |
|---|---|
| `app/models/concerns/name_normalizable.rb` | `normalize_name` callback + `name_matching` scope + `normalize_for_match` helper |
| `db/migrate/<ts>_add_name_normalized_to_deck_tournament_archetype.rb` | column on three tables + Ruby backfill |
| `app/services/search/global.rb` | `Search::Global` + its `Result` value object |
| `app/controllers/concerns/searchable.rb` | `search_query` / `search_results` |
| `app/controllers/search_controller.rb` | `GET /search`, frame-only response |
| `app/views/search/show.html.erb` | one-line Phlex wrapper |
| `app/views/components/search/results_view.rb` | the turbo-frame wrapper, owns `FRAME_ID` |
| `app/views/components/search/results_list.rb` | the listbox: three groups, "no matches", or nothing |
| `app/views/components/search/result_group.rb` | one group: header, rows, "see all" link |
| `app/views/components/search/spotlight.rb` | wrapper, form, combobox input, empty frame |
| `app/javascript/controllers/dashboard_search_controller.js` | debounce + keyboard navigation |
| `test/services/search/global_test.rb` | grouping, caps, totals, scoping |
| `test/controllers/search_controller_test.rb` | endpoint + rendered frame |
| `test/controllers/home_controller_test.rb` | the dashboard renders the spotlight |

**Modified**

| File | Change |
|---|---|
| `app/models/card.rb` | include the concern, drop the inlined scope/callback |
| `app/models/deck.rb` | include the concern, add `search` scope |
| `app/models/tournament.rb` | include the concern |
| `app/models/archetype.rb` | include the concern, `search` reads `*_normalized` |
| `test/fixtures/{decks,tournaments,archetypes}.yml` | add `name_normalized` |
| `config/routes.rb` | `get "search"` |
| `app/controllers/decks_controller.rb` | `q` filter |
| `app/controllers/tournaments_controller.rb` | `q` filter |
| `app/views/components/decks/index_view.rb` | search input in the filter bar |
| `app/views/components/tournaments/index_view.rb` | search form above the table |
| `app/views/components/home/dashboard_view.rb` | render the spotlight |
| `app/views/components/styleguide/page_view.rb` | "Spotlight search" section |
| `app/assets/stylesheets/application.css` | `.spotlight-*` block + mobile rule |
| `test/models/{deck,tournament,archetype,card}_test.rb` | scope tests, fixture-consistency guards |
| `test/controllers/{decks,tournaments}_controller_test.rb` | `q` filter tests |
| `test/controllers/styleguide_controller_test.rb` | unique frame/option ids in the demo |

---

## Task 1: `NameNormalizable` concern (Card refactor, no behaviour change)

**Files:**
- Create: `app/models/concerns/name_normalizable.rb`
- Modify: `app/models/card.rb:24-44` (the `name_matching` scope, the `before_save :normalize_name`
  line, and the `normalize_name` method at `app/models/card.rb:71-77`)
- Test: `test/models/card_test.rb` (existing tests must keep passing untouched)

**Interfaces:**
- Consumes: nothing.
- Produces: `NameNormalizable`, giving every including model the scope
  `name_matching(query) → ActiveRecord::Relation`, the class method
  `normalize_for_match(query) → String` (downcased, `sanitize_sql_like`-escaped, no `%` wrappers)
  and the instance method `normalize_name` (a `before_save` callback assigning
  `name_normalized = name&.downcase`). Requires the including model's table to have `name` and
  `name_normalized` string columns.

- [ ] **Step 1: Run the existing card tests to capture the green baseline**

Run: `bin/rails test test/models/card_test.rb`
Expected: PASS (this task must not change any behaviour, so this exact command must still pass at
the end).

- [ ] **Step 2: Create the concern**

Create `app/models/concerns/name_normalizable.rb`. The comments are moved verbatim from
`app/models/card.rb` — they explain *why* this exists and must not be dropped:

```ruby
# Case-insensitive, Unicode-safe substring matching on a model's `name`.
#
# Matching runs against `name_normalized` (a mirror of `name`, Unicode-downcased by the callback
# below) rather than against `name`, because SQLite's LIKE only folds ASCII A–Z:
# `name LIKE '%POKÉMON%'` never matches "Pokémon", so an accented query in the wrong case
# silently returned nothing. Normalising both sides in Ruby makes the fold Unicode-aware and
# keeps the comparison a plain LIKE the database can run.
#
# Including models need `name` and `name_normalized` string columns. Fixtures are inserted
# without callbacks, so their YAML must spell `name_normalized` out by hand — each including
# model has a test asserting the two stay in step.
module NameNormalizable
  extend ActiveSupport::Concern

  included do
    before_save :normalize_name

    scope :name_matching, ->(query) {
      where("#{table_name}.name_normalized LIKE ? ESCAPE '\\'", "%#{normalize_for_match(query)}%")
    }
  end

  class_methods do
    # Downcased and LIKE-escaped, ready to be wrapped in `%…%`.
    #
    # The query's LIKE metacharacters are escaped so a `%` or `_` typed by a user matches
    # literally instead of acting as a wildcard. ESCAPE is required, not decorative:
    # sanitize_sql_like escapes with a backslash, but SQLite's LIKE has no default escape
    # character, so without the clause the backslash itself would be matched. ESCAPE is standard
    # SQL, so this survives the move to PostgreSQL contemplated in #62.
    def normalize_for_match(query)
      sanitize_sql_like(query.to_s.downcase)
    end
  end

  # Mirror of `name`, Unicode-downcased, so name_matching can search with a plain LIKE instead of
  # depending on the database's own case folding.
  def normalize_name
    self.name_normalized = name&.downcase
  end
end
```

- [ ] **Step 3: Make `Card` use it**

In `app/models/card.rb`, delete the `name_matching` scope together with its comment block (lines
24–40), delete `before_save :normalize_name` from the callbacks section, and delete the
`normalize_name` method and its comment (lines 71–77). Add the include as the first line of the
class body:

```ruby
class Card < ApplicationRecord
  include NameNormalizable

  # Relationships
  belongs_to :card_set, optional: true
```

Leave `before_save :compute_fingerprint` in place. The `# Callbacks` section then reads:

```ruby
  # Callbacks
  before_save :compute_fingerprint
```

- [ ] **Step 4: Run the card tests — behaviour must be unchanged**

Run: `bin/rails test test/models/card_test.rb`
Expected: PASS, same count as Step 1. In particular "name_matching ignores case on accented
letters", "name_matching treats LIKE metacharacters in the query as literals" and "normalizes the
name on save" still pass.

- [ ] **Step 5: Run the suites that consume the scope**

Run: `bin/rails test test/mcp test/controllers/collections_controller_test.rb test/controllers/cards_controller_test.rb test/controllers/admin`
Expected: PASS. These cover `Card.name_matching`'s four call sites
(`Collection.card_name_matching`, `CardSearchable`, `Admin::CardsController`, `SearchCardsTool`).

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop app/models/card.rb app/models/concerns/name_normalizable.rb
git add app/models/card.rb app/models/concerns/name_normalizable.rb
git commit -m "refactor: extract NameNormalizable from Card"
```

---

## Task 2: `name_normalized` on decks and tournaments

**Files:**
- Create: `db/migrate/<timestamp>_add_name_normalized_to_deck_tournament_archetype.rb`
- Modify: `db/schema.rb` (regenerated by the migration — commit it), `app/models/deck.rb`,
  `app/models/tournament.rb`, `test/fixtures/decks.yml`, `test/fixtures/tournaments.yml`
- Test: `test/models/deck_test.rb`, `test/models/tournament_test.rb`

**Interfaces:**
- Consumes: `NameNormalizable` from Task 1.
- Produces: `Deck.name_matching(query)`, `Tournament.name_matching(query)`, and a
  `name_normalized` column on `decks`, `tournaments` **and `archetypes`** (the column is added for
  all three here so there is only one migration; Task 3 starts using the archetypes one).

- [ ] **Step 1: Write the failing tests**

Append to `test/models/deck_test.rb`, inside the class:

```ruby
  # The stored name carries an uppercase accented letter on purpose: SQLite's LIKE folds F/f but
  # not É/é, so a lowercase query can only match through name_normalized. Were the scope to
  # compare `name` again, this test would go red — that's the regression it exists to catch.
  test "name_matching ignores case on accented letters" do
    deck = decks(:one)
    deck.update!(name: "FLABÉBÉ Toolbox")

    %w[FLABÉBÉ Flabébé flabébé BÉBÉ bébé].each do |query|
      assert_includes Deck.name_matching(query), deck, "#{query.inspect} must match"
    end
  end

  test "name_matching treats LIKE metacharacters in the query as literals" do
    deck = decks(:one)
    deck.update!(name: "Ogerpon Toolbox")

    assert_includes Deck.name_matching("ogerpon"), deck, "sanity: the plain spelling matches"
    assert_empty Deck.name_matching("og_rpon"), "_ must not act as a wildcard"
    assert_empty Deck.name_matching("oger%on"), "% must not act as a wildcard"
  end

  # Fixtures are inserted without callbacks, so decks.yml spells name_normalized out by hand;
  # this is what stops the two from drifting when a fixture name is edited.
  test "every deck fixture carries the normalization its name implies" do
    Deck.find_each do |deck|
      assert_equal deck.name.downcase, deck.name_normalized, "#{deck.name.inspect} fixture is out of step"
    end
  end
```

Append to `test/models/tournament_test.rb`, inside the class:

```ruby
  # Uppercase accented letter in the stored name on purpose — see the note in DeckTest: only
  # name_normalized can match a lowercase query against it.
  test "name_matching ignores case on accented letters" do
    tournament = tournaments(:one)
    tournament.update!(name: "RÉGIONALE de Lyon")

    %w[RÉGIONALE Régionale régionale].each do |query|
      assert_includes Tournament.name_matching(query), tournament, "#{query.inspect} must match"
    end
  end

  test "name_matching treats LIKE metacharacters in the query as literals" do
    assert_includes Tournament.name_matching("regional"), tournaments(:one), "sanity: the plain spelling matches"
    assert_empty Tournament.name_matching("reg_onal"), "_ must not act as a wildcard"
    assert_empty Tournament.name_matching("regi%nal"), "% must not act as a wildcard"
  end

  test "every tournament fixture carries the normalization its name implies" do
    Tournament.find_each do |tournament|
      assert_equal tournament.name.downcase, tournament.name_normalized,
        "#{tournament.name.inspect} fixture is out of step"
    end
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bin/rails test test/models/deck_test.rb test/models/tournament_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'name_matching'`.

- [ ] **Step 3: Generate the migration**

Run: `bin/rails generate migration AddNameNormalizedToDeckTournamentArchetype`

This produces the real timestamp; replace the generated file's body with (modelled on
`db/migrate/20260812093000_add_name_normalized_to_cards.rb`):

```ruby
class AddNameNormalizedToDeckTournamentArchetype < ActiveRecord::Migration[8.1]
  # Isolated from the app models on purpose: this backfill must keep working whatever those
  # classes grow into.
  class MigrationDeck < ActiveRecord::Base
    self.table_name = "decks"
  end

  class MigrationTournament < ActiveRecord::Base
    self.table_name = "tournaments"
  end

  class MigrationArchetype < ActiveRecord::Base
    self.table_name = "archetypes"
  end

  MODELS = [ MigrationDeck, MigrationTournament, MigrationArchetype ].freeze

  # No index: every read of this column is a `LIKE '%…%'` substring match, whose leading wildcard
  # makes a b-tree index unusable. This mirrors the choice made for cards.
  def up
    add_column :decks, :name_normalized, :string
    add_column :tournaments, :name_normalized, :string
    add_column :archetypes, :name_normalized, :string

    # Backfilled in Ruby rather than with SQL `lower()`: SQLite's `lower()` only folds ASCII A–Z,
    # which is exactly the case-folding gap this column exists to close. Ruby's String#downcase
    # applies full Unicode case mapping.
    MODELS.each do |model|
      model.reset_column_information
      model.find_each { |record| record.update_columns(name_normalized: record.name&.downcase) }
    end
  end

  def down
    remove_column :archetypes, :name_normalized
    remove_column :tournaments, :name_normalized
    remove_column :decks, :name_normalized
  end
end
```

- [ ] **Step 4: Migrate and prepare the test database**

```bash
bin/rails db:migrate
bin/rails db:test:prepare
```
Expected: `db/schema.rb` now shows `t.string "name_normalized"` under `create_table "decks"`,
`"tournaments"` and `"archetypes"`.

- [ ] **Step 5: Include the concern in both models**

`app/models/deck.rb` — first line of the class body:

```ruby
class Deck < ApplicationRecord
  include NameNormalizable

  belongs_to :user
```

`app/models/tournament.rb` — first line of the class body:

```ruby
class Tournament < ApplicationRecord
  include NameNormalizable

  belongs_to :user
```

- [ ] **Step 6: Add `name_normalized` to the fixtures**

`test/fixtures/decks.yml` — the full file:

```yaml
# Read about fixtures at https://api.rubyonrails.org/classes/ActiveRecord/FixtureSet.html
#
# NOTE: fixtures skip callbacks, so name_normalized is spelled out by hand. DeckTest asserts it
# stays in step with name.

one:
  user: one
  name: MyString
  name_normalized: mystring
  description: MyText

two:
  user: two
  name: MyString
  name_normalized: mystring
  description: MyText
```

`test/fixtures/tournaments.yml` — add one line to each record:

```yaml
one:
  user: one
  deck: one
  tournament_profile: ash
  name: Regional Championship
  name_normalized: regional championship
  date: 2026-03-14
  format: standard
  tier: regional
  participant_count: 512
  placement: 33
  championship_points: 120

two:
  user: two
  deck: two
  name: Local League Cup
  name_normalized: local league cup
  date: 2026-02-01
  format: standard
  tier: league_cup
  participant_count: 12
  placement: 1
  championship_points: 50
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bin/rails test test/models/deck_test.rb test/models/tournament_test.rb`
Expected: PASS.

Note on the fixture-consistency tests: `DecksControllerTest#setup` renames `decks(:one)` to
`"Original"` through `update!`, which fires the callback — so the guard tests only ever see values
the callback or the YAML produced. If one fails with `nil` for `name_normalized`, the fixture YAML
is missing the line, not the callback.

- [ ] **Step 8: Lint and commit**

```bash
bin/rubocop app/models/deck.rb app/models/tournament.rb db/migrate
git add app/models/deck.rb app/models/tournament.rb db/migrate db/schema.rb \
        test/fixtures/decks.yml test/fixtures/tournaments.yml \
        test/models/deck_test.rb test/models/tournament_test.rb
git commit -m "feat: Unicode-safe name matching on decks and tournaments"
```

---

## Task 3: `Archetype.search` on the normalized columns

**Files:**
- Modify: `app/models/archetype.rb:14-27` (the `search` scope), `test/fixtures/archetypes.yml`
- Test: `test/models/archetype_test.rb`

**Interfaces:**
- Consumes: `NameNormalizable` (Task 1), the `archetypes.name_normalized` column (Task 2).
- Produces: `Archetype.search(query) → ActiveRecord::Relation` — unchanged signature, now
  Unicode-case-insensitive across `archetypes.name_normalized` and both member Pokémon's
  `cards.name_normalized`. Still `distinct`, still carries `left_joins`, so callers must not
  `.or` it directly (Task 4 uses it as a subquery).

- [ ] **Step 1: Write the failing tests**

Append to `test/models/archetype_test.rb`, inside the class:

```ruby
  # The stored name carries an uppercase accented letter on purpose: SQLite's LIKE folds F/f but
  # not É/é, so a lowercase query can only match through name_normalized. Were this scope to read
  # the plain `name` columns again, these two tests would go red — that's what they exist for.
  test "search ignores case on accented letters in the archetype name" do
    archetype = archetypes(:ogerpon)
    archetype.update!(name: "FLABÉBÉ Box", custom_name: "1")

    %w[FLABÉBÉ Flabébé flabébé].each do |query|
      assert_includes Archetype.search(query), archetype, "#{query.inspect} must match"
    end
  end

  test "search ignores case on accented letters in a member Pokémon's name" do
    cards(:budew_pre).update!(name: "FLABÉBÉ")

    %w[FLABÉBÉ Flabébé flabébé].each do |query|
      assert_includes Archetype.search(query), archetypes(:budew_ogerpon), "#{query.inspect} must match"
    end
  end

  test "every archetype fixture carries the normalization its name implies" do
    Archetype.find_each do |archetype|
      assert_equal archetype.name.downcase, archetype.name_normalized,
        "#{archetype.name.inspect} fixture is out of step"
    end
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bin/rails test test/models/archetype_test.rb`
Expected: the two accent tests FAIL (the uppercase spellings don't match), the fixture test FAILS
with `nil` — three failures. The four pre-existing `search` tests still pass.

- [ ] **Step 3: Include the concern and rewrite the scope**

`app/models/archetype.rb` — add the include as the first line of the class body, then replace the
`search` scope (keeping `roots` as it is):

```ruby
class Archetype < ApplicationRecord
  include NameNormalizable

  belongs_to :primary_pokemon, class_name: "Card"
```

```ruby
  scope :roots, -> { where(parent_id: nil) }
  # Matches the archetype's own name or either member Pokémon's, all three through their
  # normalized mirrors (see NameNormalizable). Every LIKE needs its own ESCAPE clause. Spans
  # three columns, so it can't delegate to the concern's single-column scope.
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

- [ ] **Step 4: Add `name_normalized` to the archetype fixtures**

`test/fixtures/archetypes.yml`:

```yaml
# Read about fixtures at https://api.rubyonrails.org/classes/ActiveRecord/FixtureSet.html
#
# NOTE: archetypes hold a foreign key to cards (primary/secondary Pokémon), so
# only reference cards that are not destroyed by other tests (e.g. avoid honedge).
#
# Fixtures skip callbacks, so name_normalized is spelled out by hand; ArchetypeTest asserts it
# stays in step with name.

ogerpon:
  primary_pokemon: teal_mask_ogerpon_ex
  name: "Teal Mask Ogerpon ex"
  name_normalized: "teal mask ogerpon ex"

budew_ogerpon:
  primary_pokemon: budew_pre
  secondary_pokemon: teal_mask_ogerpon_ex
  name: "Budew / Teal Mask Ogerpon ex"
  name_normalized: "budew / teal mask ogerpon ex"
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/models/archetype_test.rb`
Expected: PASS — the three new tests and the four pre-existing ones.

If the first accent test fails on `custom_name`, note that `Archetype#auto_generate_name` rewrites
`name` from the member Pokémon unless `custom_name` is present — that's why the test passes
`custom_name: "1"`.

- [ ] **Step 6: Run the suites that consume `Archetype.search`**

Run: `bin/rails test test/controllers/api test/controllers/admin test/services/decks`
Expected: PASS.

- [ ] **Step 7: Lint and commit**

```bash
bin/rubocop app/models/archetype.rb
git add app/models/archetype.rb test/fixtures/archetypes.yml test/models/archetype_test.rb
git commit -m "feat: Unicode-safe archetype search"
```

---

## Task 4: `Deck.search` — own name or archetype

**Files:**
- Modify: `app/models/deck.rb` (add the scope next to the include from Task 2)
- Test: `test/models/deck_test.rb`

**Interfaces:**
- Consumes: `Deck.name_matching` (Task 2), `Archetype.search` (Task 3).
- Produces: `Deck.search(query) → ActiveRecord::Relation` — decks whose own name matches, or whose
  archetype matches `Archetype.search`. No joins added, no duplicate rows, chainable off
  `user.decks`. This is the single scope shared by `Search::Global` (Task 7) and
  `DecksController#index` (Task 5), which is what keeps the spotlight's "See all N decks" count
  equal to what that page then shows.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/deck_test.rb`, inside the class:

```ruby
  test "search matches the deck's own name" do
    deck = decks(:one)
    deck.update!(name: "Ogerpon Toolbox")

    assert_includes Deck.search("ogerpon"), deck
  end

  # A deck tagged "Teal Mask Ogerpon ex" must surface for "Ogerpon" even when its own name says
  # nothing about it — that's the whole point of composing Archetype.search in.
  test "search matches through the deck's archetype" do
    deck = decks(:one)
    deck.update!(name: "Tuesday List", archetype: archetypes(:ogerpon))

    assert_includes Deck.search("ogerpon"), deck
  end

  test "search matches through the archetype's member Pokémon" do
    deck = decks(:one)
    deck.update!(name: "Tuesday List", archetype: archetypes(:budew_ogerpon))

    assert_includes Deck.search("budew"), deck
  end

  # The archetype side is a subquery, not a join, so a deck matching on both sides is still one row.
  test "search returns each deck once when name and archetype both match" do
    deck = decks(:one)
    deck.update!(name: "Ogerpon Toolbox", archetype: archetypes(:ogerpon))

    assert_equal [ deck.id ], Deck.search("ogerpon").pluck(:id)
  end

  test "search treats LIKE metacharacters in the query as literals" do
    decks(:one).update!(name: "Ogerpon Toolbox", archetype: archetypes(:ogerpon))

    assert_empty Deck.search("og_rpon"), "_ must not act as a wildcard"
    assert_empty Deck.search("oger%on"), "% must not act as a wildcard"
  end

  test "search chains off a user's decks" do
    decks(:one).update!(name: "Ogerpon Toolbox", user: users(:one))
    decks(:two).update!(name: "Ogerpon Toolbox", user: users(:two))

    results = users(:one).decks.search("ogerpon")

    assert_includes results, decks(:one)
    assert_not_includes results, decks(:two)
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bin/rails test test/models/deck_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'search'`.

- [ ] **Step 3: Add the scope**

In `app/models/deck.rb`, after the `before_validation` / `after_update` callbacks and before
`format_label`:

```ruby
  # Matches the deck's own name or its archetype's (which itself spans the archetype name and its
  # member Pokémon). The archetype side goes in as a subquery rather than a join: Archetype.search
  # carries its own left_joins and distinct, which #or refuses to merge, and a subquery keeps the
  # deck rows unduplicated.
  scope :search, ->(query) {
    name_matching(query).or(where(archetype_id: Archetype.search(query).select(:id)))
  }
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bin/rails test test/models/deck_test.rb`
Expected: PASS.

If SQLite raises `ambiguous column name: id`, the subquery's select needs qualifying — change
`.select(:id)` to `.select(Archetype.arel_table[:id])`. If `#or` raises
`Relation passed to #or must be structurally compatible`, a caller has added `includes`/`joins`
before `search`; the fix belongs in the caller (apply `search` first, then `includes`), not here.

- [ ] **Step 5: Lint and commit**

```bash
bin/rubocop app/models/deck.rb
git add app/models/deck.rb test/models/deck_test.rb
git commit -m "feat: add Deck.search spanning name and archetype"
```

---

## Task 5: `q` filter on the decks index

**Files:**
- Create: `app/controllers/concerns/searchable.rb`
- Modify: `app/controllers/decks_controller.rb:132-140` (`filter_params`), `:158-180`
  (`filter_decks`), `app/views/components/decks/index_view.rb:69-78` (`filter_bar`)
- Test: `test/controllers/decks_controller_test.rb`

**Interfaces:**
- Consumes: `Deck.search` (Task 4).
- Produces: `Searchable`, a controller concern with two private methods —
  `search_query → String` (the `q` param, trimmed, `""` when absent, memoized) and
  `search_results(limit:) → Search::Global::Result` (added in Task 7; **do not write it yet**).
  Task 6 and Task 8 include the same concern.

- [ ] **Step 1: Write the failing tests**

Append to `test/controllers/decks_controller_test.rb`, inside the class:

```ruby
  test "index filters decks by name" do
    @deck.update!(name: "Ogerpon Toolbox")
    other = @user.decks.create!(name: "Charizard Pidgeot")

    get decks_path(q: "ogerpon")

    assert_response :success
    assert_select "#decks-grid", text: /Ogerpon Toolbox/
    assert_select "#decks-grid", text: /Charizard Pidgeot/, count: 0
    assert_not_nil other
  end

  test "index finds a deck through its archetype" do
    @deck.update!(name: "Tuesday List", archetype: archetypes(:ogerpon))

    get decks_path(q: "ogerpon")

    assert_response :success
    assert_select "#decks-grid", text: /Tuesday List/
  end

  test "index ignores a blank q" do
    @deck.update!(name: "Ogerpon Toolbox")

    get decks_path(q: "   ")

    assert_response :success
    assert_select "#decks-grid", text: /Ogerpon Toolbox/
  end

  test "index keeps the query in the search field" do
    get decks_path(q: "ogerpon")

    assert_select "form.deck-filters input[name=q][value=ogerpon]"
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bin/rails test test/controllers/decks_controller_test.rb`
Expected: FAIL — "index filters decks by name" finds both decks, and the last test finds no input.

- [ ] **Step 3: Create the controller concern**

Create `app/controllers/concerns/searchable.rb` with `search_query` only. `search_results` is added
in Task 7, together with the service it calls — a method calling a constant that doesn't exist yet
would be untestable dead code in this task.

```ruby
# Shared reading of the `q` search param. /search, /decks and /tournaments all read the query
# through here so they can't drift on the param name or on trimming.
module Searchable
  extend ActiveSupport::Concern

  private

  # The `q` param, trimmed; "" when absent.
  def search_query
    @search_query ||= params[:q].to_s.strip
  end
end
```

- [ ] **Step 4: Filter in the controller**

`app/controllers/decks_controller.rb` — include the concern at the top of the class:

```ruby
class DecksController < ApplicationController
  include Searchable

  def index
```

Add `q` to `filter_params`:

```ruby
  def filter_params
    {
      q:         search_query.presence,
      format:    params[:format].presence,
      support:   params[:support].presence,
      proxies:   params[:proxies].presence,
      primary:   params[:primary].presence,
      secondary: params[:secondary].presence
    }
  end
```

And apply it as the first clause of `filter_decks`, before the `format` filter:

```ruby
  def filter_decks(scope)
    filters = filter_params

    # Same scope as the dashboard spotlight, so its "See all N decks" link lands on a page
    # showing exactly N decks.
    scope = scope.merge(Deck.search(filters[:q])) if filters[:q]

    scope = scope.where(format: filters[:format]) if Deck.formats.key?(filters[:format])
```

- [ ] **Step 5: Add the input to the filter bar**

`app/views/components/decks/index_view.rb` — add the search input as the first control in
`filter_bar`, and add a `search_input` private method next to `filter_select`:

```ruby
    def filter_bar
      form(action: decks_path, method: "get", class: "deck-filters", data: { controller: "card-filter" }) do
        search_input
        filter_select(:format, format_options)
        filter_select(:primary, primary_options) if @primary_options.any?
        filter_select(:secondary, secondary_options) if @secondary_options.any?
        filter_select(:support, SUPPORT_OPTIONS)
        filter_select(:proxies, PROXY_OPTIONS)
        link_to "Clear", decks_path, class: "btn btn-secondary btn-sm" if active_filters?
      end
    end

    def search_input
      input(
        type: "search",
        name: "q",
        value: @filters[:q],
        placeholder: "Deck or archetype name…",
        class: "form-input deck-filter-search",
        autocomplete: "off",
        aria_label: "Search decks",
        data: { action: "input->card-filter#debounce" }
      )
    end
```

`card_filter_controller.js` already debounces `input` and submits the form — nothing new in JS.

- [ ] **Step 6: Confirm the "Clear" link reacts to the query**

`active_filters?` (`app/views/components/decks/index_view.rb:105-107`) reads
`@filters.values.any?(&:present?)`, and `:q` is now one of those values, so the "Clear" link
already appears for a search-only filter. **No change needed** — just confirm the method still
reads that way, and don't add a redundant `:q` check.

- [ ] **Step 7: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/decks_controller_test.rb`
Expected: PASS.

- [ ] **Step 8: Add the CSS for the input**

Append to `app/assets/stylesheets/application.css`, next to the existing `.deck-filter-select`
rule (find it with `grep -n "deck-filter-select" app/assets/stylesheets/application.css`):

```css
.deck-filter-search {
  flex: 1 1 14rem;
  min-width: 10rem;
}
```

- [ ] **Step 9: Lint and commit**

```bash
bin/rubocop app/controllers app/views/components/decks/index_view.rb
git add app/controllers/concerns/searchable.rb app/controllers/decks_controller.rb \
        app/views/components/decks/index_view.rb app/assets/stylesheets/application.css \
        test/controllers/decks_controller_test.rb
git commit -m "feat: filter the decks index by name or archetype"
```

---

## Task 6: `q` filter on the tournaments index

**Files:**
- Modify: `app/controllers/tournaments_controller.rb:5-7` (`index`),
  `app/views/components/tournaments/index_view.rb`
- Test: `test/controllers/tournaments_controller_test.rb`

**Interfaces:**
- Consumes: `Searchable#search_query` (Task 5), `Tournament.name_matching` (Task 2).
- Produces: `GET /tournaments?q=` filtering by name. `Tournaments::IndexView` gains a required
  keyword argument `query:` — every caller is `app/views/tournaments/index.html.erb`.

- [ ] **Step 1: Write the failing tests**

Append to `test/controllers/tournaments_controller_test.rb`, inside the class:

```ruby
  test "index filters tournaments by name" do
    @user.tournaments.create!(deck: @deck, name: "League Cup Lyon", date: Date.new(2026, 5, 1),
                              format: "standard", tier: "league_cup")

    get tournaments_path(q: "lyon")

    assert_response :success
    assert_select ".data-table-row", count: 1
    assert_select ".data-table-row", text: /League Cup Lyon/
  end

  test "index ignores a blank q" do
    get tournaments_path(q: "   ")

    assert_response :success
    assert_select ".data-table-row", count: 1
  end

  test "index keeps the query in the search field" do
    get tournaments_path(q: "lyon")

    assert_select "form.tournaments-search input[name=q][value=lyon]"
  end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bin/rails test test/controllers/tournaments_controller_test.rb`
Expected: FAIL — the first test sees 2 rows, the last finds no form.

- [ ] **Step 3: Filter in the controller**

`app/controllers/tournaments_controller.rb`:

```ruby
class TournamentsController < ApplicationController
  include Searchable

  before_action :set_tournament, only: %i[show edit update destroy]
  before_action :set_form_collections, only: %i[new create edit update]

  def index
    @query = search_query
    @tournaments = current_user.tournaments.includes(:deck, :tournament_profile).order(date: :desc)
    @tournaments = @tournaments.name_matching(@query) if @query.present?
  end
```

- [ ] **Step 4: Add the form to the view**

`app/views/components/tournaments/index_view.rb` — take `query:`, render a search form between the
page header and the table, and adapt the empty message:

```ruby
module Tournaments
  class IndexView < ApplicationComponent
    def initialize(tournaments:, query: "")
      @tournaments = tournaments
      @query = query
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "Tournaments") do
          link_to "New Tournament", new_tournament_path, class: "btn btn-primary"
        end

        search_form

        if @tournaments.any?
          render Ui::DataTable.new(columns: %w[Name Date Tier Deck Placement CP Actions]) do |t|
            @tournaments.each do |tournament|
              t.row do
                t.cell { link_to tournament.name, tournament_path(tournament) }
                t.cell { localize(tournament.date, format: :long) }
                t.cell { tournament.tier_label }
                t.cell { tournament.deck.name }
                t.cell { placement_label(tournament) }
                t.cell { tournament.championship_points || "—" }
                t.cell do
                  render Ui::AdminActions.new(
                    edit_path: edit_tournament_path(tournament),
                    delete_path: tournament_path(tournament),
                    confirm_message: "Delete #{tournament.name}?"
                  )
                end
              end
            end
          end
        else
          p { @query.present? ? "No tournaments match this search." : "No tournaments yet." }
        end
      end
    end

    private

    def search_form
      form(action: tournaments_path, method: "get", class: "tournaments-search", data: { controller: "card-filter" }) do
        input(
          type: "search",
          name: "q",
          value: @query,
          placeholder: "Tournament name…",
          class: "form-input",
          autocomplete: "off",
          aria_label: "Search tournaments",
          data: { action: "input->card-filter#debounce" }
        )
      end
    end
```

Keep the existing `placement_label` private method exactly as it is.

- [ ] **Step 5: Pass the query from the ERB wrapper**

`app/views/tournaments/index.html.erb`:

```erb
<%= render Tournaments::IndexView.new(tournaments: @tournaments, query: @query) %>
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/controllers/tournaments_controller_test.rb`
Expected: PASS, including the two pre-existing index tests ("lists the current user's
tournaments", "does not list another user's tournaments").

- [ ] **Step 7: Add the CSS**

Append to `app/assets/stylesheets/application.css`:

```css
.tournaments-search {
  margin-bottom: 1rem;
}

.tournaments-search .form-input {
  max-width: 22rem;
}
```

- [ ] **Step 8: Lint and commit**

```bash
bin/rubocop app/controllers/tournaments_controller.rb app/views/components/tournaments/index_view.rb
git add app/controllers/tournaments_controller.rb app/views/components/tournaments/index_view.rb \
        app/views/tournaments/index.html.erb app/assets/stylesheets/application.css \
        test/controllers/tournaments_controller_test.rb
git commit -m "feat: filter the tournaments index by name"
```

---

## Task 7: `Search::Global` service

**Files:**
- Create: `app/services/search/global.rb`
- Create: `test/services/search/global_test.rb`
- Modify: `app/controllers/concerns/searchable.rb` (add `search_results`)

**Interfaces:**
- Consumes: `Deck.search` (Task 4), `Tournament.name_matching` (Task 2),
  `CardSearchable#apply_card_name_filter` (existing, `app/controllers/concerns/card_searchable.rb`).
- Produces:
  - `Search::Global::MIN_QUERY_LENGTH = 2`, `Search::Global::DEFAULT_LIMIT = 5`.
  - `Search::Global.call(user:, query:, limit: DEFAULT_LIMIT) → Search::Global::Result`.
  - `Result` members: `query` (String), `decks` (Array<Deck>), `deck_total` (Integer), `cards`
    (Array<Card>), `card_total` (Integer), `tournaments` (Array<Tournament>), `tournament_total`
    (Integer); predicates `blank?` (query shorter than `MIN_QUERY_LENGTH`) and `any?` (at least
    one match anywhere).
  - `Searchable#search_results(limit: Search::Global::DEFAULT_LIMIT) → Result`.

- [ ] **Step 1: Write the failing test**

Create `test/services/search/global_test.rb`:

```ruby
require "test_helper"

class Search::GlobalTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Ogerpon Toolbox")
  end

  test "returns a blank result for a query shorter than the minimum" do
    [ "", "   ", "o" ].each do |query|
      result = Search::Global.call(user: @user, query: query)

      assert_predicate result, :blank?, "#{query.inspect} must not search"
      assert_empty result.decks
      assert_empty result.cards
      assert_empty result.tournaments
      assert_equal 0, result.deck_total
    end
  end

  test "groups matches by type" do
    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_not_predicate result, :blank?
    assert_predicate result, :any?
    assert_includes result.decks, @deck
    assert_includes result.cards, cards(:teal_mask_ogerpon_ex)
    assert_empty result.tournaments
  end

  test "reports no matches for a query that hits nothing" do
    result = Search::Global.call(user: @user, query: "zzzznothing")

    assert_not_predicate result, :blank?
    assert_not_predicate result, :any?
  end

  test "caps each group and still reports the full total" do
    7.times { |i| @user.decks.create!(name: "Ogerpon Build #{i}") }

    result = Search::Global.call(user: @user, query: "ogerpon", limit: 5)

    assert_equal 5, result.decks.size
    assert_equal 8, result.deck_total, "7 new decks plus the one from setup"
  end

  test "finds a deck through its archetype" do
    @deck.update!(name: "Tuesday List", archetype: archetypes(:ogerpon))

    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_includes result.decks, @deck
  end

  test "excludes another user's decks and tournaments" do
    decks(:two).update!(user: users(:two), name: "Ogerpon Toolbox")
    users(:two).tournaments.create!(deck: decks(:two), name: "Ogerpon Open",
                                    date: Date.new(2026, 4, 1), format: "standard", tier: "league_cup")

    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_not_includes result.decks, decks(:two)
    assert_empty result.tournaments
  end

  test "searches the whole card catalog, not just the user's collection" do
    card = cards(:teal_mask_ogerpon_ex)

    assert_empty @user.collections.where(card: card), "sanity: the user does not own this card"
    assert_includes Search::Global.call(user: @user, query: "ogerpon").cards, card
  end

  test "matches the user's own tournaments by name" do
    tournament = @user.tournaments.create!(deck: @deck, name: "Ogerpon Open",
                                           date: Date.new(2026, 4, 1), format: "standard", tier: "league_cup")

    result = Search::Global.call(user: @user, query: "ogerpon")

    assert_includes result.tournaments, tournament
    assert_equal 1, result.tournament_total
  end

  # Cards go through the same matcher as /cards?q=, so a set code and number narrow the query
  # there too and the "see all" count stays honest.
  test "narrows cards by set code and number like the cards page does" do
    card = cards(:teal_mask_ogerpon_ex)
    result = Search::Global.call(user: @user, query: "Ogerpon #{card.set_name} #{card.set_number}")

    assert_equal [ card ], result.cards
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/services/search/global_test.rb`
Expected: FAIL with `NameError: uninitialized constant Search`.

- [ ] **Step 3: Write the service**

Create `app/services/search/global.rb`:

```ruby
module Search
  # One text query, three groups of matches: the user's decks, the whole card catalog, and the
  # user's tournaments. Read-only, so no serialized_transaction.
  class Global < ApplicationService
    # CardSearchable lives under app/controllers/concerns but is a plain module with no controller
    # dependency. Including it here is deliberate: cards must match exactly as they do on the
    # cards page (set code and number included), so the "see all N cards" count is the count that
    # page will show.
    include CardSearchable

    MIN_QUERY_LENGTH = 2
    DEFAULT_LIMIT = 5

    Result = Data.define(
      :query, :decks, :deck_total, :cards, :card_total, :tournaments, :tournament_total
    ) do
      # True when the query was too short to run — the caller renders nothing at all, as opposed
      # to "searched and found nothing".
      def blank?
        query.length < MIN_QUERY_LENGTH
      end

      def any?
        total.positive?
      end

      def total
        deck_total + card_total + tournament_total
      end
    end

    def initialize(user:, query:, limit: DEFAULT_LIMIT)
      @user = user
      @query = query.to_s.strip
      @limit = limit
    end

    def call
      return empty_result if @query.length < MIN_QUERY_LENGTH

      Result.new(
        query: @query,
        decks: deck_scope.order(:name).limit(@limit).includes(:archetype).to_a,
        deck_total: deck_scope.count,
        cards: card_scope.order(:name, :set_name).limit(@limit).to_a,
        card_total: card_scope.count,
        tournaments: tournament_scope.order(date: :desc).limit(@limit).to_a,
        tournament_total: tournament_scope.count
      )
    end

    private

    # Below the minimum, nothing touches the database — this is what keeps a one-letter query
    # cheap.
    def empty_result
      Result.new(
        query: @query, decks: [], deck_total: 0, cards: [], card_total: 0,
        tournaments: [], tournament_total: 0
      )
    end

    # `search` is applied before any `includes`: it uses #or, which refuses to merge relations
    # that don't carry the same includes.
    def deck_scope
      @deck_scope ||= @user.decks.search(@query)
    end

    def card_scope
      @card_scope ||= apply_card_name_filter(Card.all, @query)
    end

    def tournament_scope
      @tournament_scope ||= @user.tournaments.name_matching(@query)
    end
  end
end
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bin/rails test test/services/search/global_test.rb`
Expected: PASS.

If `blank?` raises `NameError: uninitialized constant Search::Global::Result::MIN_QUERY_LENGTH`,
qualify it as `Global::MIN_QUERY_LENGTH` inside the `Data.define` block — the block's lexical scope
is the block, not the enclosing class.

- [ ] **Step 5: Add `search_results` to the controller concern**

Append to the private section of `app/controllers/concerns/searchable.rb`:

```ruby
  # Grouped decks/cards/tournaments matches for the current user. The short-query cut-off is the
  # service's (Search::Global::MIN_QUERY_LENGTH), so the index pages above can filter from the
  # first character while the spotlight waits for two.
  def search_results(limit: Search::Global::DEFAULT_LIMIT)
    Search::Global.call(user: current_user, query: search_query, limit: limit)
  end
```

- [ ] **Step 6: Verify nothing else broke**

Run: `bin/rails test test/services test/models`
Expected: PASS.

- [ ] **Step 7: Lint and commit**

```bash
bin/rubocop app/services/search/global.rb app/controllers/concerns/searchable.rb test/services/search/global_test.rb
git add app/services/search/global.rb app/controllers/concerns/searchable.rb test/services/search/global_test.rb
git commit -m "feat: add Search::Global"
```

---

## Task 8: `/search` endpoint and the results frame

**Files:**
- Create: `app/controllers/search_controller.rb`, `app/views/search/show.html.erb`,
  `app/views/components/search/results_view.rb`, `app/views/components/search/results_list.rb`,
  `app/views/components/search/result_group.rb`, `test/controllers/search_controller_test.rb`
- Modify: `config/routes.rb:18-21` (inside the `authenticate :user` block)

**Interfaces:**
- Consumes: `Searchable` (Tasks 5, 7), `Search::Global::Result` (Task 7).
- Produces:
  - Route `GET /search` → `search#show`, helper `search_path`.
  - `Search::ResultsView::FRAME_ID = "search_results"` — the single definition of the frame id,
    referenced by Task 9's `Search::Spotlight`.
  - `Search::ResultsView.new(results:)` — the turbo frame, wrapping `ResultsList`.
  - `Search::ResultsList.new(results:)` — the listbox and its three groups, with no frame around
    it. Task 9's styleguide section renders **this** one: a second `turbo_frame_tag(FRAME_ID)` on
    the same page would duplicate an element id, which is exactly the bug
    `StyleguideControllerTest` already guards against for the MCP panels.
  - `Search::ResultGroup.new(key:, label:, records:, total:, index_path:, see_all_label:)`,
    yielding each record so the caller renders the row.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/search_controller_test.rb`:

```ruby
require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Ogerpon Toolbox")
    sign_in @user
  end

  test "requires authentication" do
    sign_out @user

    get search_path(q: "ogerpon")

    assert_redirected_to new_user_session_path
  end

  test "renders the frame with a group per matching type" do
    get search_path(q: "ogerpon")

    assert_response :success
    assert_select "turbo-frame#search_results"
    assert_select "[role=group][aria-labelledby=spotlight-group-decks] a[role=option]",
      text: /Ogerpon Toolbox/
    assert_select "[role=group][aria-labelledby=spotlight-group-cards] a[role=option]",
      text: /Teal Mask Ogerpon ex/
  end

  test "renders an empty frame for a query below the minimum length" do
    get search_path(q: "o")

    assert_response :success
    assert_select "turbo-frame#search_results"
    assert_select "a[role=option]", count: 0
    assert_select ".spotlight-empty", count: 0, msg: "a too-short query says nothing at all"
  end

  test "says so when the query matches nothing" do
    get search_path(q: "zzzznothing")

    assert_response :success
    assert_select ".spotlight-empty"
    assert_select "a[role=option]", count: 0
  end

  test "result links leave the frame" do
    get search_path(q: "ogerpon")

    assert_select "a[role=option][data-turbo-frame=_top]"
  end

  test "each group links to its index pre-filtered with the query" do
    get search_path(q: "ogerpon")

    assert_select "a.spotlight-see-all[href=?]", decks_path(q: "ogerpon")
    assert_select "a.spotlight-see-all[href=?]", cards_path(q: "ogerpon")
  end

  test "the group header reports the total when the cap truncated it" do
    7.times { |i| @user.decks.create!(name: "Ogerpon Build #{i}") }

    get search_path(q: "ogerpon")

    assert_select "#spotlight-group-decks", text: /5 of 8/
  end

  test "does not render an empty group" do
    get search_path(q: "ogerpon")

    assert_select "#spotlight-group-tournaments", count: 0
  end

  # layout false: the response is the frame and nothing else. Don't assert on <html> — Nokogiri
  # adds html/body wrappers when parsing a fragment, so that assertion would fail even when the
  # layout is correctly skipped.
  test "renders without the application layout" do
    get search_path(q: "ogerpon")

    assert_select "nav.navbar", count: 0
    assert_select "form.spotlight-form", count: 0, msg: "the frame must not carry the input the user is typing in"
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/controllers/search_controller_test.rb`
Expected: FAIL with `NameError: undefined local variable or method 'search_path'`.

- [ ] **Step 3: Add the route**

`config/routes.rb`, inside the `authenticate :user do` block, right after the dashboard line:

```ruby
    get "dashboard", to: "home#dashboard"
    get "search", to: "search#show"
```

- [ ] **Step 4: Write the controller and its wrapper**

Create `app/controllers/search_controller.rb`:

```ruby
# Dashboard spotlight search. Answers a Turbo Frame request on every keystroke, so the response
# carries the frame and nothing else — no layout, no navbar.
class SearchController < ApplicationController
  include Searchable

  layout false

  def show
    @results = search_results
  end
end
```

Create `app/views/search/show.html.erb`:

```erb
<%= render Search::ResultsView.new(results: @results) %>
```

- [ ] **Step 5: Write the group component**

Create `app/views/components/search/result_group.rb`:

```ruby
module Search
  # One group of spotlight results: its header, its rows (rendered by the caller's block, since
  # each type has its own path and metadata) and the link to that type's index, pre-filtered.
  class ResultGroup < ApplicationComponent
    def initialize(key:, label:, records:, total:, index_path:, see_all_label:)
      @key = key
      @label = label
      @records = records
      @total = total
      @index_path = index_path
      @see_all_label = see_all_label
    end

    def view_template(&row)
      return if @records.empty?

      div(role: "group", aria_labelledby: header_id, class: "spotlight-group") do
        div(class: "spotlight-group-header", id: header_id) { header_text }
        @records.each { |record| row.call(record) }
        link_to @see_all_label, @index_path, class: "spotlight-see-all", data: { turbo_frame: "_top" }
      end
    end

    private

    def header_id
      "spotlight-group-#{@key}"
    end

    # "DECKS · 3" when everything fits, "DECKS · 5 of 12" when the cap truncated it.
    def header_text
      count = @records.size < @total ? "#{@records.size} of #{@total}" : @total.to_s
      "#{@label} · #{count}"
    end
  end
end
```

- [ ] **Step 6: Write the results view and the list it wraps**

Create `app/views/components/search/results_view.rb` — the frame, and nothing else:

```ruby
module Search
  # The spotlight's Turbo Frame. Split from the list it wraps so the list can also be rendered
  # outside a frame (the styleguide), without a second element carrying FRAME_ID.
  class ResultsView < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "search_results".freeze

    def initialize(results:)
      @results = results
    end

    def view_template
      turbo_frame_tag(FRAME_ID) do
        render ResultsList.new(results: @results)
      end
    end
  end
end
```

Create `app/views/components/search/results_list.rb`:

```ruby
module Search
  # Three groups of options, a "no matches" line, or — when the query was too short to search —
  # nothing at all.
  class ResultsList < ApplicationComponent
    def initialize(results:)
      @results = results
    end

    def view_template
      if @results.blank?
        # Nothing: the query is too short to have searched.
      elsif @results.any?
        div(class: "spotlight-listbox", role: "listbox", aria_label: "Search results") do
          deck_group
          card_group
          tournament_group
        end
      else
        p(class: "spotlight-empty") { "No matches." }
      end
    end

    private

    def query
      @results.query
    end

    def deck_group
      render ResultGroup.new(
        key: "decks", label: "DECKS", records: @results.decks, total: @results.deck_total,
        index_path: decks_path(q: query), see_all_label: "See all #{@results.deck_total} decks"
      ) do |deck|
        option_row(
          dom_id: "spotlight-option-deck-#{deck.id}",
          path: deck_path(deck),
          name: deck.name,
          meta: [ deck.format_label, deck.archetype&.name ].compact.join(" · ")
        )
      end
    end

    def card_group
      render ResultGroup.new(
        key: "cards", label: "CARDS", records: @results.cards, total: @results.card_total,
        index_path: cards_path(q: query), see_all_label: "See all #{@results.card_total} cards"
      ) do |card|
        option_row(
          dom_id: "spotlight-option-card-#{card.id}",
          path: card_path(card),
          name: card.name,
          meta: "#{card.set_name} ##{card.set_number}"
        )
      end
    end

    def tournament_group
      render ResultGroup.new(
        key: "tournaments", label: "TOURNAMENTS", records: @results.tournaments,
        total: @results.tournament_total, index_path: tournaments_path(q: query),
        see_all_label: "See all #{@results.tournament_total} tournaments"
      ) do |tournament|
        option_row(
          dom_id: "spotlight-option-tournament-#{tournament.id}",
          path: tournament_path(tournament),
          name: tournament.name,
          meta: "#{tournament.date} · #{tournament.tier_label}"
        )
      end
    end

    # data-turbo-frame="_top" so picking a result navigates the whole page instead of replacing
    # the panel with the target page's markup.
    def option_row(dom_id:, path:, name:, meta:)
      a(id: dom_id, href: path, role: "option", class: "spotlight-option", data: { turbo_frame: "_top" }) do
        span(class: "spotlight-option-name") { name }
        span(class: "spotlight-option-meta") { meta }
      end
    end
  end
end
```

- [ ] **Step 7: Run the test to verify it passes**

Run: `bin/rails test test/controllers/search_controller_test.rb`
Expected: PASS.

If the block passed to `ResultGroup` renders nothing, check that `view_template` takes `&row` and
calls `row.call(record)` — a Phlex component only yields what its template explicitly yields.

- [ ] **Step 8: Lint and commit**

```bash
bin/rubocop app/controllers/search_controller.rb app/views/components/search config/routes.rb
git add config/routes.rb app/controllers/search_controller.rb app/views/search \
        app/views/components/search test/controllers/search_controller_test.rb
git commit -m "feat: add the /search turbo frame endpoint"
```

The three components together: `ResultsView` (frame) → `ResultsList` (branching + the three group
calls + `option_row`) → `ResultGroup` (header, yielded rows, "see all" link).

---

## Task 9: the spotlight on the dashboard

**Files:**
- Create: `app/views/components/search/spotlight.rb`,
  `test/controllers/home_controller_test.rb` (none exists yet)
- Modify: `app/views/components/home/dashboard_view.rb:8-20` (`view_template`),
  `app/views/components/styleguide/page_view.rb:36-53` (section list) and its private section
  methods, `test/controllers/styleguide_controller_test.rb`

**Interfaces:**
- Consumes: `Search::ResultsView::FRAME_ID` and `Search::Global::MIN_QUERY_LENGTH`.
- Produces: `Search::Spotlight.new` (no arguments) — the combobox, the `GET /search` form and the
  initially-empty frame, wired to the `dashboard-search` Stimulus controller written in Task 10.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/home_controller_test.rb`:

```ruby
require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "dashboard renders the spotlight search" do
    get dashboard_path

    assert_response :success
    assert_select "form[action=?] input[name=q][role=combobox]", search_path
  end

  test "the spotlight form targets the results frame" do
    get dashboard_path

    assert_select "form[data-turbo-frame=search_results]"
  end

  test "the spotlight ships an empty results frame" do
    get dashboard_path

    assert_select "turbo-frame#search_results"
    assert_select "a[role=option]", count: 0
  end

  test "the combobox points at the frame it controls" do
    get dashboard_path

    assert_select "input[role=combobox][aria-controls=search_results][aria-expanded=false]"
  end

  test "the spotlight passes the service's minimum query length to Stimulus" do
    get dashboard_path

    assert_select "[data-dashboard-search-min-length-value=?]", Search::Global::MIN_QUERY_LENGTH.to_s
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: FAIL — no form on the dashboard.

- [ ] **Step 3: Write the spotlight component**

Create `app/views/components/search/spotlight.rb`:

```ruby
module Search
  # The dashboard's search field: a combobox whose results land in a floating panel below it.
  #
  # The panel is a sibling of the form rather than a child, so the frame Turbo replaces on every
  # keystroke never contains the input the user is typing in.
  class Spotlight < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    def view_template
      div(class: "spotlight", data: spotlight_data) do
        search_form
        div(class: "spotlight-panel", data: { dashboard_search_target: "panel" }) do
          turbo_frame_tag(ResultsView::FRAME_ID)
        end
      end
    end

    private

    def spotlight_data
      {
        controller: "dashboard-search",
        dashboard_search_min_length_value: Global::MIN_QUERY_LENGTH,
        action: "click@document->dashboard-search#clickOutside " \
                "keydown@document->dashboard-search#shortcut"
      }
    end

    # No data-turbo-action="replace": this must not promote the frame navigation to the page URL,
    # or typing on the dashboard would rewrite the address bar to /search?q=…
    def search_form
      form(
        action: search_path,
        method: "get",
        class: "spotlight-form",
        role: "search",
        data: { turbo_frame: ResultsView::FRAME_ID, dashboard_search_target: "form" }
      ) do
        input(
          type: "search",
          name: "q",
          placeholder: "Search decks, cards, tournaments…",
          class: "form-input spotlight-input",
          autocomplete: "off",
          role: "combobox",
          aria_expanded: "false",
          aria_autocomplete: "list",
          aria_controls: ResultsView::FRAME_ID,
          aria_label: "Search decks, cards and tournaments",
          data: {
            dashboard_search_target: "input",
            action: "input->dashboard-search#search " \
                    "keydown.down->dashboard-search#next " \
                    "keydown.up->dashboard-search#previous " \
                    "keydown.enter->dashboard-search#open " \
                    "keydown.esc->dashboard-search#close"
          }
        )
      end
    end
  end
end
```

- [ ] **Step 4: Render it on the dashboard**

`app/views/components/home/dashboard_view.rb` — between the `h1` and the `dashboard-grid` div:

```ruby
    def view_template
      div(class: "dashboard-container", data: { controller: "decks" }) do
        h1 { "Welcome, #{@current_user.email}" }

        render Search::Spotlight.new

        div(class: "dashboard-grid") do
          collection_card
          decks_card
        end

        render Ui::DeckImport.new(pending_imports: @pending_deck_imports)
        scanner_modal
      end
    end
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `bin/rails test test/controllers/home_controller_test.rb`
Expected: PASS.

- [ ] **Step 6: Add the styleguide section**

`app/views/components/styleguide/page_view.rb` — add `spotlight_section` to the list in
`view_template`, after `form_section`:

```ruby
        form_section
        spotlight_section
        deck_card_section
```

And the section itself, next to `form_section` (the panel is shown open and populated with real
components; the frame is not live here):

```ruby
    # Renders the real components with a hand-built Result, so the reference can't drift from the
    # spotlight the dashboard ships. The panel is forced open — on the dashboard, Stimulus opens it.
    #
    # ResultsList, not ResultsView: the latter wraps everything in turbo_frame_tag(FRAME_ID), and
    # Search::Spotlight above already put one of those on this page. Two elements with the same id
    # is the exact bug StyleguideControllerTest guards against for the MCP panels.
    def spotlight_section
      sg_section("Composants", "Recherche spotlight",
              "Champ de recherche du dashboard : panneau flottant, résultats groupés par type.") do
        div(class: "sg-spotlight-demo") do
          render Search::Spotlight.new
          div(class: "spotlight-panel spotlight-panel-open") do
            render Search::ResultsList.new(results: sg_spotlight_results)
          end
        end
      end
    end

    # Plain in-memory records (never persisted), like sg_settings_user_with_token above: this page
    # never touches the database. The ids are what the path helpers need; nothing is saved.
    def sg_spotlight_results
      Search::Global::Result.new(
        query: "ogerpon",
        decks: [
          Deck.new(id: 1, name: "Ogerpon Toolbox", format: "standard",
                   archetype: Archetype.new(name: "Teal Mask Ogerpon ex")),
          Deck.new(id: 2, name: "Tuesday List", format: "glc")
        ],
        deck_total: 4,
        cards: [
          Card.new(id: 1, name: "Teal Mask Ogerpon ex", set_name: "TWM", set_number: "25"),
          Card.new(id: 2, name: "Ogerpon", set_name: "SVI", set_number: "211")
        ],
        card_total: 9,
        tournaments: [
          Tournament.new(id: 1, name: "Ogerpon Open", date: Date.new(2026, 4, 12), tier: "league_cup")
        ],
        tournament_total: 1
      )
    end
```

Add the demo container CSS in the same commit, at the end of
`app/assets/stylesheets/application.css`:

```css
.sg-spotlight-demo {
  position: relative;
  min-height: 4rem;
}
```

- [ ] **Step 7: Verify the styleguide still renders, with unique ids**

Run: `bin/rails test test/controllers/styleguide_controller_test.rb`
Expected: PASS — including "the two MCP token panels carry distinct ids", which counts
`section.settings-section` elements and must be unaffected.

Then add a guard of the same kind for this section, since the page now renders spotlight markup
twice (the component's own empty frame, and the demo panel). Append to
`test/controllers/styleguide_controller_test.rb`:

```ruby
  # The page renders the spotlight input and, separately, an open results panel. Rendering
  # ResultsView for the demo would have put a second turbo-frame#search_results on the page.
  test "the spotlight demo does not duplicate the results frame" do
    get styleguide_path

    assert_response :success
    assert_select "turbo-frame#search_results", count: 1
    ids = css_select("[role=option]").map { |option| option["id"] }

    assert_equal ids.uniq, ids, "duplicate option ids: #{ids.inspect}"
  end
```

The demo records are in-memory, so the section renders identically whatever the database holds —
and, as with the MCP panels above, `/styleguide` still never reads it.

- [ ] **Step 8: Lint and commit**

```bash
bin/rubocop app/views/components
git add app/views/components/search/spotlight.rb app/views/components/home/dashboard_view.rb \
        app/views/components/styleguide/page_view.rb app/assets/stylesheets/application.css \
        test/controllers/home_controller_test.rb
git commit -m "feat: put the spotlight search on the dashboard"
```

---

## Task 10: Stimulus controller and panel CSS

**Files:**
- Create: `app/javascript/controllers/dashboard_search_controller.js`
- Modify: `app/assets/stylesheets/application.css` (a `.spotlight-*` block, plus one rule in the
  existing mobile media query near `.card-search-results { width: 100% }`)

**Interfaces:**
- Consumes: the DOM contract from Task 9 — targets `input`, `form`, `panel`; value
  `min-length`; and the options rendered by Task 8 (`a[role=option]` with unique ids).
- Produces: no Ruby interface. Registered automatically —
  `app/javascript/controllers/index.js` eager-loads every `*_controller.js`, so the file name
  `dashboard_search_controller.js` is the registration.

- [ ] **Step 1: Write the controller**

Create `app/javascript/controllers/dashboard_search_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Dashboard spotlight search: debounces the query into a Turbo Frame and makes the resulting
// options keyboard-navigable. The options live inside the frame, so they are re-collected on
// every frame load rather than cached at connect.
export default class extends Controller {
  static targets = ["input", "form", "panel"]
  static values = { delay: { type: Number, default: 300 }, minLength: { type: Number, default: 2 } }

  connect() {
    this.options = []
    this.activeIndex = -1
    this.element.addEventListener("turbo:frame-load", this.#frameLoaded)
  }

  disconnect() {
    clearTimeout(this.timeout)
    this.element.removeEventListener("turbo:frame-load", this.#frameLoaded)
  }

  search() {
    clearTimeout(this.timeout)

    if (this.inputTarget.value.trim().length < this.minLengthValue) {
      this.#clear()
      return
    }

    this.timeout = setTimeout(() => this.formTarget.requestSubmit(), this.delayValue)
  }

  next(event) {
    if (this.options.length === 0) return

    event.preventDefault()
    this.#activate((this.activeIndex + 1) % this.options.length)
  }

  previous(event) {
    if (this.options.length === 0) return

    event.preventDefault()
    this.#activate((this.activeIndex - 1 + this.options.length) % this.options.length)
  }

  // Enter opens the highlighted option. With nothing highlighted it falls through, so the form
  // submits and the panel just refreshes.
  open(event) {
    const option = this.options[this.activeIndex]
    if (!option) return

    event.preventDefault()
    option.click()
  }

  close(event) {
    if (event) event.preventDefault()

    this.inputTarget.value = ""
    this.#clear()
  }

  clickOutside(event) {
    if (this.element.contains(event.target)) return

    this.#collapse()
  }

  // ⌘K / Ctrl+K / "/" focus the field. Stimulus key filters can't express modifiers, so both
  // shortcuts share one handler.
  shortcut(event) {
    const isSlash = event.key === "/"
    const isCommandK = event.key === "k" && (event.metaKey || event.ctrlKey)
    if (!isSlash && !isCommandK) return
    if (isSlash && this.#isTyping(event.target)) return

    event.preventDefault()
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  #frameLoaded = () => {
    this.options = Array.from(this.panelTarget.querySelectorAll("[role=option]"))
    this.activeIndex = -1
    this.#setExpanded(this.panelTarget.textContent.trim().length > 0)
  }

  #activate(index) {
    this.options.forEach((option) => option.classList.remove("is-active"))
    this.activeIndex = index

    const option = this.options[index]
    option.classList.add("is-active")
    option.scrollIntoView({ block: "nearest" })
    this.inputTarget.setAttribute("aria-activedescendant", option.id)
  }

  #clear() {
    const frame = this.panelTarget.querySelector("turbo-frame")
    if (frame) frame.innerHTML = ""

    this.#collapse()
  }

  #collapse() {
    this.options = []
    this.activeIndex = -1
    this.#setExpanded(false)
  }

  #setExpanded(expanded) {
    this.panelTarget.classList.toggle("spotlight-panel-open", expanded)
    this.inputTarget.setAttribute("aria-expanded", expanded ? "true" : "false")
    if (!expanded) this.inputTarget.removeAttribute("aria-activedescendant")
  }

  #isTyping(target) {
    return target.matches("input, textarea, select, [contenteditable=true]")
  }
}
```

- [ ] **Step 2: Write the panel CSS**

Append to `app/assets/stylesheets/application.css` (tokens only — no literal colours):

```css
/* Dashboard spotlight search */
.spotlight {
  position: relative;
  margin-top: 1.5rem;
}

.spotlight-input {
  width: 100%;
}

.spotlight-panel {
  display: none;
  position: absolute;
  top: 100%;
  left: 0;
  right: 0;
  max-height: 60vh;
  overflow-y: auto;
  background: var(--surface);
  border-radius: 0 0 8px 8px;
  box-shadow: var(--e2);
  z-index: 50;
}

.spotlight-panel-open {
  display: block;
}

.spotlight-group + .spotlight-group {
  border-top: 1px solid var(--line);
}

.spotlight-group-header {
  padding: 0.5rem 0.75rem 0.25rem;
  font-family: var(--font-display);
  font-size: 0.75rem;
  letter-spacing: 0.08em;
  color: var(--ink-500);
}

.spotlight-option {
  display: flex;
  justify-content: space-between;
  gap: 1rem;
  padding: 0.5rem 0.75rem;
  color: var(--ink-900);
  text-decoration: none;
}

.spotlight-option:hover,
.spotlight-option.is-active {
  background: var(--flare);
  color: var(--paper);
}

.spotlight-option-meta {
  color: var(--ink-500);
  font-size: 0.875rem;
  white-space: nowrap;
}

.spotlight-option:hover .spotlight-option-meta,
.spotlight-option.is-active .spotlight-option-meta {
  color: var(--paper);
}

.spotlight-see-all {
  display: block;
  padding: 0.5rem 0.75rem;
  font-size: 0.875rem;
}

.spotlight-empty {
  padding: 0.75rem;
  color: var(--ink-500);
}
```

Every token used above is defined at the top of the file (`--ink-900`/`--ink-500` line 54,
`--line`/`--paper`/`--surface` line 55, `--flare` line 58, `--e2` line 81, `--font-display`
line 85). Confirm with:

Run: `grep -nE "^\s+--(surface|line|ink-500|ink-900|paper|flare|e2|font-display):" app/assets/stylesheets/application.css`
Expected: all eight appear. There is no `--font-ui` in this design system — the display face
(Archivo) is the one used for small uppercase labels.

- [ ] **Step 3: Add the mobile rule**

In the mobile media query, next to the existing `.card-search-results { width: 100%; }` rule
(find it with `grep -n "card-search-results" app/assets/stylesheets/application.css`):

```css
  .spotlight-option {
    flex-direction: column;
    gap: 0.125rem;
  }

  .spotlight-option-meta {
    white-space: normal;
  }
```

- [ ] **Step 4: Verify the JS audit and the suite**

```bash
bin/importmap audit
bin/rails test
```
Expected: no vulnerabilities; all tests pass.

- [ ] **Step 5: Commit**

```bash
bin/rubocop
git add app/javascript/controllers/dashboard_search_controller.js app/assets/stylesheets/application.css
git commit -m "feat: keyboard-navigable spotlight panel"
```

---

## Task 11: Full verification and manual check

**Files:** none (verification only, plus fixes for anything it turns up).

**Interfaces:** none.

- [ ] **Step 1: Run every CI check**

```bash
bin/rubocop
bin/brakeman --no-pager
bin/importmap audit
bin/rails db:test:prepare test
```
Expected: all four clean. Brakeman deserves attention here: this feature builds SQL strings. The
`LIKE ? ESCAPE '\'` fragments interpolate only `table_name` (a constant from the schema) and pass
the query as a bind parameter, so there should be no new warning. If Brakeman flags the
`#{table_name}` interpolation in `NameNormalizable`, do not silence it with a comment — switch the
fragment to `arel_table[:name_normalized]` and re-run.

- [ ] **Step 2: Start the app**

Run: `bin/dev`
Then open `http://localhost:3000/dashboard` signed in as a user with decks, cards and tournaments.

- [ ] **Step 3: Manually verify the behaviours no test covers**

Walk the list and note the result of each:

1. Type one character → no panel, no request in the server log.
2. Type `gar` → panel opens after ~300 ms with grouped results; the dashboard cards below do not
   move.
3. `↓` `↓` `↑` → highlight moves and wraps at both ends; the highlighted row scrolls into view.
4. `Enter` on a highlighted row → navigates to that record (full page, not inside the panel).
5. `Escape` → field cleared, panel closed.
6. Click outside the panel → panel closes, field keeps its text.
7. `/` with the field unfocused → focuses the field; `/` **inside** the field types a slash.
8. `⌘K` → focuses and selects the field.
9. A group's "See all N …" link → lands on that index, filtered, showing N records.
10. The browser address bar still reads `/dashboard` after typing (no promotion to `/search?q=…`).
11. `/styleguide` renders the new "Recherche spotlight" section.

- [ ] **Step 4: Fix anything that failed, then re-run the suite**

For each failure, write a test first if the behaviour is testable without Capybara (controller or
service level); keyboard-only behaviour is fixed against the manual walkthrough. Re-run:

```bash
bin/rails test
bin/rubocop
```

- [ ] **Step 5: Commit any fixes and push**

```bash
git add -A
git commit -m "fix: spotlight search polish from manual verification"
git push -u origin feature/86-dashboard-search
```

- [ ] **Step 6: Request review**

Use the `superpowers:requesting-code-review` skill. Then open the PR with
`gh pr create`, referencing `Closes #86` and the spec path in the body.

---

## Verification Checklist

Each item maps to the spec section it proves:

- [ ] `NameNormalizable` is the only place the `LIKE`/`ESCAPE`/`sanitize_sql_like` rules are
      written for single-column name matching (Task 1) — `Archetype.search` reuses its
      `normalize_for_match` for the three-column case (Task 3).
- [ ] `decks`, `tournaments`, `archetypes` all carry `name_normalized`, backfilled in Ruby, with no
      index (Task 2).
- [ ] All four fixture files spell `name_normalized` out, each guarded by a test (Tasks 2, 3).
- [ ] `Deck.search` matches name or archetype, once per deck, chainable off `user.decks` (Task 4).
- [ ] The decks and tournaments indexes filter on `q` with the same scopes the spotlight uses
      (Tasks 5, 6).
- [ ] `Search::Global` caps at 5, reports true totals, scopes decks/tournaments to the user,
      searches the whole card catalog, and issues zero queries below 2 characters (Task 7).
- [ ] `Searchable` owns the `q` param and every `Search::Global` call (Tasks 5, 7).
- [ ] `/search` answers frame-only, groups results, hides empty groups, says "No matches" only
      when it actually searched (Task 8).
- [ ] Result links and "see all" links carry `data-turbo-frame="_top"` (Task 8).
- [ ] The dashboard renders the combobox with `aria-controls`/`aria-expanded` and an empty frame,
      and passes `MIN_QUERY_LENGTH` down to Stimulus (Task 9).
- [ ] `/styleguide` documents the component (Task 9).
- [ ] Keyboard: `↑`/`↓` with wrap-around, `Enter`, `Escape`, `⌘K`, `/`; click-outside; no URL
      promotion (Tasks 10, 11).
- [ ] CSS uses only design-system tokens and the panel goes full-width on mobile (Task 10).
- [ ] `bin/rubocop`, `bin/brakeman --no-pager`, `bin/importmap audit`, `bin/rails test` all clean
      (Task 11).
