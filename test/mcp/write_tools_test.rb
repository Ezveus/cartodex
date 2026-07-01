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

  test "AddCardToCollectionTool returns a clean error for an invalid quantity" do
    # honedge collection qty is 1; subtracting via a negative add drives it below 0, tripping Collection's quantity >= 0 validation
    response = AddCardToCollectionTool.call(card_id: @card.id, quantity: -5, server_context: @context)
    assert_match(/Error/i, response_text(response))
  end
end
