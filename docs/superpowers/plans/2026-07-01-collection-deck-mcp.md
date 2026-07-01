# Collection & Deck MCP Server — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an MCP server, mounted in the Rails app, whose tools let an authenticated user add cards to their collection, link cards to a deck, and transfer cards between collection and deck in both directions.

**Architecture:** A Rails controller (`Mcp::ServerController`, `ActionController::API`) authenticates a per-user API token from the `Authorization: Bearer` header, then hands the request to an `MCP::Server` (official `mcp` gem) via its `StreamableHTTPTransport`, passing the authenticated `User` through `server_context`. Tool classes live under `app/mcp/` and delegate all writes to thin services under `app/services/` following the repo's `ApplicationService.call` pattern.

**Tech Stack:** Rails 8.1, Ruby 4.0.1, SQLite3, `mcp` gem (~0.22), Minitest with fixtures, rubocop-rails-omakase.

## Global Constraints

- Rails 8.1 / Ruby 4.0.1; SQLite3 in every environment.
- Services inherit `ApplicationService` (provides `.call(...)` → `new(...).call`).
- Lint with `bin/rubocop` (rubocop-rails-omakase). Keep double-quoted strings, no trailing whitespace.
- Tests are Minitest with `fixtures :all`; fixtures reset per test (transactional), parallel workers.
- Card energy/type colours must use `Card::TYPE_TOKENS` (not relevant here, but no literal hexes anywhere).
- The MCP route uses **token auth only** and must live OUTSIDE the `authenticate :user do` block in `config/routes.rb`.

---

### Task 1: API token on User + `mcp` gem + token rake task

**Files:**
- Modify: `Gemfile` (add `gem "mcp"`)
- Create: `db/migrate/YYYYMMDDHHMMSS_add_api_token_to_users.rb`
- Modify: `app/models/user.rb` (add `has_secure_token :api_token`)
- Create: `lib/tasks/mcp.rake`
- Test: `test/models/user_test.rb`

**Interfaces:**
- Produces: `User#api_token` (String, unique), `User#regenerate_api_token`, rake task `mcp:token[email]`.

- [ ] **Step 1: Add the gem**

Add to `Gemfile` (near the other top-level gems, after `gem "propshaft"` or similar):

```ruby
# Model Context Protocol server (collection/deck tools)
gem "mcp", "~> 0.22"
```

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: `Bundle complete`, `mcp` resolved at 0.22.x.

- [ ] **Step 3: Write the failing test**

