# Surface the Allocation Model in Web UI & JSON API — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the collection↔deck allocation model (real/proxy per deck card, owned/committed/available per collection card, over-allocation) visible and controllable in the web UI and the `Api::` JSON endpoints, reusing existing services.

**Architecture:** Controllers and Phlex views stay thin — they delegate to the existing allocation services (`Allocations::Availability`, `Allocations::OverAllocations`, `Decks::CardAdder`/`OwnedCopiesSetter`/`DeckCardQuantitySetter`/`OwnedCopiesReallocator`, `Collections::CardAdder`/`QuantitySetter`) exactly as the MCP tools do. The only model addition is one derived reader (`DeckCard#proxies`).

**Tech Stack:** Rails 8.1, Ruby 3.4, SQLite, Phlex components, Hotwire (Stimulus), Minitest.

## Global Constraints

- All logic lives in services; controllers/views only call them. No business rules in controllers or Phlex components. (base design)
- Over-allocation (`committed > owned`) is **displayed, never blocked or auto-corrected**. (base design decision #5)
- Reuse existing services; do not reimplement allocation math.
- `Deck#has_proxies` is **not** touched (issue #56). Proxy state for display derives from `owned_copies`.
- Collection-index availability is computed per card (N+1) — acceptable this iteration (issue #59). Do not batch-optimise.
- Colour by energy type via `Card::TYPE_TOKENS`, never literal hexes. New UI reuses existing CSS classes/tokens.
- French UI copy (matches the existing app and the approved spec previews).
- Card identity is `card_id` (printing); `collections.foil` stays ignored.

---

### Task 1: `DeckCard#proxies` derived reader

**Files:**
- Modify: `app/models/deck_card.rb`
- Test: `test/models/deck_card_test.rb`

**Interfaces:**
- Produces: `DeckCard#proxies -> Integer` (`quantity − owned_copies`), used by every deck-card JSON helper and by `Decks::DeckCardItem`.

- [ ] **Step 1: Write the failing test**

Append to `test/models/deck_card_test.rb` (inside the class):

```ruby
test "proxies is quantity minus owned_copies" do
  deck = users(:one).decks.create!(name: "Phys", physical: true)
  dc = deck.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 1)
  assert_equal 2, dc.proxies
end

test "proxies is zero when fully backed" do
  deck = users(:one).decks.create!(name: "Phys", physical: true)
  dc = deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)
  assert_equal 0, dc.proxies
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/models/deck_card_test.rb`
Expected: FAIL with `NoMethodError: undefined method 'proxies'`.

- [ ] **Step 3: Add the method**

In `app/models/deck_card.rb`, add a public method (near the top of the class body, after the associations/validations):

```ruby
# Copies in this deck not backed by an owned card. Derived, never stored.
def proxies
  quantity.to_i - owned_copies.to_i
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/models/deck_card_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/models/deck_card.rb test/models/deck_card_test.rb
git commit -m "feat: add DeckCard#proxies derived reader (#55)"
```

---

### Task 2: `Api::DeckCardsController` — expose allocation, route through services

**Files:**
- Modify: `app/controllers/api/deck_cards_controller.rb`
- Test: `test/controllers/api/deck_cards_controller_test.rb` (create)

**Interfaces:**
- Consumes: `DeckCard#proxies` (Task 1); `Decks::CardAdder.call(deck:, card:, quantity:)`, `Decks::DeckCardQuantitySetter.call(deck:, card:, quantity:)` (returns `nil` when quantity ≤ 0 → card removed), `Decks::OwnedCopiesSetter.call(deck:, card:, owned_copies:)` (raises `ArgumentError` / `Decks::OwnedCopiesSetter::NotPhysicalError`).
- Produces: `deck_card_json` now includes `owned_copies` and `proxies`. `create`/`update` behaviour: adding to a physical deck greedily backs reals; `owned_copies` can be set via `update`.

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/api/deck_cards_controller_test.rb`:

```ruby
require "test_helper"

class Api::DeckCardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @card = cards(:honedge)
    @user.collections.create!(card: @card, quantity: 3)
    @deck = @user.decks.create!(name: "Phys", physical: true)
  end

  test "deck_card_json includes owned_copies and proxies" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 2)

    get api_deck_cards_path(@deck)

    json = JSON.parse(response.body)
    row = json.find { |r| r["card"]["id"] == @card.id }
    assert_equal 2, row["owned_copies"]
    assert_equal 1, row["proxies"]
  end

  test "create on a physical deck greedily backs reals via CardAdder" do
    post api_deck_cards_path(@deck),
      params: { deck_card: { card_id: @card.id, quantity: 2 } }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 2, json["quantity"]
    assert_equal 2, json["owned_copies"], "should back 2 reals from the 3 owned"
    assert_equal 0, json["proxies"]
  end

  test "update owned_copies routes through OwnedCopiesSetter" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { owned_copies: 1 } }, as: :json

    assert_response :success
    assert_equal 1, JSON.parse(response.body)["owned_copies"]
  end

  test "update owned_copies beyond availability returns 422" do
    @deck.deck_cards.create!(card: @card, quantity: 5, owned_copies: 0)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { owned_copies: 5 } }, as: :json

    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].present?
  end

  test "update quantity routes through DeckCardQuantitySetter and can remove" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 2)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { quantity: 0 } }, as: :json

    assert_response :no_content
    assert_nil @deck.deck_cards.find_by(card: @card)
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/controllers/api/deck_cards_controller_test.rb`
Expected: FAIL (owned_copies missing from JSON / create leaves owned_copies at 0).

- [ ] **Step 3: Rewrite the controller**

Replace `app/controllers/api/deck_cards_controller.rb` with:

```ruby
module Api
  class DeckCardsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_deck

    def index
      deck_cards = @deck.deck_cards.includes(:card)
      render json: deck_cards.map { |dc| deck_card_json(dc) }
    end

    def create
      card = Card.find(deck_card_params[:card_id])
      deck_card = Decks::CardAdder.call(deck: @deck, card: card, quantity: deck_card_params[:quantity].to_i)
      render json: deck_card_json(deck_card), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def update
      card = Card.find(params[:id])

      if deck_card_params.key?(:owned_copies)
        deck_card = Decks::OwnedCopiesSetter.call(deck: @deck, card: card, owned_copies: deck_card_params[:owned_copies].to_i)
        render json: deck_card_json(deck_card)
      else
        deck_card = Decks::DeckCardQuantitySetter.call(deck: @deck, card: card, quantity: deck_card_params[:quantity].to_i)
        if deck_card.nil?
          head :no_content
        else
          render json: deck_card_json(deck_card)
        end
      end
    rescue ArgumentError, Decks::OwnedCopiesSetter::NotPhysicalError => e
      render json: { errors: [ e.message ] }, status: :unprocessable_entity
    end

    def destroy
      deck_card = @deck.deck_cards.find_by!(card_id: params[:id])
      deck_card.destroy
      head :no_content
    end

    private

    def set_deck
      @deck = current_user.decks.find(params[:deck_id])
    end

    def deck_card_params
      params.require(:deck_card).permit(:card_id, :quantity, :owned_copies)
    end

    def deck_card_json(deck_card)
      {
        id: deck_card.id,
        quantity: deck_card.quantity,
        owned_copies: deck_card.owned_copies,
        proxies: deck_card.proxies,
        card: {
          id: deck_card.card.id,
          name: deck_card.card.name,
          card_type: deck_card.card.card_type,
          set_name: deck_card.card.set_name,
          set_number: deck_card.card.set_number,
          rarity: deck_card.card.rarity,
          hp: deck_card.card.hp,
          type_symbol: deck_card.card.type_symbol
        }
      }
    end
  end
