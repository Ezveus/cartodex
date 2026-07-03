# Collection ↔ Deck Allocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the collection↔deck "transfer" model with a real-copies-vs-proxies allocation model: the collection is the source of truth for owned cards, physical decks back some copies with owned cards (the rest are proxies), and the real copies committed across physical decks can never exceed what you own — plus advisory suggestions of owned equivalent printings.

**Architecture:** `deck_cards` gains `owned_copies` (reals; `quantity` stays the total; `proxies = quantity − owned_copies`). A query service `Allocations::Availability` computes owned/committed/available per exact printing. Thin services perform each write (add, set-owned, reallocate, set-quantity, set-collection-quantity); MCP tools wrap them. Equivalence (same `Card#fingerprint`) is purely advisory via `Collections::OwnedEquivalents`. The old `Decks::CardTransfer` service and `move_card_*` tools are removed.

**Tech Stack:** Rails 8.1, Ruby 4.0.1, SQLite3, `mcp` gem 0.22, Minitest with fixtures, rubocop-rails-omakase.

## Global Constraints

- Rails 8.1 / Ruby 4.0.1; SQLite3 everywhere.
- Services inherit `ApplicationService` (`.call(...)` → `new(...).call`).
- `app/mcp/` files define **top-level** constants (autoloaded root); MCP tools are NOT namespaced. Base class `McpTool` provides private class helpers `current_user(server_context)`, `find_card!(id)`, `find_deck!(user, id)`, `text(str)`, `positive_quantity?(q)`, `quantity_error(q)`.
- Allocation is **per exact printing (`card_id`)**. Only decks with `physical == true` consume the collection; on a non-physical deck `owned_copies` is always 0. `tcg_live` has no effect on allocation.
- Invariant: `Σ owned_copies(X) over physical decks ≤ owned(X)`. It can only be violated by a collection decrease, which is **allowed** and leaves a **tolerated, surfaced** over-allocation (never auto-corrected, never blocked). Edits/adds can never create over-allocation.
- Equivalence = same `Card#fingerprint`; **advisory only**, never changes allocation.
- Scope: domain model + MCP tools only. Do not rework the web UI/JSON API beyond keeping it green. Leave `decks.physical`/`tcg_live`/`has_proxies` columns untouched (no `medium` enum; `has_proxies` stays a manual UI flag this iteration).
- Lint clean with `bin/rubocop`; no new `bin/brakeman` warnings.
- Spec: `docs/superpowers/specs/2026-07-02-collection-deck-allocation-design.md`.

---

### Task 1: Migration + `DeckCard`/`Deck` allocation invariants

**Files:**
- Create: `db/migrate/YYYYMMDDHHMMSS_add_owned_copies_and_fingerprint_index.rb`
- Modify: `app/models/deck_card.rb`
- Modify: `app/models/deck.rb`
- Test: `test/models/deck_card_test.rb`, `test/models/deck_test.rb`

**Interfaces:**
- Produces: `deck_cards.owned_copies` (integer, default 0, not null); index on `cards.fingerprint`. `DeckCard` validates `owned_copies` is an integer in `0..quantity` and is `0` unless its deck is `physical?`. `Deck#release_owned_copies_if_not_physical` zeroes children's `owned_copies` when `physical` flips false.

- [ ] **Step 1: Write failing model tests**

Add to `test/models/deck_card_test.rb`:

```ruby
require "test_helper"

class DeckCardTest < ActiveSupport::TestCase
  test "owned_copies defaults to 0" do
    deck = decks(:one)
    dc = deck.deck_cards.create!(card: cards(:trainer_card), quantity: 2)
    assert_equal 0, dc.owned_copies
  end

  test "owned_copies cannot exceed quantity" do
    deck = users(:one).decks.create!(name: "Phys", physical: true)
    dc = deck.deck_cards.new(card: cards(:honedge), quantity: 2, owned_copies: 3)
    assert_not dc.valid?
    assert_includes dc.errors[:owned_copies], "cannot exceed quantity"
  end

  test "owned_copies must be 0 on a non-physical deck" do
    deck = decks(:one) # not physical
    dc = deck.deck_cards.new(card: cards(:honedge), quantity: 2, owned_copies: 1)
    assert_not dc.valid?
    assert_includes dc.errors[:owned_copies], "must be 0 for a non-physical deck"
  end

  test "owned_copies is allowed on a physical deck" do
    deck = users(:one).decks.create!(name: "Phys", physical: true)
    dc = deck.deck_cards.new(card: cards(:honedge), quantity: 2, owned_copies: 2)
    assert dc.valid?
  end
end
```

Add to `test/models/deck_test.rb` (create with this class if absent):

```ruby
require "test_helper"

class DeckTest < ActiveSupport::TestCase
  test "flipping physical to false releases owned copies" do
    deck = users(:one).decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)

    deck.update!(physical: false)

    assert_equal 0, deck.deck_cards.sum(:owned_copies)
  end
end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/models/deck_card_test.rb test/models/deck_test.rb -v`
Expected: FAIL — `owned_copies` is not a column / methods missing.

- [ ] **Step 3: Write the migration**

Create `db/migrate/YYYYMMDDHHMMSS_add_owned_copies_and_fingerprint_index.rb` (generate a real timestamp with `bin/rails g migration AddOwnedCopiesAndFingerprintIndex` then replace the body):

```ruby
class AddOwnedCopiesAndFingerprintIndex < ActiveRecord::Migration[8.1]
  def change
    add_column :deck_cards, :owned_copies, :integer, default: 0, null: false
    add_index :cards, :fingerprint
  end
end
```

- [ ] **Step 4: Add `DeckCard` validations**

Replace the body of `app/models/deck_card.rb`:

```ruby
class DeckCard < ApplicationRecord
  belongs_to :deck
  belongs_to :card

  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :owned_copies, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :owned_copies_within_quantity
  validate :owned_copies_zero_unless_physical

  private

  def owned_copies_within_quantity
    return if owned_copies.nil? || quantity.nil?

    errors.add(:owned_copies, "cannot exceed quantity") if owned_copies > quantity
  end

  def owned_copies_zero_unless_physical
    return if owned_copies.to_i.zero?

    errors.add(:owned_copies, "must be 0 for a non-physical deck") unless deck&.physical?
  end
end
```

- [ ] **Step 5: Add the `Deck` release callback**

In `app/models/deck.rb`, add after the existing `before_validation :clear_inapplicable_classification` line:

```ruby
  after_update :release_owned_copies_if_not_physical
```

and add this private method (alongside the existing private methods):

```ruby
  # When a deck stops being physical, its real (owned) copies are released back
  # to the collection's available pool.
  def release_owned_copies_if_not_physical
    return unless saved_change_to_physical? && !physical?

    deck_cards.update_all(owned_copies: 0)
  end
```

- [ ] **Step 6: Migrate and run tests**

Run: `bin/rails db:migrate && bin/rails db:test:prepare && bin/rails test test/models/deck_card_test.rb test/models/deck_test.rb -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models/deck_card.rb app/models/deck.rb test/models/deck_card_test.rb test/models/deck_test.rb
git commit -m "feat: add deck_card owned_copies with allocation invariants"
```

---

### Task 2: `Allocations::Availability` query service

**Files:**
- Create: `app/services/allocations/availability.rb`
- Test: `test/services/allocations/availability_test.rb`