Add to `test/models/user_test.rb` (create the file with this content if it doesn't exist; if it exists, add the two tests inside the existing class):

```ruby
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "generates an api_token on create" do
    user = User.create!(email: "token-user@example.com", password: "password123")
    assert user.api_token.present?
  end

  test "regenerate_api_token replaces the token" do
    user = User.create!(email: "regen-user@example.com", password: "password123")
    original = user.api_token
    user.regenerate_api_token
    assert_not_equal original, user.api_token
    assert user.api_token.present?
  end
end
```

- [ ] **Step 4: Run test to verify it fails**

Run: `bin/rails test test/models/user_test.rb -v`
Expected: FAIL — `NoMethodError: undefined method 'api_token'` (column/method missing).

- [ ] **Step 5: Create the migration**

Create `db/migrate/YYYYMMDDHHMMSS_add_api_token_to_users.rb` (use a real timestamp, e.g. generate with `bin/rails g migration AddApiTokenToUsers` then replace the body):

```ruby
class AddApiTokenToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :api_token, :string
    add_index :users, :api_token, unique: true

    User.reset_column_information
    User.where(api_token: nil).find_each do |user|
      user.update_columns(api_token: SecureRandom.base58(24))
    end
  end

  def down
    remove_index :users, :api_token
    remove_column :users, :api_token
  end
end
```

- [ ] **Step 6: Add `has_secure_token` to the model**

In `app/models/user.rb`, add near the top of the class body (after any `devise` line):

```ruby
  has_secure_token :api_token
```

- [ ] **Step 7: Create the rake task**

Create `lib/tasks/mcp.rake`:

```ruby
namespace :mcp do
  desc "Print a user's MCP API token. Set REGENERATE=1 to rotate it. Usage: bin/rails 'mcp:token[email@example.com]'"
  task :token, [ :email ] => :environment do |_task, args|
    user = User.find_by!(email: args.fetch(:email))
    user.regenerate_api_token if ENV["REGENERATE"] == "1"
    puts user.api_token
  end
end
```

- [ ] **Step 8: Migrate and run tests**

Run: `bin/rails db:migrate && bin/rails db:test:prepare && bin/rails test test/models/user_test.rb -v`
Expected: PASS (both tests green).

- [ ] **Step 9: Commit**

```bash
git add Gemfile Gemfile.lock db/migrate db/schema.rb app/models/user.rb lib/tasks/mcp.rake test/models/user_test.rb
git commit -m "feat: add per-user API token and mcp gem for MCP auth"
```

---

### Task 2: `Collections::CardAdder` service

**Files:**
- Create: `app/services/collections/card_adder.rb`
- Test: `test/services/collections/card_adder_test.rb`

**Interfaces:**
- Produces: `Collections::CardAdder.call(user:, card:, quantity: 1)` → the saved `Collection` (with updated `quantity`).

- [ ] **Step 1: Write the failing test**

Create `test/services/collections/card_adder_test.rb`:

```ruby
require "test_helper"

module Collections
  class CardAdderTest < ActiveSupport::TestCase
    test "creates a collection entry when none exists" do
      user = users(:two)
      card = cards(:trainer_card)

      collection = Collections::CardAdder.call(user: user, card: card, quantity: 2)

      assert_equal 2, collection.quantity
      assert_equal user, collection.user
      assert_equal card, collection.card
    end

    test "increments an existing collection entry" do
      user = users(:one) # fixture: collection(:one) is honedge, quantity 1
      card = cards(:honedge)

      collection = Collections::CardAdder.call(user: user, card: card, quantity: 3)

      assert_equal 4, collection.quantity
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/collections/card_adder_test.rb -v`
Expected: FAIL — `NameError: uninitialized constant Collections::CardAdder`.

- [ ] **Step 3: Write the implementation**

Create `app/services/collections/card_adder.rb`:

```ruby
module Collections
  class CardAdder < ApplicationService
    def initialize(user:, card:, quantity: 1)
      @user = user
      @card = card
      @quantity = quantity
    end

    def call
      collection = @user.collections.find_or_initialize_by(card: @card)
      collection.quantity = collection.quantity.to_i + @quantity
      collection.save!
      collection
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/collections/card_adder_test.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/collections/card_adder.rb test/services/collections/card_adder_test.rb
git commit -m "feat: add Collections::CardAdder service"
```

---

### Task 3: `Decks::CardAdder` service

**Files:**
- Create: `app/services/decks/card_adder.rb`
- Test: `test/services/decks/card_adder_test.rb`

**Interfaces:**
- Produces: `Decks::CardAdder.call(deck:, card:, quantity: 1)` → the saved `DeckCard`.

- [ ] **Step 1: Write the failing test**

Create `test/services/decks/card_adder_test.rb`:

```ruby
require "test_helper"

module Decks
  class CardAdderTest < ActiveSupport::TestCase
    test "creates a deck_card when none exists" do
      deck = decks(:two)
      card = cards(:honedge) # deck(:two) holds doublade, not honedge

      deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: 2)

      assert_equal 2, deck_card.quantity
      assert_equal deck, deck_card.deck
      assert_equal card, deck_card.card
    end

    test "increments an existing deck_card" do
      deck = decks(:one) # fixture: deck_card(:one) is honedge, quantity 1
      card = cards(:honedge)

      deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: 2)

      assert_equal 3, deck_card.quantity
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/decks/card_adder_test.rb -v`
Expected: FAIL — `NameError: uninitialized constant Decks::CardAdder`.

- [ ] **Step 3: Write the implementation**

Create `app/services/decks/card_adder.rb`:

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
      deck_card.save!
      deck_card
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/decks/card_adder_test.rb -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add app/services/decks/card_adder.rb test/services/decks/card_adder_test.rb
git commit -m "feat: add Decks::CardAdder service"
```

---

### Task 4: `Decks::CardTransfer` service (collection ↔ deck)

**Files:**
- Create: `app/services/decks/card_transfer.rb`
- Test: `test/services/decks/card_transfer_test.rb`

**Interfaces:**
- Produces: `Decks::CardTransfer.call(user:, deck:, card:, direction:, quantity: 1)` → `Decks::CardTransfer::Result` with `#collection_quantity` and `#deck_quantity` (both Integer). `direction` is `:in` (collection→deck) or `:out` (deck→collection). Raises `ArgumentError` on any other direction.
- Semantics: transactional; collection floored at 0 on `:in`; on `:out` the `DeckCard` is destroyed if it reaches ≤ 0; collection always gains the full `quantity` on `:out`; no ownership enforcement.

- [ ] **Step 1: Write the failing test**

Create `test/services/decks/card_transfer_test.rb`:

```ruby
require "test_helper"

module Decks
  class CardTransferTest < ActiveSupport::TestCase
    # Fixtures: collection(:one) = user one / honedge / qty 1
    #           deck_card(:one)  = deck one (user one) / honedge / qty 1
    setup do
      @user = users(:one)
      @deck = decks(:one)
      @card = cards(:honedge)
    end

    test "direction :in moves a card from collection to deck" do
      result = Decks::CardTransfer.call(user: @user, deck: @deck, card: @card, direction: :in, quantity: 1)

      assert_equal 0, result.collection_quantity
      assert_equal 2, result.deck_quantity
      assert_equal 0, @user.collections.find_by(card: @card).quantity
      assert_equal 2, @deck.deck_cards.find_by(card: @card).quantity
    end

    test "direction :in floors the collection at zero without enforcement" do
      result = Decks::CardTransfer.call(user: @user, deck: @deck, card: @card, direction: :in, quantity: 5)

      assert_equal 0, result.collection_quantity
      assert_equal 6, result.deck_quantity
    end

    test "direction :out returns cards to collection and destroys an emptied deck_card" do
      result = Decks::CardTransfer.call(user: @user, deck: @deck, card: @card, direction: :out, quantity: 1)

      assert_equal 2, result.collection_quantity
      assert_equal 0, result.deck_quantity
      assert_nil @deck.deck_cards.find_by(card: @card)
    end

    test "direction :out over-withdraw destroys the deck_card and still credits the full quantity" do
      result = Decks::CardTransfer.call(user: @user, deck: @deck, card: @card, direction: :out, quantity: 3)

      assert_equal 4, result.collection_quantity # started at 1, +3
      assert_equal 0, result.deck_quantity
      assert_nil @deck.deck_cards.find_by(card: @card)
    end

    test "raises on an unknown direction" do
      assert_raises(ArgumentError) do
        Decks::CardTransfer.call(user: @user, deck: @deck, card: @card, direction: :sideways)
      end
    end
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/services/decks/card_transfer_test.rb -v`
Expected: FAIL — `NameError: uninitialized constant Decks::CardTransfer`.

- [ ] **Step 3: Write the implementation**

Create `app/services/decks/card_transfer.rb`:

```ruby
module Decks
  class CardTransfer < ApplicationService
    Result = Struct.new(:collection_quantity, :deck_quantity, keyword_init: true)

    def initialize(user:, deck:, card:, direction:, quantity: 1)
      @user = user
      @deck = deck
      @card = card
      @direction = direction
      @quantity = quantity
    end

    def call
      unless %i[in out].include?(@direction)
        raise ArgumentError, "direction must be :in or :out, got #{@direction.inspect}"
      end

      ActiveRecord::Base.transaction do
        @direction == :in ? transfer_in : transfer_out
      end

      Result.new(collection_quantity: collection_quantity, deck_quantity: deck_quantity)
    end

    private

    def transfer_in
      collection = @user.collections.find_or_initialize_by(card: @card)
      collection.quantity = [ collection.quantity.to_i - @quantity, 0 ].max
      collection.save!

      Decks::CardAdder.call(deck: @deck, card: @card, quantity: @quantity)
    end

    def transfer_out
      deck_card = @deck.deck_cards.find_by(card: @card)
      if deck_card
        remaining = deck_card.quantity - @quantity
        remaining <= 0 ? deck_card.destroy! : deck_card.update!(quantity: remaining)
      end

      Collections::CardAdder.call(user: @user, card: @card, quantity: @quantity)
    end

    def collection_quantity
      @user.collections.find_by(card: @card)&.quantity || 0
    end

    def deck_quantity
      @deck.deck_cards.find_by(card: @card)&.quantity || 0
    end
  end
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `bin/rails test test/services/decks/card_transfer_test.rb -v`
Expected: PASS (all five tests).

- [ ] **Step 5: Commit**

```bash
git add app/services/decks/card_transfer.rb test/services/decks/card_transfer_test.rb
git commit -m "feat: add Decks::CardTransfer service"
```

---

### Task 5: MCP tool base class + write tools

**Files:**
- Create: `app/mcp/mcp_tool.rb` (base, top-level constant `McpTool`)
- Create: `app/mcp/add_card_to_collection_tool.rb`
- Create: `app/mcp/add_card_to_deck_tool.rb`
- Create: `app/mcp/move_card_to_deck_tool.rb`
- Create: `app/mcp/move_card_from_deck_tool.rb`
- Test: `test/mcp/write_tools_test.rb`

**Interfaces:**
- `app/mcp` is autoloaded by Rails as a root path, so these files define **top-level** constants (`McpTool`, `AddCardToCollectionTool`, …).
- Base `McpTool < MCP::Tool` provides private class helpers: `current_user(server_context)` → `User`; `find_card!(id)` → `Card`; `find_deck!(user, id)` → `Deck`; `text(str)` → `MCP::Tool::Response`.
- Each tool defines `self.call(**kwargs, server_context:)` returning `MCP::Tool::Response`.
- Consumes: `Collections::CardAdder`, `Decks::CardAdder`, `Decks::CardTransfer` from Tasks 2–4.

- [ ] **Step 1: Write the failing test**

Create `test/mcp/write_tools_test.rb`:

```ruby
require "test_helper"

class WriteToolsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)          # user one
    @card = cards(:honedge)      # collection qty 1, deck_card qty 1
    @context = { user: @user }
  end

  def response_text(response)
    response.content.first[:text]
  end

  test "AddCardToCollectionTool increments the collection" do
    response = AddCardToCollectionTool.call(card_id: @card.id, quantity: 3, server_context: @context)

    assert_equal 4, @user.collections.find_by(card: @card).quantity
    assert_match(/Honedge/, response_text(response))
  end

  test "AddCardToCollectionTool reports an unknown card id" do
    response = AddCardToCollectionTool.call(card_id: -1, quantity: 1, server_context: @context)

    assert_match(/Error/i, response_text(response))
  end

  test "AddCardToDeckTool increments the deck without touching the collection" do
    AddCardToDeckTool.call(deck_id: @deck.id, card_id: @card.id, quantity: 2, server_context: @context)

    assert_equal 3, @deck.deck_cards.find_by(card: @card).quantity
    assert_equal 1, @user.collections.find_by(card: @card).quantity
  end

  test "MoveCardToDeckTool transfers from collection to deck" do
    MoveCardToDeckTool.call(deck_id: @deck.id, card_id: @card.id, quantity: 1, server_context: @context)

    assert_equal 0, @user.collections.find_by(card: @card).quantity
    assert_equal 2, @deck.deck_cards.find_by(card: @card).quantity
  end

  test "MoveCardFromDeckTool transfers from deck back to collection" do
    MoveCardFromDeckTool.call(deck_id: @deck.id, card_id: @card.id, quantity: 1, server_context: @context)

    assert_equal 2, @user.collections.find_by(card: @card).quantity
    assert_nil @deck.deck_cards.find_by(card: @card)
  end

  test "deck tools reject a deck the user does not own" do
    other_deck = decks(:two) # user two

    response = AddCardToDeckTool.call(deck_id: other_deck.id, card_id: @card.id, quantity: 1, server_context: @context)

    assert_match(/Error/i, response_text(response))
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/mcp/write_tools_test.rb -v`
Expected: FAIL — `NameError: uninitialized constant McpTool`/`AddCardToCollectionTool`.

- [ ] **Step 3: Write the base class**

Create `app/mcp/mcp_tool.rb`:

```ruby
# Base class for Cartodex MCP tools. Provides helpers for resolving the
# authenticated user (passed through server_context), looking up owned records,
# and building text responses.
class McpTool < MCP::Tool
  class << self
    private

    def current_user(server_context)
      server_context.fetch(:user)
    end

    def find_card!(id)
      Card.find(id)
    end

    def find_deck!(user, id)
      user.decks.find(id)
    end

    def text(string)
      MCP::Tool::Response.new([ { type: "text", text: string } ])
    end
  end