end
```

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/controllers/api/deck_cards_controller_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/deck_cards_controller.rb test/controllers/api/deck_cards_controller_test.rb
git commit -m "feat: expose owned_copies/proxies and route deck-card writes through services (#55)"
```

---

### Task 3: `Api::CollectionsController` — expose availability, route through services

**Files:**
- Modify: `app/controllers/api/collections_controller.rb`
- Test: `test/controllers/api/collections_controller_test.rb` (create)

**Interfaces:**
- Consumes: `Allocations::Availability.call(user:, card:) -> Result(owned, committed, available)`; `Collections::CardAdder.call(user:, card:, quantity:)`, `Collections::QuantitySetter.call(user:, card:, quantity:)`.
- Produces: `collection_json` now includes `owned`, `committed`, `available`.

- [ ] **Step 1: Write the failing tests**

Create `test/controllers/api/collections_controller_test.rb`:

```ruby
require "test_helper"

class Api::CollectionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @card = cards(:honedge)
  end

  test "collection_json includes owned/committed/available" do
    @user.collections.create!(card: @card, quantity: 4)
    deck = @user.decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    get api_collections_path

    json = JSON.parse(response.body)
    row = json["collections"].find { |c| c["card_id"] == @card.id }
    assert_equal 4, row["owned"]
    assert_equal 2, row["committed"]
    assert_equal 2, row["available"]
  end

  test "create routes through Collections::CardAdder (additive)" do
    @user.collections.create!(card: @card, quantity: 1)

    post api_collections_path,
      params: { collection: { card_id: @card.id, quantity: 2 } }, as: :json

    assert_response :created
    assert_equal 3, JSON.parse(response.body)["quantity"]
  end

  test "update sets exact quantity via QuantitySetter" do
    @user.collections.create!(card: @card, quantity: 5)

    patch api_collection_path(@card),
      params: { collection: { quantity: 2 } }, as: :json

    assert_response :success
    assert_equal 2, JSON.parse(response.body)["quantity"]
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/controllers/api/collections_controller_test.rb`
Expected: FAIL (owned/committed/available missing).

- [ ] **Step 3: Rewrite the controller**

Replace `app/controllers/api/collections_controller.rb` with:

```ruby
module Api
  class CollectionsController < ApplicationController
    before_action :authenticate_user!

    def index
      collections = current_user.collections.includes(:card).load
      total_cards = collections.sum(&:quantity)

      render json: {
        collections: collections.map { |c| collection_json(c) },
        total_cards: total_cards
      }
    end

    def create
      card = Card.find(collection_params[:card_id])
      collection = Collections::CardAdder.call(user: current_user, card: card, quantity: collection_params[:quantity].to_i)
      render json: collection_json(collection), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def update
      card = Card.find(params[:id])
      collection = Collections::QuantitySetter.call(user: current_user, card: card, quantity: collection_params[:quantity].to_i)
      render json: collection_json(collection)
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def destroy
      collection = current_user.collections.find_by!(card_id: params[:id])
      collection.destroy
      head :no_content
    end

    private

    def collection_params
      params.require(:collection).permit(:card_id, :quantity)
    end

    def collection_json(collection)
      availability = Allocations::Availability.call(user: current_user, card: collection.card)
      {
        id: collection.id,
        card_id: collection.card_id,
        quantity: collection.quantity,
        owned: availability.owned,
        committed: availability.committed,
        available: availability.available,
        card: {
          name: collection.card.name,
          card_type: collection.card.card_type,
          set_name: collection.card.set_name,
          set_number: collection.card.set_number,
          rarity: collection.card.rarity,
          hp: collection.card.hp,
          type_symbol: collection.card.type_symbol
        }
      }
    end
  end
end
```

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/controllers/api/collections_controller_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/collections_controller.rb test/controllers/api/collections_controller_test.rb
git commit -m "feat: expose owned/committed/available and route collection writes through services (#55)"
```

---

### Task 4: `Api::DecksController` — add physical/tcg_live and per-card allocation

**Files:**
- Modify: `app/controllers/api/decks_controller.rb`
- Test: `test/controllers/api/decks_controller_test.rb` (append)

**Interfaces:**
- Consumes: `DeckCard#proxies` (Task 1).
- Produces: `deck_json` gains `physical`, `tcg_live`; its nested `deck_card_json` gains `owned_copies`, `proxies`.