**Interfaces:**
- Consumes: `deck_cards.owned_copies` (Task 1).
- Produces: `Allocations::Availability.call(user:, card:, excluding_deck: nil)` → `Allocations::Availability::Result` with `#owned`, `#committed`, `#available` (all Integer). `owned` = Σ collection quantity for the card; `committed` = Σ `owned_copies` across the user's **physical** decks for the card; `available` = `max(0, owned − committed_excluding)` where `committed_excluding` drops `excluding_deck`'s own `owned_copies`.

- [ ] **Step 1: Write the failing test**

Create `test/services/allocations/availability_test.rb`:

```ruby
require "test_helper"

module Allocations
  class AvailabilityTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
      @user.collections.find_or_create_by!(card: @card).update!(quantity: 3)
      @deck_a = @user.decks.create!(name: "A", physical: true)
      @deck_b = @user.decks.create!(name: "B", physical: true)
    end

    test "available equals owned when nothing is committed" do
      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 3, result.owned
      assert_equal 0, result.committed
      assert_equal 3, result.available
    end

    test "committed sums owned_copies across physical decks; available is the remainder" do
      @deck_a.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)
      @deck_b.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)

      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 3, result.committed
      assert_equal 0, result.available
    end

    test "excluding_deck frees that deck's own committed copies" do
      @deck_a.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

      result = Allocations::Availability.call(user: @user, card: @card, excluding_deck: @deck_a)
      assert_equal 2, result.committed         # total committed still 2
      assert_equal 3, result.available         # but deck A's 2 are reclaimable → 3 free for A
    end

    test "non-physical decks do not count toward committed" do
      live = @user.decks.create!(name: "Live", physical: false)
      live.deck_cards.create!(card: @card, quantity: 4) # owned_copies forced 0

      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 0, result.committed
      assert_equal 3, result.available
    end

    test "available floors at zero when over-allocated" do
      @deck_a.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)
      @user.collections.find_by(card: @card).update!(quantity: 2) # sold one

      result = Allocations::Availability.call(user: @user, card: @card)
      assert_equal 2, result.owned
      assert_equal 3, result.committed
      assert_equal 0, result.available
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/allocations/availability_test.rb -v`
Expected: FAIL — `uninitialized constant Allocations::Availability`.

- [ ] **Step 3: Write the implementation**

Create `app/services/allocations/availability.rb`:

```ruby
module Allocations
  # Computes, for one user and one exact printing (card), how many copies are
  # owned, how many are committed as real copies across physical decks, and how
  # many remain available. `excluding_deck` drops that deck's own committed
  # copies from the total, yielding the pool that deck may (re)claim.
  class Availability < ApplicationService
    Result = Struct.new(:owned, :committed, :available, keyword_init: true)

    def initialize(user:, card:, excluding_deck: nil)
      @user = user
      @card = card
      @excluding_deck = excluding_deck
    end

    def call
      Result.new(owned: owned, committed: committed, available: [ owned - committed_excluding, 0 ].max)
    end

    private

    def owned
      @user.collections.where(card: @card).sum(:quantity)
    end

    def committed
      physical_deck_cards.sum(:owned_copies)
    end

    def committed_excluding
      scope = physical_deck_cards
      scope = scope.where.not(deck_id: @excluding_deck.id) if @excluding_deck
      scope.sum(:owned_copies)
    end

    def physical_deck_cards
      DeckCard.where(card: @card, deck_id: @user.decks.where(physical: true).select(:id))
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/allocations/availability_test.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/allocations/availability.rb test/services/allocations/availability_test.rb
git commit -m "feat: add Allocations::Availability query service"
```

---

### Task 3: Remove the old transfer machinery

**Files:**
- Delete: `app/services/decks/card_transfer.rb`, `test/services/decks/card_transfer_test.rb`
- Delete: `app/mcp/move_card_to_deck_tool.rb`, `app/mcp/move_card_from_deck_tool.rb`
- Modify: `app/controllers/mcp/server_controller.rb` (drop the two tools from `TOOLS`)
- Modify: `test/mcp/write_tools_test.rb` (remove the two Move tool tests)

**Interfaces:**
- Produces: a codebase with no `Decks::CardTransfer`, `MoveCardToDeckTool`, or `MoveCardFromDeckTool`. `Mcp::ServerController::TOOLS` no longer lists the two Move tools.

- [ ] **Step 1: Delete the files**

```bash
git rm app/services/decks/card_transfer.rb test/services/decks/card_transfer_test.rb app/mcp/move_card_to_deck_tool.rb app/mcp/move_card_from_deck_tool.rb
```

- [ ] **Step 2: Remove the two tools from the controller**

In `app/controllers/mcp/server_controller.rb`, delete the `MoveCardToDeckTool,` and `MoveCardFromDeckTool,` lines from the `TOOLS` array.

- [ ] **Step 3: Remove the Move tool tests**

In `test/mcp/write_tools_test.rb`, delete the two tests named `"MoveCardToDeckTool transfers from collection to deck"` and `"MoveCardFromDeckTool transfers from deck back to collection"` (the blocks at lines ~35–47).

- [ ] **Step 4: Run the suite to verify nothing else referenced them**

Run: `bin/rails test`
Expected: PASS (no `NameError`/`uninitialized constant` for the removed constants).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "refactor: remove obsolete deck-transfer service and MCP tools"
```

---

### Task 4: `Collections::QuantitySetter` + `set_collection_quantity` tool

**Files:**
- Create: `app/services/collections/quantity_setter.rb`
- Create: `app/mcp/set_collection_quantity_tool.rb`
- Modify: `app/controllers/mcp/server_controller.rb` (add `SetCollectionQuantityTool` to `TOOLS`)
- Test: `test/services/collections/quantity_setter_test.rb`, `test/mcp/write_tools_test.rb`

**Interfaces:**
- Produces: `Collections::QuantitySetter.call(user:, card:, quantity:)` → the saved `Collection` (creates the row if absent; `quantity` is an exact value `≥ 0`; `0` is allowed and may leave decks over-allocated — never blocked). `SetCollectionQuantityTool.call(card_id:, quantity:, server_context:)`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/collections/quantity_setter_test.rb`:

```ruby
require "test_helper"

module Collections
  class QuantitySetterTest < ActiveSupport::TestCase
    test "sets an exact owned quantity, creating the row" do
      user = users(:two)
      card = cards(:trainer_card)

      collection = Collections::QuantitySetter.call(user: user, card: card, quantity: 5)

      assert_equal 5, collection.quantity
    end

    test "can reduce below what is committed without raising (tolerated over-allocation)" do
      user = users(:one)
      card = cards(:honedge)
      user.collections.find_or_create_by!(card: card).update!(quantity: 3)
      deck = user.decks.create!(name: "A", physical: true)
      deck.deck_cards.create!(card: card, quantity: 3, owned_copies: 3)

      collection = Collections::QuantitySetter.call(user: user, card: card, quantity: 2)

      assert_equal 2, collection.quantity
    end

    test "rejects a negative quantity" do
      assert_raises(ActiveRecord::RecordInvalid) do
        Collections::QuantitySetter.call(user: users(:one), card: cards(:honedge), quantity: -1)
      end
    end
  end
end
```

Add to `test/mcp/write_tools_test.rb` (inside `WriteToolsTest`):

