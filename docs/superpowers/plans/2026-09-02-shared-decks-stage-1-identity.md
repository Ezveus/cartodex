# Shared Decks — Stage 1: a deck is addressed by its key

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deck is addressed by an unguessable 22-character `key` instead of its numeric id, on every route, in every JSON payload, and in every MCP tool argument — with no user-visible change to what the app does.

**Architecture:** `decks.key` is a `NOT NULL`, UNIQUE string assigned by a `before_validation` callback. `Deck#to_param` returns it, so all 35 path-helper call sites change what they emit without being edited. The 13 lookups that read `params[:id]` switch to `find_by!(key:)` **inside their existing ownership scope** — the key replaces the id, the ownership guarantee does not move. Two more identifiers travel in URLs without being lookups (`/decks/compare?ids[]=`) or without `to_param`'s help (`deck_path(d[:id])` in the over-allocation report), and both are edited by hand.

**Tech Stack:** Ruby 3.4.1, Rails 8.1, SQLite (all environments), Minitest with parallel execution, Phlex views, Hotwire (Turbo + Stimulus), the `mcp` gem.

**Spec:** `docs/superpowers/specs/2026-09-02-shared-decks-design.md` — read "Data model", "The identity rule", "Where the unscoped lookup lives", "Blast radius", "API and MCP".

**Stage 2** (`shared` flag, Pundit, the public surfaces) builds on this and is a separate plan. This stage ships on its own: after Task 4 the app behaves exactly as before, addressed differently.

## Global Constraints

- **All views are Phlex components.** Never write ERB view logic. See the `phlex-architecture` skill.
- **Code and code comments in English.**
- `bin/rubocop` (rubocop-rails-omakase) must pass before every commit.
- `bin/rails test` must be green before every commit.
- System tests must pass at **both** viewports: `bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`. Never click a nav link directly — use `click_nav_link`.
- **A task whose diff touches a model callback, a route, or shared test setup runs `bin/rails test:system` (desktop side) before committing, not just `bin/rails test`.** `bin/rails test` does not run `test/system/`, and the system suite creates its own decks and drives the deck page's JavaScript. This stage changes both the URL of every deck and the Stimulus values the deck page reads, so a green unit suite proves very little here.
- **Sabotage-verify every new test**: before implementing, run the test and see it fail for the stated reason. After implementing, break the implementation once and confirm the test goes red. A test that has never been red proves nothing.
- Fixtures are inserted **without validations or callbacks**. `decks.yml` must therefore spell out a literal `key`, exactly as it already spells out `name_normalized`.
- `app/mcp/` is an autoloaded root, so its classes are **top-level constants** (`ListDecksTool`, not `Mcp::ListDecksTool`).
- **`decks.id` stays the primary key and the target of every foreign key.** Only *addresses* become keys. A `<select>` of decks (the tournament form, the reallocation form) and internal form params (`from_deck_id`, `to_deck_id`) keep carrying the integer.
- The worktree needs `config/master.key` copied from the main checkout and `mise trust` run before `bundle` will work.

---

## Task 1: `decks.key`, and `to_param` returns it

This is the task that makes the other three visible. The moment `to_param` changes, all 35 path helpers emit keys while every lookup still reads ids, so most of the suite goes red — that is the intended signal, and Task 2 turns it green again.

**Tasks 1 and 2 land in one commit**, at the end of Task 2. This task has no commit step of its own: the suite is red between the two, the global constraint says green before every commit, and CI runs on every push. Splitting them would produce a commit that fails CI and that `git bisect` cannot land on. The two tasks stay separate here because they are reviewed separately — the column and the callback on one side, the thirteen lookups on the other.

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_key_to_decks.rb`
- Modify: `app/models/deck.rb`
- Modify: `db/schema.rb` (written by the migration — commit it)
- Modify: `test/fixtures/decks.yml`
- Test: `test/models/deck_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `Deck#key` (String, 22 URL-safe chars, never nil), `Deck#to_param` returning it, and `Deck::KEY_BYTES = 16`. Every `*_deck_path` / `*_deck_url` helper now emits `/decks/<key>`.

- [ ] **Step 1: Write the failing model tests**

Append to `test/models/deck_test.rb`:

