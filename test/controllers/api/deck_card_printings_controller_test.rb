require "test_helper"

class Api::DeckCardPrintingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # budew_pre and budew_asc share fingerprint "budew_shared" in fixtures.
    @user = users(:one)
    sign_in @user
    @asc = cards(:budew_asc)
    @pre = cards(:budew_pre)
    @deck = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
  end

  test "index lists every printing of the card, annotated for this deck" do
    @user.collections.find_by!(card: @pre).update!(quantity: 2)
    @deck.deck_cards.create!(card: @asc, quantity: 3)

    get api_deck_card_printings_path(@deck, @asc)

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [ @asc.id, @pre.id ].sort, json.map { |p| p["card_id"] }.sort

    pre = json.find { |p| p["card_id"] == @pre.id }
    assert_equal 2, pre["owned"]
    assert_equal 2, pre["real_after"]
    assert_equal 1, pre["proxies_after"]
    assert json.find { |p| p["card_id"] == @asc.id }["current"]
  end

  test "index is scoped to the signed-in user's decks" do
    other_deck = users(:two).decks.create!(name: "Theirs", standard_pool: standard_pools(:twm_por))
    other_deck.deck_cards.create!(card: @asc, quantity: 1)

    get api_deck_card_printings_path(other_deck, @asc)

    assert_response :not_found
  end

  test "update swaps the slot to the target printing" do
    @user.collections.find_by!(card: @asc).update!(quantity: 2)
    @deck.deck_cards.create!(card: @asc, quantity: 3, owned_copies: 2)

    patch api_deck_card_printing_path(@deck, @asc),
      params: { printing: { card_id: @pre.id } }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal @pre.id, json["card"]["id"]
    assert_equal "PRE", json["card"]["set_name"]
    assert_equal 3, json["quantity"]
    assert_equal 0, json["owned_copies"], "the PRE printing is not owned, so the row is all proxies"
    assert_equal false, json["merged"]
    assert json["deck"]["has_proxies"], "the deck-wide badge state travels with every write"
  end

  test "update merges into an existing row for the target printing" do
    @deck.deck_cards.create!(card: @asc, quantity: 2)
    @deck.deck_cards.create!(card: @pre, quantity: 1)

    patch api_deck_card_printing_path(@deck, @asc),
      params: { printing: { card_id: @pre.id } }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 3, json["quantity"]
    assert_equal true, json["merged"]
    assert_equal [ @pre.id ], @deck.deck_cards.reload.map(&:card_id)
  end

  test "update reports how many copies the stepper may still back" do
    @user.collections.find_by!(card: @pre).update!(quantity: 1)
    @deck.deck_cards.create!(card: @asc, quantity: 3)

    patch api_deck_card_printing_path(@deck, @asc),
      params: { printing: { card_id: @pre.id } }, as: :json

    assert_equal 1, JSON.parse(response.body)["max_owned"]
  end

  test "update reports the over-allocation the target printing is already in" do
    # Another deck holds two real copies of a printing the user owns one of: the swap cannot fix
    # that, and the row it lands on has to show the marker the page would render on a reload.
    @user.collections.find_by!(card: @pre).update!(quantity: 1)
    other = @user.decks.create!(name: "Other", physical: true, standard_pool: standard_pools(:twm_por))
    other.deck_cards.create!(card: @pre, quantity: 2, owned_copies: 2)
    @deck.deck_cards.create!(card: @asc, quantity: 1)

    patch api_deck_card_printing_path(@deck, @asc),
      params: { printing: { card_id: @pre.id } }, as: :json

    assert JSON.parse(response.body)["over_allocated"]
  end

  test "update sends the new printing's image so the preview follows the row" do
    @asc.update!(image_url: "https://example.test/asc.png")
    @pre.update!(image_url: "https://example.test/pre.png")
    @deck.deck_cards.create!(card: @asc, quantity: 1)

    patch api_deck_card_printing_path(@deck, @asc),
      params: { printing: { card_id: @pre.id } }, as: :json

    assert_equal image_card_path(@pre), JSON.parse(response.body)["image_path"]
  end

  test "update on a non-physical deck answers with no backing to speak of" do
    # A TCG Live deck consumes no collection, so its rows sit at owned_copies 0 by construction and
    # the page renders no allocation stepper for the picker to re-bound.
    live = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))
    live.deck_cards.create!(card: @asc, quantity: 2)
    @user.collections.find_by!(card: @pre).update!(quantity: 4)

    patch api_deck_card_printing_path(live, @asc),
      params: { printing: { card_id: @pre.id } }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 0, json["owned_copies"]
    assert_equal 0, json["max_owned"]
    assert_not json["deck"]["has_proxies"]
  end

  test "update rejects a card that is not another printing" do
    @deck.deck_cards.create!(card: @asc, quantity: 1)

    patch api_deck_card_printing_path(@deck, @asc),
      params: { printing: { card_id: cards(:froakie_cri).id } }, as: :json

    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].present?
  end

  test "update 404s when the deck does not hold the card" do
    patch api_deck_card_printing_path(@deck, @asc),
      params: { printing: { card_id: @pre.id } }, as: :json

    assert_response :not_found
  end
end
