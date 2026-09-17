require "test_helper"

class Decks::BulkCardAdderTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)              # user one; not physical until a test says so
    @honedge = cards(:honedge)       # POR 56 — user one's only owned printing
    @doublade = cards(:doublade)     # POR 57
  end

  def resolved(*pairs)
    pairs.map { |card, quantity| { card: card, quantity: quantity } }
  end

  def physical!
    @deck.update!(physical: true)
    @deck
  end

  def second_physical_deck
    @user.decks.create!(name: "Rival", physical: true, standard_pool: standard_pools(:twm_por))
  end

  # Availability must be read with `excluding_deck:`, or the deck competes with itself: its own
  # committed copies are counted against it and the add backs one real copy fewer than it may.
  test "a deck does not compete with its own committed copies" do
    collections(:one).update!(quantity: 3)
    physical!
    deck_cards(:one).update!(quantity: 1, owned_copies: 1)

    Decks::BulkCardAdder.call(deck: @deck, resolved: resolved([ @honedge, 2 ]))
    row = @deck.deck_cards.find_by(card: @honedge)

    assert_equal 3, row.quantity
    assert_equal 3, row.owned_copies,
      "the deck's own committed copy was counted against it: excluding_deck: is not being passed"
  end

  # The other half of the backing rule: `current_owned` is what stops the exclusion reading as a
  # ceiling and demoting a real copy on every edit. It only shows when the pool has shrunk below
  # what the deck already backs, which a second physical deck of the same user produces.
  test "an add never demotes a real copy the deck already backs" do
    collections(:one).update!(quantity: 3)
    physical!
    deck_cards(:one).update!(quantity: 2, owned_copies: 2)
    second_physical_deck.deck_cards.create!(card: @honedge, quantity: 2, owned_copies: 2)

    Decks::BulkCardAdder.call(deck: @deck, resolved: resolved([ @honedge, 1 ]))
    row = @deck.deck_cards.find_by(card: @honedge)

    assert_equal 3, row.quantity
    assert_equal 2, row.owned_copies,
      "the row was demoted to what the shrunken pool alone allows: current_owned is not being passed"
  end

  test "the greedy cap leaves proxies when the collection cannot back the whole row" do
    collections(:one).update!(quantity: 1)
    physical!

    Decks::BulkCardAdder.call(deck: @deck, resolved: resolved([ @honedge, 3 ]))
    row = @deck.deck_cards.find_by(card: @honedge)

    assert_equal 4, row.quantity
    assert_equal 1, row.owned_copies
  end

  test "a non-physical deck backs nothing" do
    collections(:one).update!(quantity: 3)

    Decks::BulkCardAdder.call(deck: @deck, resolved: resolved([ @honedge, 2 ]))
    row = @deck.deck_cards.find_by(card: @honedge)

    assert_equal 3, row.quantity
    assert_equal 0, row.owned_copies
  end

  # Both arms from the same starting state on the same deck, the first rolled back: run the loop
  # arm on a second deck instead and the two legitimately disagree, because the first arm has
  # already consumed the collection.
  test "it agrees row for row with a Decks::CardAdder loop" do
    collections(:one).update!(quantity: 3)
    physical!
    batch = resolved([ @honedge, 2 ], [ @doublade, 2 ])

    bulk = nil
    ActiveRecord::Base.transaction(requires_new: true) do
      bulk = Decks::BulkCardAdder.call(deck: @deck, resolved: batch)
              .map { |entry| entry.values_at("card_id", "after", "owned_after") }
      raise ActiveRecord::Rollback
    end

    looped = batch.map do |row|
      deck_card = Decks::CardAdder.call(deck: @deck.reload, card: row[:card], quantity: row[:quantity])
      [ row[:card].id, deck_card.quantity, deck_card.owned_copies ]
    end

    assert_equal looped, bulk
  end

  test "the receipt carries String keys and the owned copies on both sides of the add" do
    collections(:one).update!(quantity: 3)
    physical!
    deck_cards(:one).update!(quantity: 1, owned_copies: 1)

    receipt = Decks::BulkCardAdder.call(deck: @deck, resolved: resolved([ @honedge, 2 ]))
    round_tripped = JSON.parse(receipt.to_json)

    assert_equal receipt, round_tripped, "receipt keys did not survive the JSON round trip"
    assert_equal({ "set_name" => "POR", "set_number" => "56", "name" => "Honedge", "quantity" => 2,
                   "before" => 1, "after" => 3, "owned_before" => 1, "owned_after" => 3 },
                 round_tripped.first.except("card_id"))
  end

  # On a virtual deck, so that the unsaved card fails at the *write* and the earlier row has
  # already landed: on a physical one it would fail in the availability read, before anything was
  # written, and the test would prove nothing about the transaction. The exception class is not the
  # point — a database constraint and a model validation are both "this row cannot be saved".
  test "a row that cannot be saved rolls the whole batch back" do
    assert_no_difference -> { DeckCard.count } do
      assert_raises(ActiveRecord::ActiveRecordError) do
        Decks::BulkCardAdder.call(deck: @deck, resolved: resolved([ @doublade, 2 ], [ Card.new, 1 ]))
      end
    end

    assert_nil @deck.deck_cards.find_by(card: @doublade), "the first row survived the rollback"
  end

  # `physical?` and `user` are read off an object the caller loaded *before* Cards::ReferenceResolver
  # ran, and on this path that gap is seconds — the resolve, plus any wait for SQLite's single write
  # lock — where the per-card path had two statements. A deck turned virtual in between has had its
  # rows zeroed by Deck#release_owned_copies_if_not_physical, and an adder still holding the old flag
  # would hand it real copies again.
  test "a deck turned virtual while the references were resolving is backed by nothing" do
    collections(:one).update!(quantity: 3)
    physical!
    stale = Deck.find(@deck.id)              # what the tool is holding
    Deck.find(@deck.id).update!(physical: false)   # somebody else flips it underneath

    Decks::BulkCardAdder.call(deck: stale, resolved: resolved([ @honedge, 2 ]))

    assert_equal 0, stale.deck_cards.find_by(card: @honedge).reload.owned_copies,
      "a virtual deck came out of the batch holding real copies"
  end

  # The literal, not "the two counts agree": the per-row write is legitimately not flat, so a
  # comparison of totals is satisfied by a per-row Availability.call as readily as by one batched
  # read. Three is what Availability.for_cards costs with excluding_deck: — one grouped SUM over
  # collections, two over deck_cards.
  OWNED_SUM = /SUM\("collections"\."quantity"\)/
  COMMITTED_SUM = /SUM\("deck_cards"\."owned_copies"\)/

  test "availability costs three statements whatever the decklist size" do
    physical!

    [ 4, 30 ].each do |size|
      cards = Array.new(size) { |n| minted_card("#{size}-#{n}") }
      statements = capture_queries do
        ActiveRecord::Base.uncached do
          Decks::BulkCardAdder.call(deck: @deck.reload, resolved: resolved(*cards.map { |c| [ c, 1 ] }))
        end
      end

      assert_equal 1, statements.grep(OWNED_SUM).size, "owned was read #{statements.grep(OWNED_SUM).size}× at #{size} printings"
      assert_equal 2, statements.grep(COMMITTED_SUM).size,
        "committed was read #{statements.grep(COMMITTED_SUM).size}× at #{size} printings; availability is no longer batched"
    end
  end

  private

  def minted_card(suffix)
    Card.create!(name: "Bulk Probe #{suffix}", card_type: "Trainer", set_name: "ZZY",
                 set_number: suffix.to_s, rarity: "Common")
  end
end