```ruby
  test "a new deck is assigned a url-safe key" do
    deck = users(:one).decks.create!(name: "Keyed", standard_pool: standard_pools(:twm_por))

    assert_match(/\A[A-Za-z0-9_-]{22}\z/, deck.key)
  end

  test "saving a deck again does not rewrite its key" do
    deck = decks(:one)
    original = deck.key

    deck.update!(name: "Renamed")

    assert_equal original, deck.reload.key
  end

  test "a blank key is filled in rather than rejected" do
    deck = decks(:one)
    deck.key = ""

    # before_validation and the presence validation have to agree: with before_create
    # this record would be invalid while `save` succeeded.
    assert_predicate deck, :valid?
    assert_predicate deck.key, :present?
  end

  test "to_param is the key, so no deck path carries a numeric id" do
    deck = decks(:one)

    assert_equal deck.key, deck.to_param
    assert_equal "/decks/#{deck.key}", Rails.application.routes.url_helpers.deck_path(deck)
  end

  test "two decks cannot share a key" do
    # The guarantee is the UNIQUE index, not a uniqueness validation, so the write has
    # to bypass the model to be tested at all.
    assert_raises ActiveRecord::RecordNotUnique do
      Deck.where(id: decks(:two).id).update_all(key: decks(:one).key)
    end
  end

  test "every deck fixture spells out a key" do
    # Fixtures skip callbacks, so a missing key is a NOT NULL failure at insertion
    # rather than a nil here — this test is the readable version of that crash.
    assert_equal Deck.count, Deck.where.not(key: nil).count
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `bin/rails test test/models/deck_test.rb -n "/key/"`
Expected: FAIL — `NoMethodError: undefined method 'key='` / unknown attribute `key`.

- [ ] **Step 3: Write the migration**

Create `db/migrate/<timestamp>_add_key_to_decks.rb`:

```ruby
class AddKeyToDecks < ActiveRecord::Migration[8.1]
  def up
    add_column :decks, :key, :string

    # Deliberately not through the model. Deck validates `standard_pool` presence when the
    # format is standard, so `update!` on any pre-#122 Standard row that never got an anchor
    # would abort this migration halfway, leaving a nullable column and no index. Filling a
    # column is all this is; re-validating history is not its job.
    #
    # 16 is spelled out rather than read from Deck::KEY_BYTES: a migration has to keep running
    # after the model has moved on, so it must not depend on a constant the model may rename.
    Deck.reset_column_information
    Deck.where(key: nil).pluck(:id).each do |id|
      Deck.where(id: id).update_all(key: SecureRandom.urlsafe_base64(16))
    end

    change_column_null :decks, :key, false
    add_index :decks, :key, unique: true
  end

  def down
    remove_index :decks, :key
    remove_column :decks, :key
  end
end
```

- [ ] **Step 4: Add the column to the model**

In `app/models/deck.rb`, below the existing validations:

```ruby
  # SecureRandom.urlsafe_base64(16) yields 22 URL-safe characters and 128 bits of entropy.
  # The length is fixed on purpose: a key can therefore never collide with a literal path
  # segment such as "shared", which Stage 2 adds as a collection route.
  KEY_BYTES = 16

  validates :key, presence: true
```

and, with the other callbacks:

```ruby
  before_validation :assign_key, if: -> { key.blank? }
```

and in the private section:

```ruby
  # The deck's address, everywhere: `to_param` returns it, so every URL of this deck is
  # built from it. before_validation rather than before_create so that the callback and the
  # presence validation agree — with before_create, `Deck.new(name: "x").valid?` would be
  # false while `save` succeeded. The `key.blank?` guard stops an update from rewriting it
  # (before_validation runs on update too) and heals a row written by a callback-bypassing
  # insert. There is no uniqueness validation: it would add a SELECT to every deck save to
  # guard a 128-bit collision that will not happen, and the UNIQUE index is the guarantee —
  # the same division of labour as `(set_name, set_number)` on Card.
  def assign_key
    self.key = SecureRandom.urlsafe_base64(KEY_BYTES)
  end
```

and, in the public section near `format_label`:

```ruby
  def to_param = key
