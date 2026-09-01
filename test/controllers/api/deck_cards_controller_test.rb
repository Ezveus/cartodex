require "test_helper"

class Api::DeckCardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @card = cards(:honedge)
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 3)
    @deck = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
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

    assert_response :success
    assert JSON.parse(response.body)["removed"]
    assert_nil @deck.deck_cards.find_by(card: @card)
  end

  # The deck page edits cards in place, so a write that flips the deck's proxy state has to say so
  # in its own response — nothing else will tell the header before the next full load.

  test "update owned_copies reports the deck gaining proxies" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { owned_copies: 1 } }, as: :json

    assert_response :success
    assert JSON.parse(response.body)["deck"]["has_proxies"]
  end

  test "update owned_copies reports the deck losing its last proxy" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 1)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { owned_copies: 3 } }, as: :json

    assert_response :success
    assert_not JSON.parse(response.body)["deck"]["has_proxies"]
  end

  # Removing the deck's only unbacked card retires the badge, and the row is gone by then — this is
  # the case a body-less 204 could not report.
  test "removing the last unbacked card reports the deck losing its proxies" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 2, owned_copies: 0)

    patch api_deck_card_path(@deck, cards(:doublade)),
      params: { deck_card: { quantity: 0 } }, as: :json

    assert_response :success
    assert_not JSON.parse(response.body)["deck"]["has_proxies"]
  end

  test "a quantity bump that outruns the owned copies reports the new proxies" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { quantity: 4 } }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["proxies"]
    assert json["deck"]["has_proxies"]
  end

  test "create reports the deck's proxy state" do
    post api_deck_cards_path(@deck),
      params: { deck_card: { card_id: @card.id, quantity: 4 } }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 1, json["proxies"], "only 3 are owned"
    assert json["deck"]["has_proxies"]
  end

  # deck_card_json is shared with #index, which renders one row per card; folding the deck-wide
  # state into it would cost a query per row.
  test "index does not carry the deck state on every row" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 2)

    get api_deck_cards_path(@deck)

    assert_not JSON.parse(response.body).first.key?("deck")
  end
end