end
```

- [ ] **Step 4: Write `AddCardToCollectionTool`**

Create `app/mcp/add_card_to_collection_tool.rb`:

```ruby
class AddCardToCollectionTool < McpTool
  description "Add a quantity of a card (by card_id) to the authenticated user's collection."
  input_schema(
    properties: {
      card_id: { type: "integer", description: "ID of the card to add" },
      quantity: { type: "integer", description: "How many copies to add (default 1)" }
    },
    required: [ "card_id" ]
  )

  def self.call(card_id:, server_context:, quantity: 1)
    user = current_user(server_context)
    card = find_card!(card_id)
    collection = Collections::CardAdder.call(user: user, card: card, quantity: quantity)
    text("Added #{quantity}× #{card.name} to your collection (now #{collection.quantity}).")
  rescue ActiveRecord::RecordNotFound
    text("Error: no card with id #{card_id}.")
  end
end
```

- [ ] **Step 5: Write `AddCardToDeckTool`**

Create `app/mcp/add_card_to_deck_tool.rb`:

```ruby
class AddCardToDeckTool < McpTool
  description "Add (link) a quantity of a card to one of the user's decks, without changing the collection."
  input_schema(
    properties: {
      deck_id: { type: "integer", description: "ID of the user's deck" },
      card_id: { type: "integer", description: "ID of the card to add" },
      quantity: { type: "integer", description: "How many copies to add (default 1)" }
    },
    required: [ "deck_id", "card_id" ]
  )

  def self.call(deck_id:, card_id:, server_context:, quantity: 1)
    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    card = find_card!(card_id)
    deck_card = Decks::CardAdder.call(deck: deck, card: card, quantity: quantity)
    text("Added #{quantity}× #{card.name} to deck “#{deck.name}” (now #{deck_card.quantity}).")
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck id #{deck_id} or card id #{card_id} (deck must belong to you).")
  end