```

- [ ] **Step 5: Give both fixtures a key**

In `test/fixtures/decks.yml`, extend the existing note and add the field to both rows:

```yaml
# Read about fixtures at https://api.rubyonrails.org/classes/ActiveRecord/FixtureSet.html
#
# NOTE: fixtures skip callbacks, so name_normalized and key are spelled out by hand.
# DeckTest asserts name_normalized stays in step with name, and that every row has a key —
# `decks.key` is NOT NULL, so a row without one fails to insert and takes the suite with it.
# These are readable rather than 22 characters; only generated keys are that length.

one:
  user: one
  name: MyString
  name_normalized: mystring
  description: MyText
  standard_pool: twm_por
  key: deck-one-key

two:
  user: two
  name: MyString
  name_normalized: mystring
  description: MyText
  standard_pool: twm_por
  key: deck-two-key
```

- [ ] **Step 6: Migrate and run the model tests**

Run: `bin/rails db:migrate && bin/rails db:test:prepare && bin/rails test test/models/deck_test.rb`
Expected: PASS.

- [ ] **Step 7: Sabotage-verify the two tests that could be vacuous**

Change `before_validation :assign_key, if: -> { key.blank? }` to `before_create :assign_key`. Run `bin/rails test test/models/deck_test.rb -n "/blank key/"` — it must FAIL (`valid?` returns false). Restore.

Change `assign_key` to `self.key = "constant"`. Run `bin/rails test test/models/deck_test.rb -n "/url-safe key/"` — it must FAIL on the length. Restore.

- [ ] **Step 8: Record the expected breakage — and do not commit**

Run: `bin/rails test 2>&1 | tail -30`
Expected: **many failures**, all of the shape "Couldn't find Deck with 'id'=deck-one-key" or a 404. This is the signal described at the top of this task: helpers now emit keys, lookups still read ids. Do not fix them here, and do not commit here: Task 2's final step commits both tasks together, once the suite is green again.

---

## Task 2: every deck lookup reads the key

13 lookups in 7 files, plus two identifiers that `to_param` cannot reach. The rule from the spec: **the key replaces the id inside the existing ownership scope.** Do not turn `current_user.decks.find(...)` into `Deck.find_by!(...)` anywhere in this task — that is Stage 2's single, deliberate exception.

**Files:**
- Modify: `app/controllers/decks_controller.rb` (7 lookups at lines 33, 52, 89, 121, 129, 141, 147; plus `compare` at 77)
- Modify: `app/controllers/deck_results_controller.rb:27`
- Modify: `app/controllers/api/decks_controller.rb` (`set_deck`)
- Modify: `app/controllers/api/deck_results_controller.rb:32`
- Modify: `app/controllers/concerns/deck_card_payload.rb` (`set_deck`)
- Modify: `app/controllers/admin/decks_controller.rb:8`
- Modify: `app/services/allocations/physical_decks_by_card.rb`
- Modify: `app/views/components/over_allocations/index_view.rb:32`
- Modify: `app/views/components/decks/deck_card.rb:22`
- Modify: `test/controllers/api/deck_results_controller_test.rb` (private `deck_results_path`)
- Test: `test/controllers/over_allocations_controller_test.rb`

**Interfaces:**
- Consumes: `Deck#key`, `Deck#to_param` (Task 1).
- Produces: `Allocations::PhysicalDecksByCard.call` returns `{ card_id => [{ id:, key:, name: }] }` — `id:` retained for the reallocation form, `key:` added for links. `Allocations::OverAllocations.call` passes that hash through unchanged in its `decks:` value.

**Context you need:** `over_allocations/index_view.rb:32` is the only `deck_path` in the app handed a bare integer rather than a model:

```ruby
link_to d[:name], deck_path(d[:id]), class: "over-allocation-deck-link"
```

`to_param` is a method on the model, so a helper given an integer emits `/decks/42` forever. **Every deck link in the over-allocation report 404s** once Task 1 lands, and no existing test notices. That is what the new test in Step 1 is for.

- [ ] **Step 1: Write the failing test for the report's deck links**

Add to `test/controllers/over_allocations_controller_test.rb` (the `over_allocate` helper is already defined at the bottom of that file):