- [ ] **Step 1: Write the failing test**

Append to `test/controllers/api/decks_controller_test.rb` (inside the class):

```ruby
test "deck_json includes physical, tcg_live and per-card allocation" do
  deck = @user.decks.create!(name: "Phys", physical: true, tcg_live: false)
  deck.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 2)

  get api_deck_path(deck)

  json = JSON.parse(response.body)
  assert_equal true, json["physical"]
  assert_equal false, json["tcg_live"]
  card_row = json["cards"].first
  assert_equal 2, card_row["owned_copies"]
  assert_equal 1, card_row["proxies"]
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/controllers/api/decks_controller_test.rb`
Expected: FAIL (keys missing).

- [ ] **Step 3: Extend the JSON helpers**

In `app/controllers/api/decks_controller.rb`, replace the two helper methods `deck_json` and `deck_card_json` with:

```ruby
    def deck_json(deck)
      {
        id: deck.id,
        name: deck.name,
        description: deck.description,
        physical: deck.physical,
        tcg_live: deck.tcg_live,
        cards: deck.deck_cards.map { |dc| deck_card_json(dc) }
      }
    end

    def deck_card_json(deck_card)
      {
        id: deck_card.id,
        quantity: deck_card.quantity,
        owned_copies: deck_card.owned_copies,
        proxies: deck_card.proxies,
        card: {
          id: deck_card.card.id,
          name: deck_card.card.name,
          card_type: deck_card.card.card_type,
          set_name: deck_card.card.set_name,
          set_number: deck_card.card.set_number,
          rarity: deck_card.card.rarity,
          hp: deck_card.card.hp,
          type_symbol: deck_card.card.type_symbol
        }
      }
    end
```

- [ ] **Step 4: Run to verify pass**

Run: `bin/rails test test/controllers/api/decks_controller_test.rb`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/controllers/api/decks_controller.rb test/controllers/api/decks_controller_test.rb
git commit -m "feat: add physical/tcg_live and per-card allocation to deck JSON (#55)"
```

---

### Task 5: Deck show — real/proxy badge, owned_copies stepper, over-allocated marker

**Files:**
- Modify: `app/controllers/decks_controller.rb` (`show`)
- Modify: `app/views/components/decks/show_view.rb`
- Modify: `app/views/components/decks/deck_card_item.rb`
- Create: `app/javascript/controllers/deck_card_owned_copies_controller.js`
- Modify: `app/assets/stylesheets/application.css` (append small styles)
- Test: `test/integration/allocation_ui_test.rb` (create)

**Interfaces:**
- Consumes: `Allocations::Availability` (per deck card, `excluding_deck: @deck`), `Allocations::OverAllocations`, `DeckCard#proxies`.
- Produces: `Decks::DeckCardItem.new(deck_card:, deck_id:, physical: false, max_owned: 0, over_allocated: false)`; `Decks::ShowView.new(deck:, editing:, tournament_profiles:, availability: {}, over_allocated_card_ids: [])` where `availability` maps `card_id -> Allocations::Availability::Result`.

- [ ] **Step 1: Write the failing test**

Create `test/integration/allocation_ui_test.rb`:

```ruby
require "test_helper"

class AllocationUiTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @card = cards(:honedge)
  end

  test "deck show renders real/proxy split and owned_copies stepper on physical decks" do
    @user.collections.create!(card: @card, quantity: 3)
    deck = @user.decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 2)

    get deck_path(deck)

    assert_response :success
    assert_select ".deck-card-alloc", /2 réelles/
    assert_select "[data-controller~=deck-card-owned-copies]"
  end

  test "deck show flags an over-allocated card" do
    @user.collections.create!(card: @card, quantity: 1)
    deck = @user.decks.create!(name: "Phys", physical: true)
    # committed 2 > owned 1 → over-allocated
    deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    get deck_path(deck)

    assert_select ".deck-card-warning"
  end
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/integration/allocation_ui_test.rb`
Expected: FAIL (no `.deck-card-alloc` / stepper).

- [ ] **Step 3: Compute allocation data in the controller**

In `app/controllers/decks_controller.rb`, replace the `show` action with:

```ruby
  def show
    @deck = current_user.decks.includes(:archetype, deck_cards: :card, deck_results: []).find(params[:id])
    @tournament_profiles = current_user.tournament_profiles.order(:player_name)
    @editing = false

    if @deck.physical?
      @availability = @deck.deck_cards.to_h do |dc|
        [ dc.card_id, Allocations::Availability.call(user: current_user, card: dc.card, excluding_deck: @deck) ]
      end
      @over_allocated_card_ids = Allocations::OverAllocations.call(user: current_user).map { |o| o[:card_id] }.to_set
    else
      @availability = {}
      @over_allocated_card_ids = Set.new
    end
  end
```

