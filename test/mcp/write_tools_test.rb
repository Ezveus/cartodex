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
    AddCardToDeckTool.call(deck_key: @deck.key, card_id: @card.id, quantity: 2, server_context: @context)

    assert_equal 3, @deck.deck_cards.find_by(card: @card).quantity
    assert_equal 1, @user.collections.find_by(card: @card).quantity
  end

  test "deck tools reject a deck the user does not own" do
    other_deck = decks(:two) # user two

    response = AddCardToDeckTool.call(deck_key: other_deck.key, card_id: @card.id, quantity: 1, server_context: @context)

    assert_match(/Error/i, response_text(response))
  end

  test "AddCardToCollectionTool rejects a non-positive quantity without decrementing" do
    # A direct call bypasses the JSON-schema minimum, so the tool guards explicitly:
    # a negative quantity must error rather than silently decrement the collection.
    response = AddCardToCollectionTool.call(card_id: @card.id, quantity: -1, server_context: @context)

    assert_match(/positive integer/i, response_text(response))
    assert_equal 1, @user.collections.find_by(card: @card).quantity # unchanged
  end

  test "AddCardToDeckTool rejects a non-positive quantity without touching the deck" do
    response = AddCardToDeckTool.call(deck_key: @deck.key, card_id: @card.id, quantity: 0, server_context: @context)

    assert_match(/positive integer/i, response_text(response))
    assert_equal 1, @deck.deck_cards.find_by(card: @card).quantity # unchanged
  end

  test "SetCollectionQuantityTool sets the owned quantity" do
    SetCollectionQuantityTool.call(card_id: @card.id, quantity: 7, server_context: @context)

    assert_equal 7, @user.collections.find_by(card: @card).quantity
  end

  test "SetCollectionQuantityTool rejects a negative quantity with a clean error" do
    response = SetCollectionQuantityTool.call(card_id: @card.id, quantity: -1, server_context: @context)

    assert_match(/must be/i, response_text(response))
  end

  test "AddCardToDeckTool backs reals on a physical deck" do
    physical = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    @user.collections.find_by(card: @card).update!(quantity: 2) # honedge owned 2

    AddCardToDeckTool.call(deck_key: physical.key, card_id: @card.id, quantity: 3, server_context: @context)

    dc = physical.deck_cards.find_by(card: @card)
    assert_equal 3, dc.quantity
    assert_equal 2, dc.owned_copies
  end

  test "SetDeckCardOwnedCopiesTool adjusts the real/proxy split" do
    physical = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    @user.collections.find_by(card: @card).update!(quantity: 3)
    physical.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)

    SetDeckCardOwnedCopiesTool.call(deck_key: physical.key, card_id: @card.id, owned_copies: 1, server_context: @context)

    assert_equal 1, physical.deck_cards.find_by(card: @card).owned_copies
  end

  test "ReallocateOwnedCopiesTool moves reals between physical decks" do
    @user.collections.find_by(card: @card).update!(quantity: 3)
    a = @user.decks.create!(name: "A", physical: true, standard_pool: standard_pools(:twm_por))
    b = @user.decks.create!(name: "B", physical: true, standard_pool: standard_pools(:twm_por))
    a.deck_cards.create!(card: @card, quantity: 4, owned_copies: 3)
    b.deck_cards.create!(card: @card, quantity: 4, owned_copies: 0)

    ReallocateOwnedCopiesTool.call(from_deck_key: a.key, to_deck_key: b.key, card_id: @card.id, quantity: 1, server_context: @context)

    assert_equal 2, a.deck_cards.find_by(card: @card).owned_copies
    assert_equal 1, b.deck_cards.find_by(card: @card).owned_copies
  end

  test "SetDeckCardQuantityTool removes the card when quantity is 0" do
    physical = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    physical.deck_cards.create!(card: @card, quantity: 2)

    SetDeckCardQuantityTool.call(deck_key: physical.key, card_id: @card.id, quantity: 0, server_context: @context)

    assert_nil physical.deck_cards.find_by(card: @card)
  end

  test "SetDeckCardQuantityTool returns a clean error for non-integer quantity" do
    physical = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    physical.deck_cards.create!(card: @card, quantity: 2)

    response = SetDeckCardQuantityTool.call(deck_key: physical.key, card_id: @card.id, quantity: "abc", server_context: @context)

    assert_match(/must be an integer/i, response_text(response))
    assert_equal 2, physical.deck_cards.find_by(card: @card).quantity # not destroyed
  end

  test "AddCardToDeckTool suggests owned equivalents when a physical add makes proxies" do
    physical = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    # own an equivalent printing (budew_pre) but not the exact one (budew_asc)
    @user.collections.find_or_create_by!(card: cards(:budew_pre)).update!(quantity: 2)

    response = AddCardToDeckTool.call(deck_key: physical.key, card_id: cards(:budew_asc).id, quantity: 2, server_context: @context)

    assert_match(/equivalent/i, response_text(response))
    assert_match(/Budew/, response_text(response))
  end

  test "SetDeckCardPrintingTool moves the slot to another printing" do
    physical = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    physical.deck_cards.create!(card: cards(:budew_asc), quantity: 3)

    response = SetDeckCardPrintingTool.call(
      deck_key: physical.key, card_id: cards(:budew_asc).id,
      target_card_id: cards(:budew_pre).id, server_context: @context
    )

    assert_equal [ cards(:budew_pre).id ], physical.deck_cards.reload.map(&:card_id)
    assert_match(/PRE 4/, response_text(response))
    assert_match(/3 proxy/, response_text(response))
  end

  test "SetDeckCardPrintingTool refuses a card that is not another printing" do
    physical = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
    physical.deck_cards.create!(card: cards(:budew_asc), quantity: 1)

    response = SetDeckCardPrintingTool.call(
      deck_key: physical.key, card_id: cards(:budew_asc).id,
      target_card_id: cards(:froakie_cri).id, server_context: @context
    )

    assert_match(/Error/i, response_text(response))
    assert_equal [ cards(:budew_asc).id ], physical.deck_cards.reload.map(&:card_id)
  end

  test "SetDeckCardPrintingTool reports a card the deck does not hold" do
    physical = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))

    response = SetDeckCardPrintingTool.call(
      deck_key: physical.key, card_id: cards(:budew_asc).id,
      target_card_id: cards(:budew_pre).id, server_context: @context
    )

    assert_match(/Error/i, response_text(response))
  end

  test "a client can reallocate using only the keys the over-allocation report gave it" do
    over_allocate(cards(:honedge), owned: 1, committed: 2)
    target = @user.decks.create!(name: "Target", physical: true, standard_pool: standard_pools(:twm_por))
    target.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 0)

    report = JSON.parse(response_text(ListOverAllocationsTool.call(server_context: @context)))
    source_key = report.first["decks"].first["key"]

    response = ReallocateOwnedCopiesTool.call(
      from_deck_key: source_key, to_deck_key: target.key,
      card_id: cards(:honedge).id, quantity: 1, server_context: @context
    )

    # A presence assertion proves the field exists; only chaining the two tools proves a
    # client can act on what it just read.
    refute_match(/unknown deck/, response_text(response))
    assert_equal 1, target.deck_cards.find_by(card: cards(:honedge)).owned_copies
  end
end