```ruby
  test "each deck link addresses the deck by its key, not its id" do
    deck = over_allocate(cards(:honedge), owned: 1, committed: 2)

    get over_allocations_path

    assert_response :success
    # `deck_path(deck)` goes through to_param; the point of the test is the negative
    # assertion, because this is the one deck_path in the app that to_param cannot fix.
    assert_select ".over-allocation-deck-link[href=?]", deck_path(deck)
    assert_select ".over-allocation-deck-link[href=?]", "/decks/#{deck.id}", count: 0
  end
```

- [ ] **Step 2: Run it and watch it fail**

Run: `bin/rails test test/controllers/over_allocations_controller_test.rb -n "/by its key/"`
Expected: FAIL — the rendered href is `/decks/<id>`, so the first `assert_select` matches nothing.

- [ ] **Step 3: Carry the key out of the service**

In `app/services/allocations/physical_decks_by_card.rb`, add `decks.key` to the `pluck` and the hash:

```ruby
      rows = @user.decks.where(physical: true)
                  .joins(:deck_cards)
                  .where(deck_cards: { card_id: @card_ids })
                  .where(@condition)
                  .distinct
                  .pluck("deck_cards.card_id", "decks.id", "decks.key", "decks.name")

      # Both identifiers, on purpose: `key` addresses the deck in a link, `id` is what the
      # reallocation form's from_deck_id/to_deck_id selects carry — those reference a row
      # rather than a page. This hash is also what ListOverAllocationsTool serialises to
      # MCP clients, so the key added here is what makes reallocate_owned_copies callable
      # from the report (see Task 4).
      rows.group_by(&:first).transform_values do |group|
        group.map { |(_card_id, deck_id, deck_key, deck_name)| { id: deck_id, key: deck_key, name: deck_name } }
      end
```

- [ ] **Step 4: Use it in the view**

In `app/views/components/over_allocations/index_view.rb:32`:

```ruby
            link_to d[:name], deck_path(d[:key]), class: "over-allocation-deck-link"
```

- [ ] **Step 5: Run the over-allocation test, and sabotage-verify it**

Run: `bin/rails test test/controllers/over_allocations_controller_test.rb`
Expected: PASS, including the pre-existing query-count test — adding a column to a `pluck` adds no query.

Now put `d[:id]` back in the view and re-run: the new test must FAIL. Restore.

- [ ] **Step 6: Switch the seven `DecksController` lookups**

Each of lines 33, 52, 89, 121, 129, 141, 147 keeps its scope and its `includes`, and swaps `find(params[:id])` for `find_by!(key: params[:id])`. For example, `#show`:

```ruby
    @deck = current_user.decks.includes(:archetype, :tournaments, deck_cards: :card, deck_results: []).find_by!(key: params[:id])
```

and `#destroy`:

```ruby
    deck = current_user.decks.find_by!(key: params[:id])
```

`find_by!` raises `ActiveRecord::RecordNotFound` just as `find` did, so the 404 behaviour of every one of these is unchanged.

- [ ] **Step 7: Switch `compare` to keys**

In `app/controllers/decks_controller.rb#compare`:

```ruby
    keys = Array(params[:ids]).map(&:to_s).uniq
    decks = current_user.decks.where(key: keys).includes(deck_cards: :card)
    decks = decks.sort_by { |deck| keys.index(deck.key) }
```

and in `app/views/components/decks/deck_card.rb:22`:

```ruby
          value: @deck.key,
```

`deck_compare_controller.js` needs **no change**: `#selected()` returns `cb.value` and `compare()` appends it verbatim, with no numeric coercion anywhere in the file.

- [ ] **Step 8: Switch the remaining five lookups**

`app/controllers/deck_results_controller.rb:27`, `app/controllers/api/deck_results_controller.rb:32` and `app/controllers/concerns/deck_card_payload.rb`:

```ruby
    @deck = current_user.decks.find_by!(key: params[:deck_id])
```

(`DeckCardPayload#set_deck` keeps no `includes`; `Api::DecksController#set_deck` keeps its own:)

```ruby
      @deck = current_user.decks.includes(deck_cards: { card: :pokemon_subtype }).find_by!(key: params[:id])
```

`app/controllers/admin/decks_controller.rb:8` stays unscoped — an admin panel lists everybody's decks and cannot be scoped to `current_user`, and `Admin::BaseController#require_admin!` is its guard:

```ruby
      @deck = Deck.includes(deck_cards: :card, deck_results: []).find_by!(key: params[:id])
```

- [ ] **Step 9: Fix the one test that builds a deck URL by hand**

In `test/controllers/api/deck_results_controller_test.rb`, the private helper:

```ruby
  def deck_results_path
    "/api/decks/#{@deck.key}/results"
  end
```

- [ ] **Step 10: Run the whole unit suite**

Run: `bin/rails test`
Expected: PASS. Every failure introduced by Task 1 is addressed by this task; anything still red is a lookup this plan missed — find it with `grep -rn "\.find(params" app/`.

- [ ] **Step 11: Run the system suite at both viewports**

Run: `bin/rails test:system`
Then: `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`
Expected: PASS at both. This is not optional here: the system suite is what drives the deck page's real URLs, and `bin/rails test` never loads `test/system/`.

- [ ] **Step 12: Commit Tasks 1 and 2 together**

Both tasks in one commit, as announced at the top of Task 1: between them the suite is red, and the constraint is green before every commit.

```bash
git add db/migrate db/schema.rb app/models/deck.rb test/fixtures/decks.yml test/models/deck_test.rb
git add app/controllers app/services/allocations/physical_decks_by_card.rb app/views/components test/controllers
git commit -m "Address a deck by an unguessable key rather than by its id

to_param returns the key, so all 35 path helpers change what they emit
without being edited. The 13 lookups follow in the same commit: the key
replaces the id *inside* each existing ownership scope, and no lookup
becomes unscoped here.

before_validation rather than before_create so the callback and the
presence validation agree; the UNIQUE index, not a validation, is what
guarantees uniqueness.

Two identifiers to_param cannot reach are edited by hand — the compare
checkbox, and the over-allocation report's deck_path(d[:id]), which was
handed a bare integer and would have 404'd every deck link in the report
with nothing to notice."
```

---

## Task 3: the API and the deck page speak keys

Seven Stimulus controllers build API URLs from a value the server renders. Six declare `deckId: Number`; a `String` arriving there coerces to `NaN` and produces `/api/decks/NaN/cards`, which fails silently in the controller's `catch`. The seventh reads a dataset attribute.

**Files:**
- Modify: `app/controllers/api/decks_controller.rb` (`deck_json`)
- Modify: `app/javascript/controllers/result_modal_controller.js`
- Modify: `app/javascript/controllers/archetype_picker_controller.js`
- Modify: `app/javascript/controllers/deck_card_owned_copies_controller.js`
- Modify: `app/javascript/controllers/printing_picker_controller.js`
- Modify: `app/javascript/controllers/card_search_controller.js`
- Modify: `app/javascript/controllers/deck_card_quantity_controller.js`
- Modify: `app/javascript/controllers/tournament_pdf_controller.js`
- Modify: `app/views/components/decks/show_view.rb`, `deck_card_item.rb`, `result_modal.rb`, `tournament_pdf_modal.rb`, `archetype_field.rb`
- Test: `test/controllers/decks_controller_test.rb`, `test/controllers/api/decks_controller_test.rb`

**Interfaces:**
- Consumes: `Deck#key` (Task 1), the key-reading API lookups (Task 2).
- Produces: `deck_json` returns `key:` and no `id:`. Every Stimulus value that identified a deck is `deckKey: String`, rendered as `data-<controller>-deck-key-value`.

**Context you need:** which view renders which value — `grep -rn "deck_id" app/views/components/decks/` finds all of them, and the grep has to be that wide: `Decks::DeckCardItem` does not read `@deck` at all. It takes a `deck_id:` keyword (`deck_card_item.rb:3`), which `show_view.rb:166` fills with `@deck.id`, and renders it three times as `@deck_id`. Renaming only the `*_deck_id_value` attributes would leave `deck_card_quantity_deck_key_value: @deck_id` — an attribute with the right name and an id in it, which a grep on `deck_id_value` would call done. `archetype_picker_controller.js:59` guards with `if (!this.deckIdValue) return`; a `String` value defaults to `""`, which is falsy, so the guard survives the type change unchanged.

- [ ] **Step 1: Write the failing tests**