end
```

- [ ] **Step 6: Write `MoveCardToDeckTool`**

Create `app/mcp/move_card_to_deck_tool.rb`:

```ruby
class MoveCardToDeckTool < McpTool
  description "Move a quantity of a card from the collection into a deck (collection down, deck up)."
  input_schema(
    properties: {
      deck_id: { type: "integer", description: "ID of the user's deck" },
      card_id: { type: "integer", description: "ID of the card to move" },
      quantity: { type: "integer", description: "How many copies to move (default 1)" }
    },
    required: [ "deck_id", "card_id" ]
  )

  def self.call(deck_id:, card_id:, server_context:, quantity: 1)
    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    card = find_card!(card_id)
    result = Decks::CardTransfer.call(user: user, deck: deck, card: card, direction: :in, quantity: quantity)
    text("Moved #{quantity}× #{card.name} into deck “#{deck.name}”. " \
         "Collection: #{result.collection_quantity}, deck: #{result.deck_quantity}.")
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck id #{deck_id} or card id #{card_id} (deck must belong to you).")
  end
end
```

- [ ] **Step 7: Write `MoveCardFromDeckTool`**

Create `app/mcp/move_card_from_deck_tool.rb`:

```ruby
class MoveCardFromDeckTool < McpTool
  description "Move a quantity of a card out of a deck back into the collection (deck down, collection up)."
  input_schema(
    properties: {
      deck_id: { type: "integer", description: "ID of the user's deck" },
      card_id: { type: "integer", description: "ID of the card to move" },
      quantity: { type: "integer", description: "How many copies to move (default 1)" }
    },
    required: [ "deck_id", "card_id" ]
  )

  def self.call(deck_id:, card_id:, server_context:, quantity: 1)
    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    card = find_card!(card_id)
    result = Decks::CardTransfer.call(user: user, deck: deck, card: card, direction: :out, quantity: quantity)
    text("Moved #{quantity}× #{card.name} out of deck “#{deck.name}”. " \
         "Collection: #{result.collection_quantity}, deck: #{result.deck_quantity}.")
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck id #{deck_id} or card id #{card_id} (deck must belong to you).")
  end