```ruby
  test "SetCollectionQuantityTool sets the owned quantity" do
    SetCollectionQuantityTool.call(card_id: @card.id, quantity: 7, server_context: @context)

    assert_equal 7, @user.collections.find_by(card: @card).quantity
  end

  test "SetCollectionQuantityTool rejects a negative quantity with a clean error" do
    response = SetCollectionQuantityTool.call(card_id: @card.id, quantity: -1, server_context: @context)

    assert_match(/must be/i, response_text(response))
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/collections/quantity_setter_test.rb test/mcp/write_tools_test.rb -v`
Expected: FAIL — constants missing.

- [ ] **Step 3: Write the service**

Create `app/services/collections/quantity_setter.rb`:

```ruby
module Collections
  # Sets a user's owned quantity for a card to an exact value. Reducing below
  # what physical decks currently commit is allowed and leaves those decks
  # over-allocated (surfaced elsewhere, never blocked here).
  class QuantitySetter < ApplicationService
    def initialize(user:, card:, quantity:)
      @user = user
      @card = card
      @quantity = quantity
    end

    def call
      collection = @user.collections.find_or_initialize_by(card: @card)
      collection.update!(quantity: @quantity)
      collection
    end
  end
end
```

- [ ] **Step 4: Write the MCP tool**

Create `app/mcp/set_collection_quantity_tool.rb`:

```ruby
class SetCollectionQuantityTool < McpTool
  description "Set the exact owned quantity of a card in the authenticated user's collection (e.g. to record a sale). May leave physical decks over-allocated; never blocked."
  input_schema(
    properties: {
      card_id: { type: "integer", description: "ID of the card" },
      quantity: { type: "integer", minimum: 0, description: "Exact number of copies owned (0 allowed)" }
    },
    required: [ "card_id", "quantity" ]
  )

  def self.call(card_id:, quantity:, server_context:)
    user = current_user(server_context)
    card = find_card!(card_id)
    collection = Collections::QuantitySetter.call(user: user, card: card, quantity: quantity)
    text("Set #{card.name} owned quantity to #{collection.quantity}.")
  rescue ActiveRecord::RecordNotFound
    text("Error: no card with id #{card_id}.")
  rescue ActiveRecord::RecordInvalid => e
    text("Error: #{e.message}")
  end
end
```

- [ ] **Step 5: Register the tool**

In `app/controllers/mcp/server_controller.rb`, add `SetCollectionQuantityTool,` to the `TOOLS` array (with the other write tools).

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/services/collections/quantity_setter_test.rb test/mcp/write_tools_test.rb -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/services/collections/quantity_setter.rb app/mcp/set_collection_quantity_tool.rb app/controllers/mcp/server_controller.rb test/services/collections/quantity_setter_test.rb test/mcp/write_tools_test.rb
git commit -m "feat: add set_collection_quantity service and MCP tool"
```

---

### Task 5: Physical auto-split in `Decks::CardAdder` (+ `add_card_to_deck`)

**Files:**
- Modify: `app/services/decks/card_adder.rb`
- Test: `test/services/decks/card_adder_test.rb`, `test/mcp/write_tools_test.rb`

**Interfaces:**
- Consumes: `Allocations::Availability` (Task 2).
- Produces: `Decks::CardAdder.call(deck:, card:, quantity: 1)` still increments the deck_card's `quantity`, and now — **only when `deck.physical?`** — greedily bumps `owned_copies` to `min(new_quantity, max(current_owned, available_excluding_self))` (reals first, remainder proxies, never demoting existing reals, never exceeding availability). Non-physical decks keep `owned_copies` at 0. `AddCardToDeckTool` is unchanged in signature and simply delegates here.

- [ ] **Step 1: Write the failing tests**

Add to `test/services/decks/card_adder_test.rb` (inside the existing `Decks::CardAdderTest`):

```ruby
    test "physical deck backs reals greedily then fills proxies" do
      user = users(:one)
      card = cards(:honedge)
      user.collections.find_or_create_by!(card: card).update!(quantity: 3)
      deck = user.decks.create!(name: "A", physical: true)

      deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: 4)

      assert_equal 4, deck_card.quantity
      assert_equal 3, deck_card.owned_copies # 3 reals + 1 proxy
    end

    test "a second physical deck gets only proxies once owned copies are exhausted" do
      user = users(:one)
      card = cards(:honedge)
      user.collections.find_or_create_by!(card: card).update!(quantity: 3)
      deck_a = user.decks.create!(name: "A", physical: true)
      deck_b = user.decks.create!(name: "B", physical: true)
      Decks::CardAdder.call(deck: deck_a, card: card, quantity: 4) # takes all 3 reals

      deck_card_b = Decks::CardAdder.call(deck: deck_b, card: card, quantity: 4)

      assert_equal 4, deck_card_b.quantity
      assert_equal 0, deck_card_b.owned_copies # all proxies
    end

    test "non-physical deck never backs reals" do
      user = users(:one)
      card = cards(:honedge)
      user.collections.find_or_create_by!(card: card).update!(quantity: 3)
      deck = user.decks.create!(name: "Live", physical: false)

      deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: 2)

      assert_equal 0, deck_card.owned_copies
    end
```

Add to `test/mcp/write_tools_test.rb` a physical-deck case (the existing setup uses non-physical `decks(:one)`, so build a physical deck locally):

```ruby
  test "AddCardToDeckTool backs reals on a physical deck" do
    physical = @user.decks.create!(name: "Phys", physical: true)
    @user.collections.find_by(card: @card).update!(quantity: 2) # honedge owned 2

    AddCardToDeckTool.call(deck_id: physical.id, card_id: @card.id, quantity: 3, server_context: @context)

    dc = physical.deck_cards.find_by(card: @card)
    assert_equal 3, dc.quantity
    assert_equal 2, dc.owned_copies
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/decks/card_adder_test.rb test/mcp/write_tools_test.rb -v`
Expected: FAIL — `owned_copies` stays 0 (auto-split not implemented).

- [ ] **Step 3: Implement the auto-split**

Replace `app/services/decks/card_adder.rb`:

```ruby
module Decks
  class CardAdder < ApplicationService
    def initialize(deck:, card:, quantity: 1)
      @deck = deck
      @card = card
      @quantity = quantity
    end

    def call
      deck_card = @deck.deck_cards.find_or_initialize_by(card: @card)
      deck_card.quantity = deck_card.quantity.to_i + @quantity
      deck_card.owned_copies = target_owned_copies(deck_card) if @deck.physical?
      deck_card.save!
      deck_card
    end

    private

    # Greedy backing: use as many reals as the collection makes available to
    # this deck, capped at the deck_card's total, and never below what the deck
    # already backs (an add never demotes existing reals).
    def target_owned_copies(deck_card)
      current = deck_card.owned_copies.to_i
      free_for_deck = Allocations::Availability.call(user: @deck.user, card: @card, excluding_deck: @deck).available
      [ deck_card.quantity, [ current, free_for_deck ].max ].min
    end
  end