In `test/controllers/api/decks_controller_test.rb`:

```ruby
  test "deck json identifies the deck by its key and never by its id" do
    get api_deck_path(@deck), as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal @deck.key, body["key"]
    assert_nil body["id"]
  end
```

In `test/controllers/decks_controller_test.rb`:

```ruby
  test "the deck page hands its javascript the key, not the id" do
    get deck_path(@deck)

    assert_response :success
    # A String landing in a controller that still declares `deckId: Number` coerces to NaN
    # and dies in a fetch catch, so these attributes are the JS half of the identity change
    # and nothing else in the suite reads them.
    assert_select "[data-result-modal-deck-key-value=?]", @deck.key
    assert_select "[data-card-search-deck-key-value=?]", @deck.key
    assert_select "[data-deck-card-quantity-deck-key-value=?]", @deck.key
    assert_select "[data-tournament-pdf-deck-key-value=?]", @deck.key
    assert_select "[data-result-modal-deck-id-value]", count: 0
  end

  test "the compare checkbox carries the key" do
    get decks_path

    assert_response :success
    assert_select ".deck-compare-checkbox[value=?]", @deck.key
  end
```

- [ ] **Step 2: Run them and watch them fail**

Run: `bin/rails test test/controllers/decks_controller_test.rb test/controllers/api/decks_controller_test.rb -n "/key/"`
Expected: FAIL — `key` missing from the JSON, and the `data-*-deck-key-value` attributes absent.

- [ ] **Step 3: Change the JSON**

In `app/controllers/api/decks_controller.rb#deck_json`, replace `id: deck.id,` with:

```ruby
        key: deck.key,
```

Leave `deck_card_json`'s `id:` alone — that identifies a `DeckCard` row, not a deck.

- [ ] **Step 4: Rename the Stimulus values**

In each of the six controllers, `deckId: Number` becomes `deckKey: String` and `this.deckIdValue` becomes `this.deckKeyValue`. The URLs they build need no other change — for example `deck_card_quantity_controller.js`:

```js
  static values = { deckKey: String, cardId: Number, quantity: Number }
  // …
    const updated = await requestJson(`/api/decks/${this.deckKeyValue}/cards/${this.cardIdValue}`, {
```

and `tournament_pdf_controller.js`, which reads a dataset attribute rather than a Stimulus value:

```js
    const deckKey = event.currentTarget.dataset.tournamentPdfDeckKeyValue
    // …
    const url = `/decks/${deckKey}/export?style=tournament_pdf&profile_id=${encodeURIComponent(profileId)}`
```

- [ ] **Step 5: Render the new attribute names**

Every `*_deck_id_value: @deck.id` in `app/views/components/decks/` becomes `*_deck_key_value: @deck.key` — `show_view.rb` (lines 18 and 113), `tournament_pdf_modal.rb:44`, `archetype_field.rb:15`.

`Decks::DeckCardItem` is the exception that needs two edits, not one. Its keyword changes:

```ruby
    def initialize(deck_card:, deck_key:, physical: false, max_owned: 0, over_allocated: false, swappable: false)
      @deck_card = deck_card
      @deck_key = deck_key
```

its three renders become `deck_card_quantity_deck_key_value: @deck_key`, `printing_picker_deck_key_value: @deck_key` and `deck_card_owned_copies_deck_key_value: @deck_key`, and the call site in `show_view.rb:166` passes `deck_key: @deck.key`.

`grep -rn "deck_id" app/views/components/decks/` must come back empty when this step is done — not just `deck_id_value`.

- [ ] **Step 6: Run the tests, then sabotage-verify**

Run: `bin/rails test test/controllers/decks_controller_test.rb test/controllers/api/decks_controller_test.rb`
Expected: PASS.

Revert one view to `result_modal_deck_id_value: @deck.id` and re-run: the deck-page test must FAIL. Restore.

- [ ] **Step 7: Run both system suites — this is where a missed rename shows up**

Run: `bin/rails test:system`
Then: `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`
Expected: PASS. `deck_printing_swap_test`, `deck_proxy_badge_test` and `deck_card_mobile_test` exercise `printing_picker`, `deck_card_quantity` and `deck_card_owned_copies` for real; a value renamed on one side only fails here and nowhere else.