end
```

- [ ] **Step 8: Run test to verify it passes**

Run: `bin/rails test test/mcp/write_tools_test.rb -v`
Expected: PASS (all tests).

- [ ] **Step 9: Commit**

```bash
git add app/mcp/mcp_tool.rb app/mcp/add_card_to_collection_tool.rb app/mcp/add_card_to_deck_tool.rb app/mcp/move_card_to_deck_tool.rb app/mcp/move_card_from_deck_tool.rb test/mcp/write_tools_test.rb
git commit -m "feat: add MCP write tools for collection and deck management"
```

---

### Task 6: MCP read tools

**Files:**
- Create: `app/mcp/search_cards_tool.rb`
- Create: `app/mcp/list_decks_tool.rb`
- Create: `app/mcp/list_collection_tool.rb`
- Create: `app/mcp/list_deck_cards_tool.rb`
- Test: `test/mcp/read_tools_test.rb`

**Interfaces:**
- Consumes: `McpTool` base (Task 5).
- Each returns a `MCP::Tool::Response` whose text is a JSON array (so the assistant can parse ids).
- `SearchCardsTool.call(query:, server_context:, set_code: nil, limit: 20)` → `[{id, name, set_name, set_number, card_type}]`
- `ListDecksTool.call(server_context:)` → `[{id, name, format}]`
- `ListCollectionTool.call(server_context:, query: nil)` → `[{card_id, name, quantity}]`
- `ListDeckCardsTool.call(deck_id:, server_context:)` → `[{card_id, name, quantity}]`

- [ ] **Step 1: Write the failing test**

Create `test/mcp/read_tools_test.rb`:

```ruby
require "test_helper"
require "json"

class ReadToolsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @context = { user: @user }
  end

  def payload(response)
    JSON.parse(response.content.first[:text])
  end

  test "SearchCardsTool finds cards by name substring" do
    response = SearchCardsTool.call(query: "honed", server_context: @context)
    names = payload(response).map { |c| c["name"] }

    assert_includes names, "Honedge"
  end

  test "ListDecksTool returns only the user's decks" do
    response = ListDecksTool.call(server_context: @context)
    ids = payload(response).map { |d| d["id"] }

    assert_includes ids, decks(:one).id
    assert_not_includes ids, decks(:two).id
  end

  test "ListCollectionTool returns the user's collection entries" do
    response = ListCollectionTool.call(server_context: @context)
    card_ids = payload(response).map { |c| c["card_id"] }

    assert_includes card_ids, cards(:honedge).id
  end

  test "ListDeckCardsTool returns the cards in an owned deck" do
    response = ListDeckCardsTool.call(deck_id: decks(:one).id, server_context: @context)
    card_ids = payload(response).map { |c| c["card_id"] }

    assert_includes card_ids, cards(:honedge).id
  end

  test "ListDeckCardsTool reports an error for a deck the user does not own" do
    response = ListDeckCardsTool.call(deck_id: decks(:two).id, server_context: @context)

    assert_match(/Error/i, response.content.first[:text])
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/mcp/read_tools_test.rb -v`
Expected: FAIL — `NameError: uninitialized constant SearchCardsTool`.

- [ ] **Step 3: Write `SearchCardsTool`**

Create `app/mcp/search_cards_tool.rb`:

```ruby
class SearchCardsTool < McpTool
  MAX_LIMIT = 50

  description "Search the card database by name substring (optionally filtered by set code). Returns matching cards with their ids."
  input_schema(
    properties: {
      query: { type: "string", description: "Case-insensitive substring of the card name" },
      set_code: { type: "string", description: "Optional set code to filter by (e.g. \"por\")" },
      limit: { type: "integer", description: "Max results (default 20, capped at 50)" }
    },
    required: [ "query" ]
  )

  def self.call(query:, server_context:, set_code: nil, limit: 20)
    scope = Card.where("name LIKE ?", "%#{query}%")
    scope = scope.joins(:card_set).where(card_sets: { code: set_code }) if set_code.present?
    cards = scope.limit(limit.to_i.clamp(1, MAX_LIMIT)).map do |card|
      { id: card.id, name: card.name, set_name: card.set_name, set_number: card.set_number, card_type: card.card_type }
    end
    text(cards.to_json)
  end
end
```

- [ ] **Step 4: Write `ListDecksTool`**

Create `app/mcp/list_decks_tool.rb`:

```ruby
class ListDecksTool < McpTool
  description "List the authenticated user's decks with their ids, names, and formats."
  input_schema(properties: {}, required: [])

  def self.call(server_context:)
    user = current_user(server_context)
    decks = user.decks.map do |deck|
      { id: deck.id, name: deck.name, format: deck.format }
    end
    text(decks.to_json)
  end