end
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bin/rails test test/services/decks/card_adder_test.rb test/mcp/write_tools_test.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/decks/card_adder.rb test/services/decks/card_adder_test.rb test/mcp/write_tools_test.rb
git commit -m "feat: back real copies greedily when adding to a physical deck"
```

---

### Task 6: `Decks::OwnedCopiesSetter` + `set_deck_card_owned_copies` tool

**Files:**
- Create: `app/services/decks/owned_copies_setter.rb`
- Create: `app/mcp/set_deck_card_owned_copies_tool.rb`
- Modify: `app/controllers/mcp/server_controller.rb`
- Test: `test/services/decks/owned_copies_setter_test.rb`, `test/mcp/write_tools_test.rb`

**Interfaces:**
- Consumes: `Allocations::Availability` (Task 2).
- Produces: `Decks::OwnedCopiesSetter.call(deck:, card:, owned_copies:)` → the saved `DeckCard`. Sets the real count for a **physical** deck's existing card. Raises `Decks::OwnedCopiesSetter::NotPhysicalError` if the deck isn't physical, and `ArgumentError` if `owned_copies` is outside `0..min(quantity, available_for_deck)` (so an edit can never create over-allocation). `SetDeckCardOwnedCopiesTool.call(deck_id:, card_id:, owned_copies:, server_context:)`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/decks/owned_copies_setter_test.rb`:

```ruby
require "test_helper"

module Decks
  class OwnedCopiesSetterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
      @user.collections.find_or_create_by!(card: @card).update!(quantity: 3)
      @deck = @user.decks.create!(name: "A", physical: true)
      @deck_card = @deck.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)
    end

    test "lowers the real count (demoting to proxy)" do
      dc = Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, owned_copies: 1)
      assert_equal 1, dc.owned_copies
    end

    test "rejects exceeding the deck_card quantity" do
      assert_raises(ArgumentError) do
        Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, owned_copies: 5)
      end
    end

    test "rejects exceeding availability (cannot create over-allocation)" do
      other = @user.decks.create!(name: "B", physical: true)
      other.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2) # only 1 free for @deck

      assert_raises(ArgumentError) do
        Decks::OwnedCopiesSetter.call(deck: @deck, card: @card, owned_copies: 3)
      end
    end

    test "rejects a non-physical deck" do
      live = @user.decks.create!(name: "Live", physical: false)
      live.deck_cards.create!(card: @card, quantity: 2)

      assert_raises(Decks::OwnedCopiesSetter::NotPhysicalError) do
        Decks::OwnedCopiesSetter.call(deck: live, card: @card, owned_copies: 1)
      end
    end
  end
end
```

Add to `test/mcp/write_tools_test.rb`:

```ruby
  test "SetDeckCardOwnedCopiesTool adjusts the real/proxy split" do
    physical = @user.decks.create!(name: "Phys", physical: true)
    @user.collections.find_by(card: @card).update!(quantity: 3)
    physical.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)

    SetDeckCardOwnedCopiesTool.call(deck_id: physical.id, card_id: @card.id, owned_copies: 1, server_context: @context)

    assert_equal 1, physical.deck_cards.find_by(card: @card).owned_copies
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/decks/owned_copies_setter_test.rb test/mcp/write_tools_test.rb -v`
Expected: FAIL — constants missing.

- [ ] **Step 3: Write the service**

Create `app/services/decks/owned_copies_setter.rb`:

```ruby
module Decks
  # Sets the real (owned-backed) copy count of an existing card in a physical
  # deck. The new value is bounded by the deck_card's total and by availability,
  # so an edit can never create over-allocation (only a collection decrease can).
  class OwnedCopiesSetter < ApplicationService
    class NotPhysicalError < StandardError; end

    def initialize(deck:, card:, owned_copies:)
      @deck = deck
      @card = card
      @owned_copies = owned_copies
    end

    def call
      raise NotPhysicalError, "deck is not physical" unless @deck.physical?

      deck_card = @deck.deck_cards.find_by!(card: @card)
      max_owned = [ deck_card.quantity, availability.available ].min
      unless @owned_copies.is_a?(Integer) && @owned_copies.between?(0, max_owned)
        raise ArgumentError, "owned_copies must be between 0 and #{max_owned}"
      end

      deck_card.update!(owned_copies: @owned_copies)
      deck_card
    end

    private

    def availability
      Allocations::Availability.call(user: @deck.user, card: @card, excluding_deck: @deck)
    end
  end
end
```

- [ ] **Step 4: Write the MCP tool**

Create `app/mcp/set_deck_card_owned_copies_tool.rb`:

```ruby
class SetDeckCardOwnedCopiesTool < McpTool
  description "Set how many copies of a card in a physical deck are backed by owned cards (the rest are proxies). Bounded by the deck total and by availability; cannot create over-allocation."
  input_schema(
    properties: {
      deck_id: { type: "integer", description: "ID of the user's physical deck" },
      card_id: { type: "integer", description: "ID of the card" },
      owned_copies: { type: "integer", minimum: 0, description: "Number of real (owned-backed) copies" }
    },
    required: [ "deck_id", "card_id", "owned_copies" ]
  )

  def self.call(deck_id:, card_id:, owned_copies:, server_context:)
    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    card = find_card!(card_id)
    deck_card = Decks::OwnedCopiesSetter.call(deck: deck, card: card, owned_copies: owned_copies)
    text("#{card.name} in deck “#{deck.name}”: #{deck_card.owned_copies} real, #{deck_card.quantity - deck_card.owned_copies} proxy.")
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck, or the card is not in that deck.")
  rescue Decks::OwnedCopiesSetter::NotPhysicalError
    text("Error: deck “#{deck&.name}” is not physical; only physical decks back owned copies.")
  rescue ArgumentError => e
    text("Error: #{e.message}")
  end
end
```

- [ ] **Step 5: Register the tool**

In `app/controllers/mcp/server_controller.rb`, add `SetDeckCardOwnedCopiesTool,` to `TOOLS`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/services/decks/owned_copies_setter_test.rb test/mcp/write_tools_test.rb -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/services/decks/owned_copies_setter.rb app/mcp/set_deck_card_owned_copies_tool.rb app/controllers/mcp/server_controller.rb test/services/decks/owned_copies_setter_test.rb test/mcp/write_tools_test.rb
git commit -m "feat: add set_deck_card_owned_copies service and MCP tool"
```

---

### Task 7: `Decks::OwnedCopiesReallocator` + `reallocate_owned_copies` tool

**Files:**
- Create: `app/services/decks/owned_copies_reallocator.rb`
- Create: `app/mcp/reallocate_owned_copies_tool.rb`
- Modify: `app/controllers/mcp/server_controller.rb`
- Test: `test/services/decks/owned_copies_reallocator_test.rb`, `test/mcp/write_tools_test.rb`

**Interfaces:**
- Produces: `Decks::OwnedCopiesReallocator.call(from_deck:, to_deck:, card:, quantity:)` → `[from_deck_card, to_deck_card]`. Moves `quantity` real copies from `from_deck` to `to_deck` (both physical, both already holding the card). Pure conversion (deck totals unchanged, global `committed` unchanged). Raises `Decks::OwnedCopiesReallocator::NotPhysicalError` unless both are physical, and `ArgumentError` if `quantity` isn't positive, the source lacks that many reals, or the target lacks that many proxy slots (`to.owned_copies + quantity > to.quantity`). Transactional. `ReallocateOwnedCopiesTool.call(from_deck_id:, to_deck_id:, card_id:, quantity:, server_context:)`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/decks/owned_copies_reallocator_test.rb`:

```ruby
require "test_helper"

module Decks
  class OwnedCopiesReallocatorTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
      @user.collections.find_or_create_by!(card: @card).update!(quantity: 3)
      @deck_a = @user.decks.create!(name: "A", physical: true)
      @deck_b = @user.decks.create!(name: "B", physical: true)
      @a = @deck_a.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)
      @b = @deck_b.deck_cards.create!(card: @card, quantity: 4, owned_copies: 0)
    end

    test "moves reals without changing deck sizes or global committed" do
      Decks::OwnedCopiesReallocator.call(from_deck: @deck_a, to_deck: @deck_b, card: @card, quantity: 1)

      assert_equal 4, @a.reload.quantity
      assert_equal 2, @a.owned_copies
      assert_equal 4, @b.reload.quantity
      assert_equal 1, @b.owned_copies
    end

    test "rejects when the source lacks enough reals" do
      assert_raises(ArgumentError) do
        Decks::OwnedCopiesReallocator.call(from_deck: @deck_a, to_deck: @deck_b, card: @card, quantity: 4)
      end
    end

    test "rejects when the target lacks proxy slots" do
      @b.update!(owned_copies: 4) # no proxy slots left (but this over-fills availability; set quantity room instead)
      @b.update!(quantity: 4, owned_copies: 4)
      assert_raises(ArgumentError) do
        Decks::OwnedCopiesReallocator.call(from_deck: @deck_a, to_deck: @deck_b, card: @card, quantity: 1)
      end
    end

    test "rejects a non-physical deck" do
      live = @user.decks.create!(name: "Live", physical: false)
      live.deck_cards.create!(card: @card, quantity: 4)
      assert_raises(Decks::OwnedCopiesReallocator::NotPhysicalError) do
        Decks::OwnedCopiesReallocator.call(from_deck: @deck_a, to_deck: live, card: @card, quantity: 1)
      end
    end
  end
end
```

> Note for the implementer: the "target lacks proxy slots" setup above deliberately sets `@deck_b` to `quantity: 4, owned_copies: 4`. Since `@deck_a` also holds 3 reals, that is a 7-real over-allocation against 3 owned — which is fine for this test because reallocation does no availability check (it only checks source reals and target proxy slots). If model validation rejects `owned_copies: 4` on `@b` for any reason, adjust the fixtures so the target genuinely has no proxy slots (`owned_copies == quantity`) while staying individually valid.

Add to `test/mcp/write_tools_test.rb`:

```ruby
  test "ReallocateOwnedCopiesTool moves reals between physical decks" do
    @user.collections.find_by(card: @card).update!(quantity: 3)
    a = @user.decks.create!(name: "A", physical: true)
    b = @user.decks.create!(name: "B", physical: true)
    a.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)
    b.deck_cards.create!(card: @card, quantity: 4, owned_copies: 0)

    ReallocateOwnedCopiesTool.call(from_deck_id: a.id, to_deck_id: b.id, card_id: @card.id, quantity: 1, server_context: @context)

    assert_equal 2, a.deck_cards.find_by(card: @card).owned_copies
    assert_equal 1, b.deck_cards.find_by(card: @card).owned_copies
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/decks/owned_copies_reallocator_test.rb test/mcp/write_tools_test.rb -v`
Expected: FAIL — constants missing.

- [ ] **Step 3: Write the service**

Create `app/services/decks/owned_copies_reallocator.rb`:

```ruby
module Decks
  # Moves real (owned-backed) copies of a card from one physical deck to another
  # without changing either deck's size: the freed slot in the source becomes a
  # proxy, a proxy slot in the target becomes real. Global committed is unchanged,
  # so the invariant is preserved by construction.
  class OwnedCopiesReallocator < ApplicationService
    class NotPhysicalError < StandardError; end

    def initialize(from_deck:, to_deck:, card:, quantity:)
      @from_deck = from_deck
      @to_deck = to_deck
      @card = card
      @quantity = quantity
    end

    def call
      raise NotPhysicalError, "both decks must be physical" unless @from_deck.physical? && @to_deck.physical?
      raise ArgumentError, "quantity must be a positive integer" unless @quantity.is_a?(Integer) && @quantity.positive?

      ActiveRecord::Base.transaction do
        from = @from_deck.deck_cards.find_by!(card: @card)
        to = @to_deck.deck_cards.find_by!(card: @card)

        raise ArgumentError, "source deck has only #{from.owned_copies} real copies" if from.owned_copies < @quantity
        raise ArgumentError, "target deck has no proxy slots to convert" if to.owned_copies + @quantity > to.quantity

        from.update!(owned_copies: from.owned_copies - @quantity)
        to.update!(owned_copies: to.owned_copies + @quantity)
        [ from, to ]
      end
    end
  end
end
```

- [ ] **Step 4: Write the MCP tool**

Create `app/mcp/reallocate_owned_copies_tool.rb`:

```ruby
class ReallocateOwnedCopiesTool < McpTool
  description "Move real (owned-backed) copies of a card from one physical deck to another. Deck sizes are unchanged; a proxy in the target becomes real and a real in the source becomes a proxy."
  input_schema(
    properties: {
      from_deck_id: { type: "integer", description: "ID of the source physical deck" },
      to_deck_id: { type: "integer", description: "ID of the target physical deck" },
      card_id: { type: "integer", description: "ID of the card" },
      quantity: { type: "integer", minimum: 1, description: "How many real copies to move" }
    },
    required: [ "from_deck_id", "to_deck_id", "card_id", "quantity" ]
  )

  def self.call(from_deck_id:, to_deck_id:, card_id:, quantity:, server_context:)
    user = current_user(server_context)
    from_deck = find_deck!(user, from_deck_id)
    to_deck = find_deck!(user, to_deck_id)
    card = find_card!(card_id)
    from, to = Decks::OwnedCopiesReallocator.call(from_deck: from_deck, to_deck: to_deck, card: card, quantity: quantity)
    text("Moved #{quantity}× real #{card.name}: “#{from_deck.name}” now #{from.owned_copies} real, “#{to_deck.name}” now #{to.owned_copies} real.")
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck, or the card is not in one of the decks.")
  rescue Decks::OwnedCopiesReallocator::NotPhysicalError
    text("Error: both decks must be physical.")
  rescue ArgumentError => e
    text("Error: #{e.message}")
  end
end
```

- [ ] **Step 5: Register the tool**

In `app/controllers/mcp/server_controller.rb`, add `ReallocateOwnedCopiesTool,` to `TOOLS`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/services/decks/owned_copies_reallocator_test.rb test/mcp/write_tools_test.rb -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/services/decks/owned_copies_reallocator.rb app/mcp/reallocate_owned_copies_tool.rb app/controllers/mcp/server_controller.rb test/services/decks/owned_copies_reallocator_test.rb test/mcp/write_tools_test.rb
git commit -m "feat: add reallocate_owned_copies service and MCP tool"
```

---

### Task 8: `Decks::DeckCardQuantitySetter` + `set_deck_card_quantity` tool

**Files:**
- Create: `app/services/decks/deck_card_quantity_setter.rb`
- Create: `app/mcp/set_deck_card_quantity_tool.rb`
- Modify: `app/controllers/mcp/server_controller.rb`
- Test: `test/services/decks/deck_card_quantity_setter_test.rb`, `test/mcp/write_tools_test.rb`

**Interfaces:**
- Produces: `Decks::DeckCardQuantitySetter.call(deck:, card:, quantity:)` → the saved `DeckCard`, or `nil` when `quantity <= 0` (the row is removed). Sets the deck_card total; recaps `owned_copies` to `min(owned_copies, quantity)`. Does not auto-bump reals (unlike `CardAdder`). `SetDeckCardQuantityTool.call(deck_id:, card_id:, quantity:, server_context:)`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/decks/deck_card_quantity_setter_test.rb`:

```ruby
require "test_helper"

module Decks
  class DeckCardQuantitySetterTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @card = cards(:honedge)
      @user.collections.find_or_create_by!(card: @card).update!(quantity: 3)
      @deck = @user.decks.create!(name: "A", physical: true)
      @deck.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)
    end

    test "reducing quantity below owned_copies recaps the reals" do
      dc = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 2)
      assert_equal 2, dc.quantity
      assert_equal 2, dc.owned_copies
    end

    test "setting quantity to 0 removes the deck_card" do
      result = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 0)
      assert_nil result
      assert_nil @deck.deck_cards.find_by(card: @card)
    end

    test "does not auto-bump reals when increasing quantity" do
      dc = Decks::DeckCardQuantitySetter.call(deck: @deck, card: @card, quantity: 6)
      assert_equal 6, dc.quantity
      assert_equal 3, dc.owned_copies # unchanged, no greedy backing
    end
  end
end
```

Add to `test/mcp/write_tools_test.rb`:

```ruby
  test "SetDeckCardQuantityTool removes the card when quantity is 0" do
    physical = @user.decks.create!(name: "Phys", physical: true)
    physical.deck_cards.create!(card: @card, quantity: 2)

    SetDeckCardQuantityTool.call(deck_id: physical.id, card_id: @card.id, quantity: 0, server_context: @context)

    assert_nil physical.deck_cards.find_by(card: @card)
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/decks/deck_card_quantity_setter_test.rb test/mcp/write_tools_test.rb -v`
Expected: FAIL — constants missing.

- [ ] **Step 3: Write the service**

Create `app/services/decks/deck_card_quantity_setter.rb`:

```ruby
module Decks
  # Sets the total quantity of a card in a deck. quantity <= 0 removes the card.
  # Real copies are recapped to the new total but never auto-increased (use
  # Decks::CardAdder for greedy backing).
  class DeckCardQuantitySetter < ApplicationService
    def initialize(deck:, card:, quantity:)
      @deck = deck
      @card = card
      @quantity = quantity
    end

    def call
      deck_card = @deck.deck_cards.find_by(card: @card)

      if @quantity.to_i <= 0
        deck_card&.destroy!
        return nil
      end

      deck_card ||= @deck.deck_cards.build(card: @card)
      deck_card.quantity = @quantity
      deck_card.owned_copies = [ deck_card.owned_copies.to_i, @quantity ].min
      deck_card.save!
      deck_card
    end
  end
end
```

- [ ] **Step 4: Write the MCP tool**

Create `app/mcp/set_deck_card_quantity_tool.rb`:

```ruby
class SetDeckCardQuantityTool < McpTool
  description "Set the total number of copies of a card in a deck (proxies included). 0 removes the card. Real copies are recapped to the new total but never auto-increased."
  input_schema(
    properties: {
      deck_id: { type: "integer", description: "ID of the user's deck" },
      card_id: { type: "integer", description: "ID of the card" },
      quantity: { type: "integer", minimum: 0, description: "New total copies (0 removes the card)" }
    },
    required: [ "deck_id", "card_id", "quantity" ]
  )

  def self.call(deck_id:, card_id:, quantity:, server_context:)
    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    card = find_card!(card_id)
    deck_card = Decks::DeckCardQuantitySetter.call(deck: deck, card: card, quantity: quantity)
    if deck_card.nil?
      text("Removed #{card.name} from deck “#{deck.name}”.")
    else
      text("#{card.name} in deck “#{deck.name}”: total #{deck_card.quantity} (#{deck_card.owned_copies} real).")
    end
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck id #{deck_id} or card id #{card_id} (deck must belong to you).")
  rescue ActiveRecord::RecordInvalid => e
    text("Error: #{e.message}")
  end
end
```

- [ ] **Step 5: Register the tool**

In `app/controllers/mcp/server_controller.rb`, add `SetDeckCardQuantityTool,` to `TOOLS`.

- [ ] **Step 6: Run tests to verify they pass**

Run: `bin/rails test test/services/decks/deck_card_quantity_setter_test.rb test/mcp/write_tools_test.rb -v`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/services/decks/deck_card_quantity_setter.rb app/mcp/set_deck_card_quantity_tool.rb app/controllers/mcp/server_controller.rb test/services/decks/deck_card_quantity_setter_test.rb test/mcp/write_tools_test.rb
git commit -m "feat: add set_deck_card_quantity service and MCP tool"
```

---

### Task 9: Over-allocation report + extended read tools

**Files:**
- Create: `app/services/allocations/over_allocations.rb`
- Create: `app/mcp/list_over_allocations_tool.rb`
- Modify: `app/mcp/list_collection_tool.rb`, `app/mcp/list_deck_cards_tool.rb`, `app/mcp/list_decks_tool.rb`
- Modify: `app/controllers/mcp/server_controller.rb`
- Test: `test/services/allocations/over_allocations_test.rb`, `test/mcp/read_tools_test.rb`

**Interfaces:**
- Consumes: `Allocations::Availability` (Task 2).
- Produces: `Allocations::OverAllocations.call(user:)` → array of `{ card_id:, owned:, committed:, decks: [{id:, name:}] }` for each card where `committed > owned`. `ListOverAllocationsTool`. Extended read tools: `list_collection` → `{card_id, name, owned, committed, available}`; `list_deck_cards` → `{card_id, name, quantity, owned_copies, proxies}`; `list_decks` → `{id, name, format, physical, tcg_live}`.

- [ ] **Step 1: Write the failing tests**

Create `test/services/allocations/over_allocations_test.rb`:

```ruby
require "test_helper"

module Allocations
  class OverAllocationsTest < ActiveSupport::TestCase
    test "reports cards committed beyond what is owned, with the decks involved" do
      user = users(:one)
      card = cards(:honedge)
      user.collections.find_or_create_by!(card: card).update!(quantity: 2)
      deck = user.decks.create!(name: "A", physical: true)
      deck.deck_cards.create!(card: card, quantity: 3, owned_copies: 3) # committed 3 > owned 2

      report = Allocations::OverAllocations.call(user: user)

      entry = report.find { |e| e[:card_id] == card.id }
      assert_equal 2, entry[:owned]
      assert_equal 3, entry[:committed]
      assert_equal [ deck.id ], entry[:decks].map { |d| d[:id] }
    end

    test "is empty when nothing is over-allocated" do
      user = users(:two)
      assert_empty Allocations::OverAllocations.call(user: user)
    end
  end