- [ ] **Step 8: Commit**

```bash
git add app/controllers/api/decks_controller.rb app/javascript/controllers app/views/components/decks test/controllers
git commit -m "Hand the deck page and the API a key instead of an id

Six Stimulus controllers declared deckId: Number, where a String coerces
to NaN and the resulting /api/decks/NaN/... dies quietly in a fetch catch.
The renames are therefore asserted server-side as well: nothing else in
the suite reads those attributes."
```

---

## Task 4: the MCP contract, inputs and outputs

A breaking change, accepted by decision 8 of the spec. The part that is easy to miss: **inputs are not the whole contract.** `ListOverAllocationsTool` serialises `Allocations::OverAllocations` straight to JSON, deck identifiers included, so changing only the inputs would leave a client reading "these decks over-commit this card" with no key to hand back to `reallocate_owned_copies`. Task 2's service change already fixed that; this task proves it.

**Files:**
- Modify: `app/mcp/mcp_tool.rb` (`find_deck!`)
- Modify: `app/mcp/add_card_to_deck_tool.rb`, `list_deck_cards_tool.rb`, `set_deck_card_owned_copies_tool.rb`, `set_deck_card_printing_tool.rb`, `set_deck_card_quantity_tool.rb`, `list_printings_tool.rb`, `reallocate_owned_copies_tool.rb`
- Modify: `app/mcp/list_decks_tool.rb`
- Test: `test/mcp/read_tools_test.rb`, `test/mcp/write_tools_test.rb`

**Interfaces:**
- Consumes: `Deck#key` (Task 1), `PhysicalDecksByCard`'s `key:` (Task 2).
- Produces: `McpTool.find_deck!(user, key)` looks up by key. Tool arguments are `deck_key` (String), or `from_deck_key`/`to_deck_key` for `reallocate_owned_copies`. `list_decks` emits `key`, not `id`.

- [ ] **Step 1: Write the failing tests**

In `test/mcp/read_tools_test.rb`:

```ruby
  test "list_decks identifies each deck by its key" do
    # This file's setup defines @user only; the deck is fetched here.
    deck = decks(:one)

    result = ListDecksTool.call(server_context: { user: @user })

    decks = JSON.parse(result.content.first[:text])
    assert_equal [ deck.key ], decks.map { |d| d["key"] }
    assert_nil decks.first["id"]
  end

  test "list_over_allocations carries the key of every deck it names" do
    over_allocate(cards(:honedge), owned: 1, committed: 2)

    result = ListOverAllocationsTool.call(server_context: { user: @user })

    report = JSON.parse(result.content.first[:text])
    assert report.first["decks"].all? { |d| d["key"].present? }, "a named deck had no key"
  end
```

In `test/mcp/write_tools_test.rb` — the test that actually proves the contract is coherent:

```ruby
  test "a client can reallocate using only the keys the over-allocation report gave it" do
    over_allocate(cards(:honedge), owned: 1, committed: 2)
    target = @user.decks.create!(name: "Target", physical: true, standard_pool: standard_pools(:twm_por))
    target.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 0)

    report = JSON.parse(ListOverAllocationsTool.call(server_context: { user: @user }).content.first[:text])
    source_key = report.first["decks"].first["key"]

    result = ReallocateOwnedCopiesTool.call(
      from_deck_key: source_key, to_deck_key: target.key,
      card_id: cards(:honedge).id, quantity: 1, server_context: { user: @user }
    )

    # A presence assertion proves the field exists; only chaining the two tools proves a
    # client can act on what it just read.
    refute_match(/unknown deck/, result.content.first[:text])
    assert_equal 1, target.deck_cards.find_by(card: cards(:honedge)).owned_copies
  end
```

If `over_allocate` is not already available to these tests, copy the helper from `test/controllers/over_allocations_controller_test.rb` into `test/test_helper.rb` rather than duplicating it in two files.

- [ ] **Step 2: Run them and watch them fail**

Run: `bin/rails test test/mcp/`
Expected: FAIL — `list_decks` still emits `id`, and `ReallocateOwnedCopiesTool` raises `ArgumentError: unknown keyword: :from_deck_key`.

- [ ] **Step 3: Look decks up by key**