end
```

- [ ] **Step 5: Write `ListCollectionTool`**

Create `app/mcp/list_collection_tool.rb`:

```ruby
class ListCollectionTool < McpTool
  description "List the authenticated user's collection (cards with quantity > 0), optionally filtered by card name."
  input_schema(
    properties: {
      query: { type: "string", description: "Optional case-insensitive substring of the card name" }
    },
    required: []
  )

  def self.call(server_context:, query: nil)
    user = current_user(server_context)
    scope = user.collections.with_cards.includes(:card)
    entries = scope.filter_map do |collection|
      next if query.present? && !collection.card.name.downcase.include?(query.downcase)

      { card_id: collection.card_id, name: collection.card.name, quantity: collection.quantity }
    end
    text(entries.to_json)
  end
end
```

- [ ] **Step 6: Write `ListDeckCardsTool`**

Create `app/mcp/list_deck_cards_tool.rb`:

```ruby
class ListDeckCardsTool < McpTool
  description "List the cards in one of the user's decks with their ids and quantities."
  input_schema(
    properties: {
      deck_id: { type: "integer", description: "ID of the user's deck" }
    },
    required: [ "deck_id" ]
  )

  def self.call(deck_id:, server_context:)
    user = current_user(server_context)
    deck = find_deck!(user, deck_id)
    entries = deck.deck_cards.includes(:card).map do |deck_card|
      { card_id: deck_card.card_id, name: deck_card.card.name, quantity: deck_card.quantity }
    end
    text(entries.to_json)
  rescue ActiveRecord::RecordNotFound
    text("Error: unknown deck id #{deck_id} (deck must belong to you).")
  end
end
```

- [ ] **Step 7: Run test to verify it passes**

Run: `bin/rails test test/mcp/read_tools_test.rb -v`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add app/mcp/search_cards_tool.rb app/mcp/list_decks_tool.rb app/mcp/list_collection_tool.rb app/mcp/list_deck_cards_tool.rb test/mcp/read_tools_test.rb
git commit -m "feat: add MCP read tools for cards, decks, and collection"
```

---

### Task 7: MCP server controller, route, and token auth

**Files:**
- Create: `app/controllers/mcp/server_controller.rb`
- Modify: `config/routes.rb`
- Test: `test/integration/mcp_server_test.rb`

**Interfaces:**
- Consumes: all eight tool classes (Tasks 5–6), `User#api_token` (Task 1).
- Route: `match "mcp", to: "mcp/server#handle", via: %i[get post delete]`, placed OUTSIDE `authenticate :user do`.
- `Mcp::ServerController#handle` authenticates the Bearer token → `@current_user`, builds `MCP::Server` with `server_context: { user: @current_user }`, and drives it via `StreamableHTTPTransport` (stateless). Missing/invalid token → HTTP 401 before any tool runs.

> **Verification note for the implementer:** the exact return shape of `transport.handle_request(request)` and how to render it are the one integration point that must be confirmed by the Step-3 test. If `render json: body.first` produces a double-encoded or empty body, switch to `render body: Array(body).join, content_type: "application/json"` (and copy `Content-Type` from the returned headers). The test asserts on the DB side-effect + HTTP status, so it will pass regardless of the exact body encoding once the transport is wired correctly. If a bare `tools/call` is rejected because the transport requires an `initialize` handshake first, keep `stateless: true` (which permits direct calls); only if that still fails, send an `initialize` request in the test before the `tools/call`.

- [ ] **Step 1: Write the failing test**

Create `test/integration/mcp_server_test.rb`:

```ruby
require "test_helper"

class McpServerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    @user.regenerate_api_token
    @user.save!
    @card = cards(:trainer_card)
  end

  def rpc(name, arguments)
    { jsonrpc: "2.0", id: 1, method: "tools/call",
      params: { name: name, arguments: arguments } }.to_json
  end

  def auth_headers(token: @user.api_token)
    {
      "Authorization" => "Bearer #{token}",
      "Content-Type" => "application/json",
      "Accept" => "application/json, text/event-stream"
    }
  end

  test "rejects a request without a valid token" do
    post "/mcp", params: rpc("list_decks", {}), headers: auth_headers(token: "not-a-real-token")

    assert_response :unauthorized
  end

  test "rejects a request with no Authorization header" do
    post "/mcp", params: rpc("list_decks", {}), headers: { "Content-Type" => "application/json" }

    assert_response :unauthorized
  end

  test "runs a tool call scoped to the authenticated user" do
    assert_nil @user.collections.find_by(card: @card)

    post "/mcp", params: rpc("add_card_to_collection", { card_id: @card.id, quantity: 2 }), headers: auth_headers

    assert_response :success
    assert_equal 2, @user.collections.find_by(card: @card).quantity
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bin/rails test test/integration/mcp_server_test.rb -v`
Expected: FAIL — routing error (no `/mcp` route) / `Mcp::ServerController` missing.