end
```

Add to `test/mcp/read_tools_test.rb` (inside `ReadToolsTest`, which already has `@user`, `@context`, and the `payload` helper):

```ruby
  test "ListDeckCardsTool exposes owned_copies and proxies" do
    physical = @user.decks.create!(name: "Phys", physical: true)
    @user.collections.find_or_create_by!(card: cards(:honedge)).update!(quantity: 1)
    physical.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 1)

    response = ListDeckCardsTool.call(deck_id: physical.id, server_context: @context)
    entry = payload(response).find { |c| c["card_id"] == cards(:honedge).id }

    assert_equal 3, entry["quantity"]
    assert_equal 1, entry["owned_copies"]
    assert_equal 2, entry["proxies"]
  end

  test "ListCollectionTool exposes owned, committed and available" do
    card = cards(:honedge)
    @user.collections.find_or_create_by!(card: card).update!(quantity: 3)
    deck = @user.decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: card, quantity: 2, owned_copies: 2)

    response = ListCollectionTool.call(server_context: @context)
    entry = payload(response).find { |c| c["card_id"] == card.id }

    assert_equal 3, entry["owned"]
    assert_equal 2, entry["committed"]
    assert_equal 1, entry["available"]
  end

  test "ListOverAllocationsTool reports over-committed cards" do
    card = cards(:honedge)
    @user.collections.find_or_create_by!(card: card).update!(quantity: 1)
    deck = @user.decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: card, quantity: 2, owned_copies: 2)

    response = ListOverAllocationsTool.call(server_context: @context)
    card_ids = payload(response).map { |e| e["card_id"] }

    assert_includes card_ids, card.id
  end
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/allocations/over_allocations_test.rb test/mcp/read_tools_test.rb -v`
Expected: FAIL — constants / new fields missing.

- [ ] **Step 3: Write the `OverAllocations` service**

Create `app/services/allocations/over_allocations.rb`:

```ruby
module Allocations
  # Lists cards whose real copies committed across the user's physical decks
  # exceed the number owned (only reachable via a collection decrease).
  class OverAllocations < ApplicationService
    def initialize(user:)
      @user = user
    end

    def call
      physical_deck_ids = @user.decks.where(physical: true).select(:id)
      committed_by_card = DeckCard.where(deck_id: physical_deck_ids).group(:card_id).sum(:owned_copies)

      committed_by_card.filter_map do |card_id, committed|
        owned = @user.collections.where(card_id: card_id).sum(:quantity)
        next if committed <= owned

        decks = @user.decks.where(physical: true)
                     .joins(:deck_cards)
                     .where(deck_cards: { card_id: card_id })
                     .where("deck_cards.owned_copies > 0")
                     .distinct
        { card_id: card_id, owned: owned, committed: committed, decks: decks.map { |d| { id: d.id, name: d.name } } }
      end
    end
  end
end
```

- [ ] **Step 4: Write the `ListOverAllocationsTool`**

Create `app/mcp/list_over_allocations_tool.rb`:

```ruby
class ListOverAllocationsTool < McpTool
  description "List cards whose real copies committed across physical decks exceed what the user owns (decks to review), with the decks involved."
  input_schema(properties: {}, required: [])

  def self.call(server_context:)
    user = current_user(server_context)
    text(Allocations::OverAllocations.call(user: user).to_json)
  end
end
```

- [ ] **Step 5: Extend the list read tools**

Replace the `entries`/`decks` mapping in `app/mcp/list_collection_tool.rb`'s `call` so each entry includes allocation figures:

```ruby
  def self.call(server_context:, query: nil)
    user = current_user(server_context)
    scope = user.collections.with_cards.includes(:card)
    entries = scope.filter_map do |collection|
      next if query.present? && !collection.card.name.downcase.include?(query.downcase)

      availability = Allocations::Availability.call(user: user, card: collection.card)
      {
        card_id: collection.card_id,
        name: collection.card.name,
        owned: availability.owned,
        committed: availability.committed,
        available: availability.available
      }
    end
    text(entries.to_json)
  end
```

Replace the mapping in `app/mcp/list_deck_cards_tool.rb`'s `call`:

```ruby
    entries = deck.deck_cards.includes(:card).map do |deck_card|
      {
        card_id: deck_card.card_id,
        name: deck_card.card.name,
        quantity: deck_card.quantity,
        owned_copies: deck_card.owned_copies,
        proxies: deck_card.quantity - deck_card.owned_copies
      }
    end
```

Replace the mapping in `app/mcp/list_decks_tool.rb`'s `call`:

```ruby
    decks = user.decks.map do |deck|
      { id: deck.id, name: deck.name, format: deck.format, physical: deck.physical, tcg_live: deck.tcg_live }
    end
```

- [ ] **Step 6: Register the tool**

In `app/controllers/mcp/server_controller.rb`, add `ListOverAllocationsTool,` to `TOOLS`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `bin/rails test test/services/allocations/over_allocations_test.rb test/mcp/read_tools_test.rb -v`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add app/services/allocations/over_allocations.rb app/mcp/list_over_allocations_tool.rb app/mcp/list_collection_tool.rb app/mcp/list_deck_cards_tool.rb app/mcp/list_decks_tool.rb app/controllers/mcp/server_controller.rb test/services/allocations/over_allocations_test.rb test/mcp/read_tools_test.rb
git commit -m "feat: surface allocation figures and over-allocations in MCP read tools"
```

---

### Task 10: Owned-equivalents advice (`suggest_owned_equivalents` + inline in `add_card_to_deck`)

**Files:**
- Create: `app/services/collections/owned_equivalents.rb`
- Create: `app/mcp/suggest_owned_equivalents_tool.rb`
- Modify: `app/mcp/add_card_to_deck_tool.rb`
- Modify: `app/controllers/mcp/server_controller.rb`
- Test: `test/services/collections/owned_equivalents_test.rb`, `test/mcp/read_tools_test.rb`, `test/mcp/write_tools_test.rb`
- Test fixtures: `test/fixtures/cards.yml` (may need a second equivalent printing — see note)

**Interfaces:**
- Consumes: `Allocations::Availability` (Task 2), `Card#fingerprint`.
- Produces: `Collections::OwnedEquivalents.call(user:, card:, excluding_card: false)` → array of `{ card_id:, set_name:, set_number:, rarity:, owned:, available: }` for every printing the user owns whose card shares `card.fingerprint`. Unordered; includes entries with `available: 0`. When `excluding_card: true`, the queried `card` itself is dropped (used for the inline add suggestion). Empty when the card has no fingerprint or the user owns no equivalent. `SuggestOwnedEquivalentsTool.call(card_id:, server_context:)`. `AddCardToDeckTool`'s response appends the suggestion when a physical add creates proxies and equivalents are owned.

- [ ] **Step 1: Write the failing tests**

Create `test/services/collections/owned_equivalents_test.rb`:

```ruby
require "test_helper"

module Collections
  class OwnedEquivalentsTest < ActiveSupport::TestCase
    setup do
      # budew_pre and budew_asc share fingerprint "budew_shared" in fixtures.
      @user = users(:one)
      @asc = cards(:budew_asc)
      @pre = cards(:budew_pre)
      @user.collections.find_or_create_by!(card: @pre).update!(quantity: 2)
    end

    test "lists owned printings sharing the fingerprint" do
      result = Collections::OwnedEquivalents.call(user: @user, card: @asc)
      card_ids = result.map { |e| e[:card_id] }

      assert_includes card_ids, @pre.id
      pre_entry = result.find { |e| e[:card_id] == @pre.id }
      assert_equal 2, pre_entry[:owned]
      assert_equal 2, pre_entry[:available]
    end

    test "excludes the queried card when excluding_card: true" do
      @user.collections.find_or_create_by!(card: @asc).update!(quantity: 1)

      result = Collections::OwnedEquivalents.call(user: @user, card: @asc, excluding_card: true)

      assert_not_includes result.map { |e| e[:card_id] }, @asc.id
      assert_includes result.map { |e| e[:card_id] }, @pre.id
    end

    test "is empty when no equivalent is owned" do
      other_user = users(:two)
      assert_empty Collections::OwnedEquivalents.call(user: other_user, card: @asc)
    end
  end
end
```

Add to `test/mcp/read_tools_test.rb`:

```ruby
  test "SuggestOwnedEquivalentsTool lists owned equivalent printings" do
    @user.collections.find_or_create_by!(card: cards(:budew_pre)).update!(quantity: 2)

    response = SuggestOwnedEquivalentsTool.call(card_id: cards(:budew_asc).id, server_context: @context)
    card_ids = payload(response).map { |e| e["card_id"] }

    assert_includes card_ids, cards(:budew_pre).id
  end
```

Add to `test/mcp/write_tools_test.rb`:

```ruby
  test "AddCardToDeckTool suggests owned equivalents when a physical add makes proxies" do
    physical = @user.decks.create!(name: "Phys", physical: true)
    # own an equivalent printing (budew_pre) but not the exact one (budew_asc)
    @user.collections.find_or_create_by!(card: cards(:budew_pre)).update!(quantity: 2)

    response = AddCardToDeckTool.call(deck_id: physical.id, card_id: cards(:budew_asc).id, quantity: 2, server_context: @context)

    assert_match(/equivalent/i, response_text(response))
    assert_match(/Budew/, response_text(response))
  end
```

> Note for the implementer: the two Budew fixtures (`budew_pre`, `budew_asc`) already share `fingerprint: budew_shared`. Confirm both have valid `set_name`/`set_number`/`rarity` (Pokémon cards need `hp`/`type_symbol`/`retreat_cost` to validate; check `test/fixtures/cards.yml` and fill any missing required fields so the fixtures load). No new fixture is required for these tests.

- [ ] **Step 2: Run tests to verify they fail**

Run: `bin/rails test test/services/collections/owned_equivalents_test.rb test/mcp/read_tools_test.rb test/mcp/write_tools_test.rb -v`
Expected: FAIL — constants missing / no suggestion appended.

- [ ] **Step 3: Write the `OwnedEquivalents` service**

Create `app/services/collections/owned_equivalents.rb`:

```ruby
module Collections
  # Owned printings physically interchangeable with the given card — i.e. sharing
  # its Card#fingerprint. Purely advisory: allocation is unaffected. Each entry
  # reports per-printing owned/available. Includes fully-committed printings
  # (available: 0). Unordered.
  class OwnedEquivalents < ApplicationService
    def initialize(user:, card:, excluding_card: false)
      @user = user
      @card = card
      @excluding_card = excluding_card
    end

    def call
      return [] if @card.fingerprint.blank?

      equivalent_ids = Card.where(fingerprint: @card.fingerprint).select(:id)
      collections = @user.collections.where(card_id: equivalent_ids).includes(:card)

      collections.filter_map do |collection|
        next if @excluding_card && collection.card_id == @card.id

        available = Allocations::Availability.call(user: @user, card: collection.card).available
        {
          card_id: collection.card_id,
          set_name: collection.card.set_name,
          set_number: collection.card.set_number,
          rarity: collection.card.rarity,
          owned: collection.quantity,
          available: available
        }
      end
    end
  end
end
```

- [ ] **Step 4: Write the `SuggestOwnedEquivalentsTool`**

Create `app/mcp/suggest_owned_equivalents_tool.rb`:

```ruby
class SuggestOwnedEquivalentsTool < McpTool
  description "List owned printings physically interchangeable with a given card (same fingerprint) — e.g. reprints and alternate arts — with per-printing owned and available counts. Advisory only."
  input_schema(
    properties: {
      card_id: { type: "integer", description: "ID of the card to find owned equivalents for" }
    },
    required: [ "card_id" ]
  )

  def self.call(card_id:, server_context:)
    user = current_user(server_context)
    card = find_card!(card_id)
    text(Collections::OwnedEquivalents.call(user: user, card: card).to_json)
  rescue ActiveRecord::RecordNotFound
    text("Error: no card with id #{card_id}.")
  end
end
```

- [ ] **Step 5: Append the inline suggestion in `add_card_to_deck`**

Replace `app/mcp/add_card_to_deck_tool.rb`'s `call` body so that, on a physical deck where proxies were created, it appends owned equivalents:

```ruby
  def self.call(deck_id:, card_id:, server_context:, quantity: 1)
    return quantity_error(quantity) unless positive_quantity?(quantity)

    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    card = find_card!(card_id)
    deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: quantity)
    message = "Added #{quantity}× #{card.name} to deck “#{deck.name}” (now #{deck_card.quantity}: #{deck_card.owned_copies} real, #{deck_card.quantity - deck_card.owned_copies} proxy)."
    message += equivalents_hint(user, card) if deck.physical? && deck_card.quantity > deck_card.owned_copies
    text(message)
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck id #{deck_id} or card id #{card_id} (deck must belong to you).")
  end

  def self.equivalents_hint(user, card)
    equivalents = Collections::OwnedEquivalents.call(user: user, card: card, excluding_card: true)
    return "" if equivalents.empty?

    " You own equivalent printings you could back real copies with instead: #{equivalents.to_json}"
  end
  private_class_method :equivalents_hint
```

- [ ] **Step 6: Register the tool**

In `app/controllers/mcp/server_controller.rb`, add `SuggestOwnedEquivalentsTool,` to `TOOLS`.

- [ ] **Step 7: Run tests to verify they pass**

Run: `bin/rails test test/services/collections/owned_equivalents_test.rb test/mcp/read_tools_test.rb test/mcp/write_tools_test.rb -v`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add app/services/collections/owned_equivalents.rb app/mcp/suggest_owned_equivalents_tool.rb app/mcp/add_card_to_deck_tool.rb app/controllers/mcp/server_controller.rb test/services/collections/owned_equivalents_test.rb test/mcp/read_tools_test.rb test/mcp/write_tools_test.rb
git commit -m "feat: suggest owned equivalent printings (advisory)"
```

---

### Task 11: Full verification (suite + lint + security)

**Files:** none (verification only).

- [ ] **Step 1: Full suite**

Run: `bin/rails db:test:prepare test`
Expected: PASS, 0 failures/errors.

- [ ] **Step 2: Lint**

Run: `bin/rubocop`
Expected: no offenses. Fix any style offenses in the new files and re-run.

- [ ] **Step 3: Security scan**

Run: `bin/brakeman --no-pager`
Expected: no new warnings.

- [ ] **Step 4: Commit any fixups**

```bash
git add -A
git commit -m "chore: satisfy rubocop and brakeman for allocation feature"
```

---

## Self-review notes

- **Spec coverage:** data model (Task 1); availability/invariant (Task 2); removal of old transfer (Task 3); `set_collection_quantity` incl. tolerated over-allocation on decrease (Task 4); physical auto-split on add + Kirlia A/B example (Task 5); `set_deck_card_owned_copies` with the no-over-allocation bound (Task 6); `reallocate_owned_copies` pure conversion (Task 7); `set_deck_card_quantity` set/remove/recap (Task 8); over-allocation report + extended `list_collection`/`list_deck_cards`/`list_decks` (Task 9); equivalence advisory tool + inline add suggestion (Task 10); full verification (Task 11). Medium-change release covered in Task 1; non-physical no-adossage covered across Tasks 2/5/6.
- **Type consistency:** `Allocations::Availability::Result#owned/#committed/#available` used consistently in Tasks 2, 5, 6, 9, 10; services return the saved record (or `nil` on removal); tools return `MCP::Tool::Response` via `text`; `Collections::OwnedEquivalents` entry shape identical in the tool and the inline hint.
- **Out of scope confirmed untouched:** web UI/API, `has_proxies` auto-derivation, foil-aware allocation, deck legality.