In `app/mcp/mcp_tool.rb`:

```ruby
    def find_deck!(user, key)
      user.decks.find_by!(key: key)
    end
```

- [ ] **Step 4: Rename the tool arguments**

In each of the six single-deck tools, the schema property and the keyword change together. `add_card_to_deck_tool.rb`:

```ruby
  input_schema(
    properties: {
      deck_key: { type: "string", description: "Key of the user's deck" },
      card_id: { type: "integer", description: "ID of the card to add" },
      quantity: { type: "integer", description: "Number of copies to add (default 1)" }
    },
    required: [ "deck_key", "card_id" ]
  )

  def self.call(deck_key:, card_id:, server_context:, quantity: 1)
    # …
    deck = find_deck!(user, deck_key)
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck key #{deck_key.inspect} or card id #{card_id} (deck must belong to you).")
  end
```

Apply the same shape to `list_deck_cards`, `set_deck_card_owned_copies`, `set_deck_card_printing`, `set_deck_card_quantity`, and `list_printings` (where `deck_key` stays **optional** — its description is "Optional: a deck of the user's to annotate the printings for"). `reallocate_owned_copies_tool.rb` takes `from_deck_key` and `to_deck_key`, both `type: "string"`, both required, and its `find_deck!` calls follow.

Every error string that said "unknown deck id" now says "unknown deck key".

- [ ] **Step 5: Change `list_decks`, description included**

In `app/mcp/list_decks_tool.rb`:

```ruby
  description "List the authenticated user's decks with their keys, names, formats and Standard pool."
```

and in the map:

```ruby
      { key: deck.key, name: deck.name, format: deck.format, standard_pool: deck.standard_pool&.name,
        physical: deck.physical, tcg_live: deck.tcg_live }
```

This is the only way a client discovers the new values, which is why the description has to change with it.

- [ ] **Step 6: Confirm no other tool emits a deck identifier**

Run: `grep -rn "deck.id\|deck_id" app/mcp/`
Expected: no hits. `SuggestOwnedEquivalentsTool`, `ListPrintingsTool` and `ListDeckCardsTool` were checked while writing the spec and emit none; this grep is the guard that Step 4 left nothing behind.

- [ ] **Step 7: Run the MCP tests, then sabotage-verify the chain**

Run: `bin/rails test test/mcp/`
Expected: PASS.

Now drop `key:` from `PhysicalDecksByCard`'s hash and re-run: the chained reallocation test must FAIL with a nil key rather than merely reporting a missing field. Restore.

- [ ] **Step 8: Run everything**

Run: `bin/rails test && bin/rubocop && bin/brakeman --no-pager`
Then: `bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`
Expected: all green.

- [ ] **Step 9: Commit**

```bash
git add app/mcp test/mcp test/test_helper.rb
git commit -m "Speak deck keys over MCP, in outputs as well as inputs

deck_id: integer becomes deck_key: string on seven tools, and list_decks
emits keys — the only way a client discovers them, hence the description
change too. The half that is easy to miss is the output side:
list_over_allocations names decks, and without a key in that payload a
client could read the report and still have nothing to hand back to
reallocate_owned_copies. A test chains the two tools rather than merely
asserting the field is present."
```

---

## Definition of done for Stage 1

- `grep -rn "\.find(params\[:id\])\|\.find(params\[:deck_id\])" app/controllers/` returns nothing for decks.
- `grep -rn "deck_id" app/views/components/decks/` returns nothing — the wide form, because `DeckCardItem` carries a `deck_id:` keyword and not only `*_deck_id_value` attributes.
- `grep -rn "deck.id\|deck_id" app/mcp/` returns nothing.
- `bin/rails test`, `bin/rubocop`, `bin/brakeman --no-pager`, `bin/importmap audit` all pass.
- `bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system` both pass.
- The app is functionally unchanged. Every deck URL is `/decks/<22 chars>`.

## What Stage 2 adds

`decks.shared` and the Share modal, Pundit and `PubliclyReachable`, the public deck view, `/decks/shared`, the visitor dashboard, the navbar shell, the fourth search group, app-wide `noindex`, and the rate limits. Plan: `docs/superpowers/plans/2026-09-02-shared-decks-stage-2-sharing.md`.