Now update the show view render. Find `app/views/decks/show.html.erb` and pass the new locals. Replace its `render` call so it reads:

```erb
<%= render Decks::ShowView.new(
  deck: @deck,
  editing: @editing,
  tournament_profiles: @tournament_profiles,
  availability: @availability,
  over_allocated_card_ids: @over_allocated_card_ids
) %>
```

- [ ] **Step 4: Thread the data through `ShowView`**

In `app/views/components/decks/show_view.rb`, change the constructor:

```ruby
    def initialize(deck:, editing: false, tournament_profiles: [], availability: {}, over_allocated_card_ids: [])
      @deck = deck
      @editing = editing
      @tournament_profiles = tournament_profiles
      @availability = availability
      @over_allocated_card_ids = over_allocated_card_ids.to_set
    end
```

Replace the `card_list` method with:

```ruby
    def card_list(group)
      ul(class: "deck-card-list") do
        group.sort_by { |dc| dc.card.name }.each do |dc|
          availability = @availability[dc.card_id]
          max_owned = availability ? [ dc.quantity, availability.available ].min : 0
          render Decks::DeckCardItem.new(
            deck_card: dc,
            deck_id: @deck.id,
            physical: @deck.physical?,
            max_owned: max_owned,
            over_allocated: @over_allocated_card_ids.include?(dc.card_id)
          )
        end
      end
    end
```

- [ ] **Step 5: Render the badge + stepper + marker in `DeckCardItem`**

Replace `app/views/components/decks/deck_card_item.rb` with:

```ruby
module Decks
  class DeckCardItem < ApplicationComponent
    def initialize(deck_card:, deck_id:, physical: false, max_owned: 0, over_allocated: false)
      @deck_card = deck_card
      @deck_id = deck_id
      @physical = physical
      @max_owned = max_owned
      @over_allocated = over_allocated
    end

    def view_template
      li(
        class: "deck-card-item",
        data: {
          card_preview_url: card.image_url.present? ? image_card_path(card) : nil,
          card_preview_card_id: card.id,
          action: "mouseenter->card-preview#show click->card-preview#open",
          controller: "deck-card-quantity",
          deck_card_quantity_deck_id_value: @deck_id,
          deck_card_quantity_card_id_value: card.id,
          deck_card_quantity_quantity_value: @deck_card.quantity
        }
      ) do
        div(class: "deck-card-qty-controls") do
          button(class: "qty-btn", data: { action: "deck-card-quantity#decrement" }) { "-" }
          span(class: "deck-card-qty") { @deck_card.quantity.to_s }
          button(class: "qty-btn", data: { action: "deck-card-quantity#increment" }) { "+" }
        end
        span(class: "deck-card-name") { card.name }
        span(class: "deck-card-set") { "#{card.set_name} #{card.set_number}" }
        allocation_controls if @physical
      end
    end

    private

    def card = @deck_card.card

    # Real/proxy split, a stepper to adjust owned_copies (bounded 0..max_owned),
    # and an over-allocation marker. Physical decks only.
    def allocation_controls
      div(
        class: "deck-card-alloc",
        data: {
          controller: "deck-card-owned-copies",
          deck_card_owned_copies_deck_id_value: @deck_id,
          deck_card_owned_copies_card_id_value: card.id,
          deck_card_owned_copies_owned_value: @deck_card.owned_copies,
          deck_card_owned_copies_max_value: @max_owned
        }
      ) do
        button(class: "qty-btn", data: { action: "deck-card-owned-copies#decrement" }) { "−" }
        span(class: "deck-card-alloc-label", data: { deck_card_owned_copies_target: "label" }) { alloc_label }
        button(class: "qty-btn", data: { action: "deck-card-owned-copies#increment" }) { "+" }
        span(class: "deck-card-warning badge badge-warning") { "⚠ sur-allouée" } if @over_allocated
      end
    end

    def alloc_label
      "#{@deck_card.owned_copies} réelles · #{@deck_card.proxies} proxy"
    end
  end
end
```

- [ ] **Step 6: Write the Stimulus controller**

Create `app/javascript/controllers/deck_card_owned_copies_controller.js`:

```javascript
import { Controller } from "@hotwired/stimulus"

// Adjusts a deck card's real (owned-backed) copy count via the deck-card API.
export default class extends Controller {
  static targets = ["label"]
  static values = { deckId: Number, cardId: Number, owned: Number, max: Number }

  increment() {
    if (this.ownedValue >= this.maxValue) return
    this.#update(this.ownedValue + 1)
  }

  decrement() {
    if (this.ownedValue <= 0) return
    this.#update(this.ownedValue - 1)
  }

  async #update(newOwned) {
    const token = document.querySelector('meta[name="csrf-token"]').content
    const response = await fetch(`/api/decks/${this.deckIdValue}/cards/${this.cardIdValue}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      credentials: "same-origin",
      body: JSON.stringify({ deck_card: { owned_copies: newOwned } })
    })
    if (!response.ok) return

    const data = await response.json()
    this.ownedValue = data.owned_copies
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = `${data.owned_copies} réelles · ${data.proxies} proxy`
    }
  }
}
```

- [ ] **Step 7: Add minimal styles**

Append to `app/assets/stylesheets/application.css`:

```css
.deck-card-alloc { display: inline-flex; align-items: center; gap: 0.375rem; margin-left: 0.5rem; font: var(--font-mono, monospace); font-size: 0.75rem; color: var(--text-muted, #666); }
.deck-card-alloc-label { min-width: 8ch; text-align: center; }
.deck-card-warning { margin-left: 0.25rem; }
```

- [ ] **Step 8: Run to verify pass**

Run: `bin/rails test test/integration/allocation_ui_test.rb`
Expected: PASS (both tests).

- [ ] **Step 9: Commit**

```bash
git add app/controllers/decks_controller.rb app/views/decks/show.html.erb app/views/components/decks/show_view.rb app/views/components/decks/deck_card_item.rb app/javascript/controllers/deck_card_owned_copies_controller.js app/assets/stylesheets/application.css test/integration/allocation_ui_test.rb
git commit -m "feat: surface real/proxy split and owned_copies stepper on deck show (#55)"
```

---

### Task 6: Collection tile — owned/committed/available line

**Files:**
- Modify: `app/controllers/collections_controller.rb` (`index`)
- Modify: `app/views/components/collections/index_view.rb`
- Modify: `app/assets/stylesheets/application.css` (append)
- Test: `test/integration/allocation_ui_test.rb` (append)

**Interfaces:**
- Consumes: `Allocations::Availability` per collection card.
- Produces: `Collections::IndexView.new(...)` gains `availability: {}` (map `card_id -> Result`). Existing callers must pass it.

- [ ] **Step 1: Write the failing test**

Append to `test/integration/allocation_ui_test.rb` (inside the class):

```ruby
test "collection tile shows owned/committed/available" do
  @user.collections.create!(card: @card, quantity: 4)
  deck = @user.decks.create!(name: "Phys", physical: true)
  deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

  get collections_path

  assert_response :success
  assert_select ".collection-tile-alloc", /poss\. 4/
  assert_select ".collection-tile-alloc", /engagé 2/
  assert_select ".collection-tile-alloc", /dispo 2/
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/integration/allocation_ui_test.rb -n /collection tile/`
Expected: FAIL (`.collection-tile-alloc` absent).

- [ ] **Step 3: Compute availability in the controller**

In `app/controllers/collections_controller.rb`, at the end of `index` (after `@total_copies = ...`), add:

```ruby
    @availability = @collections.to_h do |c|
      [ c.card_id, Allocations::Availability.call(user: current_user, card: c.card) ]
    end
```

Find `app/views/collections/index.html.erb` and add `availability: @availability` to the `Collections::IndexView.new(...)` render call.

- [ ] **Step 4: Add the line to the tile**

In `app/views/components/collections/index_view.rb`, update the constructor to accept `availability:` and store it. The current constructor takes keyword args (`collections:`, `card_sets:`, etc.) — add `availability: {}` to the signature and `@availability = availability` to the body.

Then, inside `collection_tile`, after the `link_to ... end` block and before `div(class: "collection-tile-controls")`, insert:

```ruby
        if (a = @availability[card.id])
          span(class: "collection-tile-alloc") { "poss. #{a.owned} · engagé #{a.committed} · dispo #{a.available}" }
        end
```

- [ ] **Step 5: Add minimal styles**

Append to `app/assets/stylesheets/application.css`:

```css
.collection-tile-alloc { display: block; font: var(--font-mono, monospace); font-size: 0.7rem; color: var(--text-muted, #666); margin: 0.25rem 0; }
```

- [ ] **Step 6: Run to verify pass**

Run: `bin/rails test test/integration/allocation_ui_test.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add app/controllers/collections_controller.rb app/views/collections/index.html.erb app/views/components/collections/index_view.rb app/assets/stylesheets/application.css test/integration/allocation_ui_test.rb
git commit -m "feat: show owned/committed/available on collection tiles (#55)"
```

---

### Task 7: Over-allocations page

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/over_allocations_controller.rb`
- Create: `app/views/over_allocations/index.html.erb`
- Create: `app/views/components/over_allocations/index_view.rb`
- Test: `test/integration/allocation_ui_test.rb` (append)

**Interfaces:**
- Consumes: `Allocations::OverAllocations.call(user:) -> [{card_id:, owned:, committed:, decks: [{id:, name:}]}]`.
- Produces: route `over_allocations_path`; `OverAllocations::IndexView.new(over_allocations:, cards_by_id:)` where `cards_by_id` maps `card_id -> Card`.

- [ ] **Step 1: Write the failing test**

Append to `test/integration/allocation_ui_test.rb`:

```ruby
test "over_allocations page lists over-allocated cards and contributing decks" do
  @user.collections.create!(card: @card, quantity: 1)
  deck = @user.decks.create!(name: "Contrib", physical: true)
  deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

  get over_allocations_path

  assert_response :success
  assert_select ".over-allocation-row", 1
  assert_select ".over-allocation-row", /#{@card.name}/
  assert_select ".over-allocation-row", /Contrib/
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/integration/allocation_ui_test.rb -n /over_allocations page/`
Expected: FAIL (`over_allocations_path` undefined).

- [ ] **Step 3: Add the route**

In `config/routes.rb`, inside the `authenticate :user do` block, next to `resources :collections`, add:

```ruby
    resources :over_allocations, only: [ :index ]
```

- [ ] **Step 4: Create the controller**

Create `app/controllers/over_allocations_controller.rb`:

```ruby
class OverAllocationsController < ApplicationController
  def index
    @over_allocations = Allocations::OverAllocations.call(user: current_user)
    @cards_by_id = Card.where(id: @over_allocations.map { |o| o[:card_id] }).index_by(&:id)
  end
end
```

- [ ] **Step 5: Create the view + component**

Create `app/views/over_allocations/index.html.erb`:

```erb
<%= render OverAllocations::IndexView.new(over_allocations: @over_allocations, cards_by_id: @cards_by_id) %>
```

Create `app/views/components/over_allocations/index_view.rb`:

```ruby
module OverAllocations
  class IndexView < ApplicationComponent
    def initialize(over_allocations:, cards_by_id:)
      @over_allocations = over_allocations
      @cards_by_id = cards_by_id
    end

    def view_template
      div(class: "over-allocations-container") do
        h1 { "Cartes sur-allouées" }

        if @over_allocations.empty?
          p(class: "over-allocations-empty") { "Aucune sur-allocation. Tout est équilibré." }
        else
          div(class: "over-allocation-list") do
            @over_allocations.each { |over| row(over) }
          end
        end
      end
    end

    private

    def row(over)
      card = @cards_by_id[over[:card_id]]
      div(class: "over-allocation-row") do
        span(class: "over-allocation-card") { card&.name.to_s }
        span(class: "over-allocation-counts") { "possédées #{over[:owned]} · engagées #{over[:committed]}" }
        div(class: "over-allocation-decks") do
          over[:decks].each do |d|
            link_to d[:name], deck_path(d[:id]), class: "over-allocation-deck-link"
          end
        end
      end
    end
  end
end
```

- [ ] **Step 6: Run to verify pass**

Run: `bin/rails test test/integration/allocation_ui_test.rb -n /over_allocations page/`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add config/routes.rb app/controllers/over_allocations_controller.rb app/views/over_allocations/index.html.erb app/views/components/over_allocations/index_view.rb test/integration/allocation_ui_test.rb
git commit -m "feat: add over-allocations page (#55)"
```

---

### Task 8: "To review" badge + over-allocation banner

**Files:**
- Modify: `app/views/components/decks/classification_badges.rb`
- Modify: `app/views/components/decks/deck_card.rb` (list tile)
- Modify: `app/views/components/decks/index_view.rb`
- Modify: `app/controllers/decks_controller.rb` (`index`)
- Modify: `app/controllers/collections_controller.rb` (`index`)
- Modify: `app/views/components/collections/index_view.rb`
- Create: `app/views/components/allocations/over_allocation_banner.rb`
- Modify: `app/assets/stylesheets/application.css` (append)
- Test: `test/integration/allocation_ui_test.rb` (append)

**Interfaces:**
- Consumes: `Allocations::OverAllocations`.
- Produces: `Decks::ClassificationBadges.new(deck:, over_allocated: false)`; `Decks::DeckCard.new(deck:, with_actions: true, over_allocated: false)`; `Decks::IndexView.new(..., over_allocated_deck_ids: [])`; `Collections::IndexView.new(..., over_allocation_count: 0)`; `Allocations::OverAllocationBanner.new(count:)`.

- [ ] **Step 1: Write the failing tests**

Append to `test/integration/allocation_ui_test.rb`:

```ruby
test "deck list shows a to-review badge and banner when over-allocated" do
  @user.collections.create!(card: @card, quantity: 1)
  deck = @user.decks.create!(name: "Contrib", physical: true)
  deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

  get decks_path

  assert_response :success
  assert_select ".badge-warning", /À revoir/
  assert_select ".over-allocation-banner"
end

test "collections page shows the banner when over-allocated" do
  @user.collections.create!(card: @card, quantity: 1)
  deck = @user.decks.create!(name: "Contrib", physical: true)
  deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

  get collections_path

  assert_select ".over-allocation-banner"
end

test "no banner when nothing is over-allocated" do
  @user.collections.create!(card: @card, quantity: 4)
  deck = @user.decks.create!(name: "OK", physical: true)
  deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

  get decks_path

  assert_select ".over-allocation-banner", false
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/integration/allocation_ui_test.rb -n /to-review|banner/`
Expected: FAIL.

- [ ] **Step 3: Create the banner component**

Create `app/views/components/allocations/over_allocation_banner.rb`:

```ruby
module Allocations
  # A discreet alert shown at the top of /decks and /collections when the user
  # has over-allocated cards, linking to the over-allocations page. Renders
  # nothing when count is zero.
  class OverAllocationBanner < ApplicationComponent
    def initialize(count:)
      @count = count
    end

    def view_template
      return if @count.zero?

      div(class: "over-allocation-banner badge-warning") do
        plain "⚠ #{@count} #{@count == 1 ? "carte sur-allouée" : "cartes sur-allouées"} — "
        link_to "voir", over_allocations_path
      end
    end
  end
end
```

- [ ] **Step 4: Add the "to review" badge to `ClassificationBadges`**

In `app/views/components/decks/classification_badges.rb`, change the constructor and add the badge:

```ruby
    def initialize(deck:, over_allocated: false)
      @deck = deck
      @over_allocated = over_allocated
    end
```

In `view_template`, add as the last child inside the `div(class: "deck-badges")` block:

```ruby
        span(class: "badge badge-warning") { "À revoir" } if @over_allocated
```

- [ ] **Step 5: Forward `over_allocated` through the deck list tile**

In `app/views/components/decks/deck_card.rb`, change the constructor:

```ruby
    def initialize(deck:, with_actions: true, over_allocated: false)
      @deck = deck
      @with_actions = with_actions
      @over_allocated = over_allocated
    end
```

Change the `ClassificationBadges` render line to:

```ruby
          render Decks::ClassificationBadges.new(deck: @deck, over_allocated: @over_allocated)
```

- [ ] **Step 6: Wire the deck index (controller + view)**

In `app/controllers/decks_controller.rb`, at the end of `index`, add:

```ruby
    over_allocations = Allocations::OverAllocations.call(user: current_user)
    @over_allocation_count = over_allocations.size
    @over_allocated_deck_ids = over_allocations.flat_map { |o| o[:decks].map { |d| d[:id] } }.to_set
```

In `app/views/decks/index.html.erb`, add `over_allocated_deck_ids: @over_allocated_deck_ids` and `over_allocation_count: @over_allocation_count` to the `Decks::IndexView.new(...)` render.

In `app/views/components/decks/index_view.rb`:
- Add to the constructor signature: `over_allocated_deck_ids: [], over_allocation_count: 0`, and store `@over_allocated_deck_ids = over_allocated_deck_ids.to_set`, `@over_allocation_count = over_allocation_count`.
- In `view_template`, immediately inside `div(class: "decks-container", ...)` and before `div(class: "decks-header")`, add:

```ruby
        render Allocations::OverAllocationBanner.new(count: @over_allocation_count)
```

- Change the deck render line to forward the flag:

```ruby
            @decks.each { |deck| render Decks::DeckCard.new(deck: deck, over_allocated: @over_allocated_deck_ids.include?(deck.id)) }
```

- [ ] **Step 7: Wire the collections index (controller + view)**

In `app/controllers/collections_controller.rb`, at the end of `index`, add:

```ruby
    @over_allocation_count = Allocations::OverAllocations.call(user: current_user).size
```

In `app/views/collections/index.html.erb`, add `over_allocation_count: @over_allocation_count` to the `Collections::IndexView.new(...)` render.

In `app/views/components/collections/index_view.rb`:
- Add `over_allocation_count: 0` to the constructor and store `@over_allocation_count = over_allocation_count`.
- In `view_template`, render the banner at the very top of the container (before the header):

```ruby
        render Allocations::OverAllocationBanner.new(count: @over_allocation_count)
```

- [ ] **Step 8: Add minimal styles**

Append to `app/assets/stylesheets/application.css`:

```css
.over-allocation-banner { display: block; padding: 0.5rem 0.75rem; border-radius: var(--radius, 6px); margin-bottom: 1rem; font-size: 0.875rem; }
.over-allocation-row { display: flex; flex-wrap: wrap; gap: 0.75rem; align-items: baseline; padding: 0.5rem 0; border-bottom: 1px solid var(--border, #eee); }
.over-allocation-decks { display: inline-flex; gap: 0.5rem; }
```

- [ ] **Step 9: Run to verify pass**

Run: `bin/rails test test/integration/allocation_ui_test.rb`
Expected: PASS (all tests, including the earlier ones).

- [ ] **Step 10: Commit**

```bash
git add app/views/components/decks/classification_badges.rb app/views/components/decks/deck_card.rb app/views/components/decks/index_view.rb app/controllers/decks_controller.rb app/controllers/collections_controller.rb app/views/components/collections/index_view.rb app/views/decks/index.html.erb app/views/collections/index.html.erb app/views/components/allocations/over_allocation_banner.rb app/assets/stylesheets/application.css test/integration/allocation_ui_test.rb
git commit -m "feat: add to-review badge and over-allocation banner (#55)"
```

---

### Task 9: Reallocate reals between decks (over-allocations page control)

> **Note:** Reallocation is a *rebalancing* tool — moving a real from deck A to deck B keeps total `committed` constant, so it does not by itself clear an over-allocation (demoting reals via the Task 5 stepper, or adding to the collection, does). It is included because the approved spec scopes it here and the `OwnedCopiesReallocator` service + MCP tool already exist. If the reviewer prefers, this task can be dropped without affecting Tasks 1–8.

**Files:**
- Modify: `config/routes.rb`
- Modify: `app/controllers/over_allocations_controller.rb`
- Modify: `app/views/components/over_allocations/index_view.rb`
- Test: `test/integration/allocation_ui_test.rb` (append)

**Interfaces:**
- Consumes: `Decks::OwnedCopiesReallocator.call(from_deck:, to_deck:, card:, quantity:)` (raises `ArgumentError` / `Decks::OwnedCopiesReallocator::NotPhysicalError`).
- Produces: route `reallocate_over_allocations_path` (POST); a form per over-allocation row.

- [ ] **Step 1: Write the failing test**

Append to `test/integration/allocation_ui_test.rb`:

```ruby
test "reallocate moves a real copy from one physical deck to another" do
  @user.collections.create!(card: @card, quantity: 1)
  from = @user.decks.create!(name: "From", physical: true)
  from.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)
  to = @user.decks.create!(name: "To", physical: true)
  to.deck_cards.create!(card: @card, quantity: 2, owned_copies: 0)

  post reallocate_over_allocations_path, params: {
    from_deck_id: from.id, to_deck_id: to.id, card_id: @card.id, quantity: 1
  }

  assert_redirected_to over_allocations_path
  assert_equal 1, from.deck_cards.find_by(card: @card).owned_copies
  assert_equal 1, to.deck_cards.find_by(card: @card).owned_copies
end

test "reallocate with an invalid move redirects with an alert" do
  @user.collections.create!(card: @card, quantity: 1)
  from = @user.decks.create!(name: "From", physical: true)
  from.deck_cards.create!(card: @card, quantity: 2, owned_copies: 1)
  to = @user.decks.create!(name: "To", physical: true)
  to.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1) # no proxy slot

  post reallocate_over_allocations_path, params: {
    from_deck_id: from.id, to_deck_id: to.id, card_id: @card.id, quantity: 1
  }

  assert_redirected_to over_allocations_path
  assert flash[:alert].present?
end
```

- [ ] **Step 2: Run to verify failure**

Run: `bin/rails test test/integration/allocation_ui_test.rb -n /reallocate/`
Expected: FAIL (`reallocate_over_allocations_path` undefined).

- [ ] **Step 3: Add the route**

In `config/routes.rb`, change the over_allocations resource to:

```ruby
    resources :over_allocations, only: [ :index ] do
      post :reallocate, on: :collection
    end
```

- [ ] **Step 4: Add the controller action**

In `app/controllers/over_allocations_controller.rb`, add:

```ruby
  def reallocate
    from_deck = current_user.decks.find(params[:from_deck_id])
    to_deck = current_user.decks.find(params[:to_deck_id])
    card = Card.find(params[:card_id])

    Decks::OwnedCopiesReallocator.call(
      from_deck: from_deck, to_deck: to_deck, card: card, quantity: params[:quantity].to_i
    )
    redirect_to over_allocations_path, notice: "Copies réelles déplacées."
  rescue ArgumentError, Decks::OwnedCopiesReallocator::NotPhysicalError => e
    redirect_to over_allocations_path, alert: e.message
  rescue ActiveRecord::RecordNotFound
    redirect_to over_allocations_path, alert: "Carte introuvable dans l'un des decks."
  end
```

- [ ] **Step 5: Enrich the controller#index with reallocation candidates**

Replace `index` in `app/controllers/over_allocations_controller.rb` with:

```ruby
  def index
    @over_allocations = Allocations::OverAllocations.call(user: current_user)
    card_ids = @over_allocations.map { |o| o[:card_id] }
    @cards_by_id = Card.where(id: card_ids).index_by(&:id)

    # Per card: physical decks holding it that still have proxy slots to convert
    # into reals (owned_copies < quantity) — the valid reallocation targets.
    @targets_by_card = card_ids.index_with do |card_id|
      current_user.decks.where(physical: true)
        .joins(:deck_cards)
        .where(deck_cards: { card_id: card_id })
        .where("deck_cards.owned_copies < deck_cards.quantity")
        .distinct
        .pluck(:id, :name)
    end
  end
```

- [ ] **Step 6: Add the reallocation form to each row**

In `app/views/components/over_allocations/index_view.rb`, change the constructor to accept targets:

```ruby
    def initialize(over_allocations:, cards_by_id:, targets_by_card: {})
      @over_allocations = over_allocations
      @cards_by_id = cards_by_id
      @targets_by_card = targets_by_card
    end
```

Add `targets_by_card: @targets_by_card` to the render call in `app/views/over_allocations/index.html.erb`.

Inside `row(over)`, after the `over-allocation-decks` div, add a reallocation form built from the contributing decks (sources with `owned_copies > 0`) and the target decks:

```ruby
        reallocation_form(over)
```

Then add the private method:

```ruby
    def reallocation_form(over)
      sources = over[:decks]
      targets = @targets_by_card[over[:card_id]] || []
      return if sources.empty? || targets.empty?

      form_with url: reallocate_over_allocations_path, method: :post, class: "over-allocation-reallocate" do |f|
        f.hidden_field :card_id, value: over[:card_id]
        f.select :from_deck_id, sources.map { |d| [ d[:name], d[:id] ] }
        f.select :to_deck_id, targets.map { |id, name| [ name, id ] }
        f.number_field :quantity, value: 1, min: 1
        f.submit "Réallouer"
      end
    end
```

Note: `form_with` and `select`/`number_field` come from Phlex::Rails helpers; `ApplicationComponent` already includes `FormWith`. If `f.select`/`f.hidden_field` are unavailable on the yielded builder in this Phlex version, fall back to raw inputs inside the form block:

```ruby
      form_with url: reallocate_over_allocations_path, method: :post, class: "over-allocation-reallocate" do
        input(type: "hidden", name: "card_id", value: over[:card_id])
        select(name: "from_deck_id") { sources.each { |d| option(value: d[:id]) { d[:name] } } }
        select(name: "to_deck_id") { targets.each { |id, name| option(value: id) { name } } }
        input(type: "number", name: "quantity", value: "1", min: "1")
        button(type: "submit") { "Réallouer" }
      end
```

Prefer the raw-inputs version for reliability (it does not depend on the yielded form-builder API).

- [ ] **Step 7: Run to verify pass**

Run: `bin/rails test test/integration/allocation_ui_test.rb`
Expected: PASS (all tests).

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/over_allocations_controller.rb app/views/components/over_allocations/index_view.rb app/views/over_allocations/index.html.erb test/integration/allocation_ui_test.rb
git commit -m "feat: reallocate reals between decks from the over-allocations page (#55)"
```

---

### Final verification

- [ ] **Run the full relevant suites**

Run: `bin/rails test test/models/deck_card_test.rb test/controllers/api/ test/integration/allocation_ui_test.rb`
Expected: all PASS.

- [ ] **Lint**

Run: `bin/rubocop -f github app/ test/`
Expected: no offenses (auto-correct with `bin/rubocop -A` if needed, re-run tests).

- [ ] **Security scan**

Run: `bin/brakeman --no-pager`
Expected: no new warnings.

---

## Notes on scope (from the approved spec)

- **Out of scope:** batching the collection-index N+1 (#59), reconciling `Deck#has_proxies` (#56), foil-aware allocation, deck legality (#61).
- **Known seam:** collection index and both banner computations call `Allocations::OverAllocations` / `Availability` per request without batching — acceptable this iteration.
