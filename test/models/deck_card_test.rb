require "test_helper"

class DeckCardTest < ActiveSupport::TestCase
  test "owned_copies defaults to 0" do
    deck = decks(:one)
    dc = deck.deck_cards.create!(card: cards(:trainer_card), quantity: 2)
    assert_equal 0, dc.owned_copies
  end

  test "owned_copies cannot exceed quantity" do
    deck = users(:one).decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
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
    deck = users(:one).decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    dc = deck.deck_cards.new(card: cards(:honedge), quantity: 2, owned_copies: 2)
    assert dc.valid?
  end

  test "is unique per deck and card" do
    deck = decks(:one)
    card = cards(:trainer_card)
    deck.deck_cards.create!(card: card, quantity: 1)
    dup = deck.deck_cards.build(card: card, quantity: 1)
    assert_not dup.valid?
    assert_includes dup.errors[:card_id], "has already been taken"
  end

  test "proxies is quantity minus owned_copies" do
    deck = users(:one).decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    dc = deck.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 1)
    assert_equal 2, dc.proxies
  end

  test "proxies is zero when fully backed" do
    deck = users(:one).decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    dc = deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)
    assert_equal 0, dc.proxies
  end

  test "with_proxies selects the rows carrying at least one proxy" do
    deck = users(:one).decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    proxied = deck.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 1)
    backed = deck.deck_cards.create!(card: cards(:doublade), quantity: 2, owned_copies: 2)

    assert_includes DeckCard.with_proxies, proxied
    assert_not_includes DeckCard.with_proxies, backed
  end

  # /decks sorts on decks.updated_at, and editing the list is editing the deck. Each write is
  # travelled a day ahead of the last so that a touch cannot hide inside the same second.
  test "creating, requantifying and removing a card each move the deck's updated_at" do
    deck = decks(:one)
    deck.update_columns(updated_at: 3.days.ago)

    travel_to(2.days.ago) { @row = deck.deck_cards.create!(card: cards(:doublade), quantity: 1) }
    assert_in_delta 2.days.ago, deck.reload.updated_at, 1.minute

    travel_to(1.day.ago) { @row.update!(quantity: 2) }
    assert_in_delta 1.day.ago, deck.reload.updated_at, 1.minute

    @row.destroy!
    assert_in_delta Time.current, deck.reload.updated_at, 1.minute
  end

  # belongs_to's touch goes through touch_later, which folds every touch of one transaction into a
  # single UPDATE. Without that, a 60-card import would add 60 statements inside Decks::Fetcher's
  # BEGIN IMMEDIATE, the one write lock the whole app shares.
  test "a bulk add touches its deck with a single UPDATE" do
    deck = decks(:one)
    updates = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      updates << payload[:sql] if payload[:sql].match?(/\AUPDATE "decks"/)
    end

    Decks::BulkCardAdder.call(deck: deck, resolved: [
      { card: cards(:doublade), quantity: 2 },
      { card: cards(:trainer_card), quantity: 3 },
      { card: cards(:teal_mask_ogerpon_ex), quantity: 1 }
    ])

    assert_equal 1, updates.size, updates.join("\n")
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end
end