- [ ] **Step 3: Add the route**

In `config/routes.rb`, add this line at the top level, right after the `get "up" => ...` health-check line (it must NOT be inside the `authenticate :user do` block):

```ruby
  # MCP server — authenticated by per-user API token (Authorization: Bearer),
  # so it lives outside the Devise session-authenticated block.
  match "mcp", to: "mcp/server#handle", via: %i[get post delete]
```

- [ ] **Step 4: Write the controller**

Create `app/controllers/mcp/server_controller.rb`:

```ruby
module Mcp
  class ServerController < ActionController::API
    TOOLS = [
      AddCardToCollectionTool,
      AddCardToDeckTool,
      MoveCardToDeckTool,
      MoveCardFromDeckTool,
      SearchCardsTool,
      ListDecksTool,
      ListCollectionTool,
      ListDeckCardsTool
    ].freeze

    before_action :authenticate_token!

    def handle
      server = MCP::Server.new(
        name: "cartodex",
        version: "1.0.0",
        tools: TOOLS,
        server_context: { user: @current_user }
      )
      transport = MCP::Server::Transports::StreamableHTTPTransport.new(server, stateless: true)
      status, headers, body = transport.handle_request(request)

      headers&.each { |key, value| response.set_header(key, value) }
      render json: body.first, status: status
    end

    private

    def authenticate_token!
      token = request.headers["Authorization"].to_s.delete_prefix("Bearer ").strip
      @current_user = User.find_by(api_token: token) if token.present?
      head :unauthorized unless @current_user
    end
  end
end
```

- [ ] **Step 5: Run test to verify it passes**

Run: `bin/rails test test/integration/mcp_server_test.rb -v`
Expected: PASS. If it fails on the third test's rendering/handshake, apply the fallbacks in the Verification note above, then re-run until green.

- [ ] **Step 6: Commit**

```bash
git add app/controllers/mcp/server_controller.rb config/routes.rb test/integration/mcp_server_test.rb
git commit -m "feat: mount MCP server controller with per-user token auth"
```

---

### Task 8: Full suite, lint, and security scan

**Files:** none (verification only).

- [ ] **Step 1: Run the whole test suite**

Run: `bin/rails db:test:prepare test`
Expected: PASS, no failures/errors.

- [ ] **Step 2: Lint**

Run: `bin/rubocop`
Expected: no offenses. Fix any style offenses in the new files and re-run.

- [ ] **Step 3: Security scan**

Run: `bin/brakeman --no-pager`
Expected: no new warnings. If Brakeman flags the unauthenticated `handle` action (token auth isn't recognized as authentication), confirm it's a false positive in the report and, if warranted, add a Brakeman ignore entry via `bin/brakeman -I` (document why: the action authenticates via `authenticate_token!`).

- [ ] **Step 4: Commit any lint/security fixups**

```bash
git add -A
git commit -m "chore: satisfy rubocop and brakeman for MCP server"
```

---

## Manual verification (after implementation)

1. Get a token: `bin/rails 'mcp:token[your-email@example.com]'`.
2. Register the server with your MCP client. For Claude Code:
   `claude mcp add --transport http cartodex http://localhost:3000/mcp --header "Authorization: Bearer <token>"`
   (start the app with `bin/dev` first).
3. Ask the assistant to "search for Honedge", "add 4 to my collection", "list my decks", "move 2 into deck N", "move them back out" — and confirm the collection/deck quantities in the app UI.

## Self-review notes

- **Spec coverage:** add-to-collection (Task 5 `AddCardToCollectionTool`), link-to-deck (Task 5 `AddCardToDeckTool`), move collection→deck (Task 5 `MoveCardToDeckTool`), move deck→collection (Task 5 `MoveCardFromDeckTool`), per-user Bearer token (Tasks 1 & 7), transfer semantics/flooring (Task 4), by-id + read tools (Task 6), mounted HTTP endpoint (Task 7). All covered.
- **Type consistency:** `Decks::CardTransfer::Result#collection_quantity` / `#deck_quantity` used consistently in Tasks 4–5; `server_context` is a Hash with `:user`; tool responses always `MCP::Tool::Response.new([{type:, text:}])`.
