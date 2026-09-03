require "test_helper"

class Api::DecksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  # --- Create action ---

  # The API cannot declare a format, so a deck created through it is always
  # Standard by the column default; without an anchor it would be unsavable.
  test "create anchors a new deck to the current standard pool" do
    post api_decks_path, params: { deck: { name: "New Deck" } }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    deck = Deck.find_by!(key: json["key"])
    assert_equal StandardPool.current, deck.standard_pool
  end

  # --- Import action ---

  test "import enqueues Decks::ImportJob and returns 202" do
    decklist = "4 Honedge POR 56"

    assert_enqueued_with(job: Decks::ImportJob) do
      post import_api_decks_path, params: { name: "My Deck", decklist: decklist }, as: :json
    end

    assert_response :accepted
    json = JSON.parse(response.body)
    assert json["import_id"].present?, "Response should include an import_id"
  end

  test "import requires authentication" do
    sign_out @user

    post import_api_decks_path, params: { name: "My Deck", decklist: "4 Honedge POR 56" }, as: :json

    assert_response :unauthorized
  end

  # --- Suggested archetype action ---

  test "suggested_archetype returns a matching archetype" do
    deck = @user.decks.create!(name: "Ogerpon", standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)

    get suggested_archetype_api_deck_path(deck)

    assert_response :success
    json = JSON.parse(response.body)
    assert json["matched"]
    assert_equal archetypes(:ogerpon).id, json["archetype"]["id"]
  end

  test "suggested_archetype returns candidate Pokémon when nothing matches" do
    deck = @user.decks.create!(name: "Budew pile", standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)

    get suggested_archetype_api_deck_path(deck)

    assert_response :success
    json = JSON.parse(response.body)
    assert_not json["matched"]
    assert_equal cards(:budew_pre).id, json["suggested_primary"]["id"]
  end

  test "suggested_archetype is scoped to the current user" do
    other = users(:two).decks.create!(name: "Theirs", standard_pool: standard_pools(:twm_por))

    get suggested_archetype_api_deck_path(other)

    assert_response :not_found
  end

  test "deck json identifies the deck by its key and never by its id" do
    deck = decks(:one)

    get api_deck_path(deck), as: :json

    assert_response :success
    body = response.parsed_body
    assert_equal deck.key, body["key"]
    assert_nil body["id"]
  end

  test "deck_json includes physical, tcg_live and per-card allocation" do
    deck = @user.decks.create!(name: "Phys", physical: true, tcg_live: false, standard_pool: standard_pools(:twm_por))
    deck.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 2)

    get api_deck_path(deck)

    json = JSON.parse(response.body)
    assert_equal true, json["physical"]
    assert_equal false, json["tcg_live"]
    card_row = json["cards"].first
    assert_equal 2, card_row["owned_copies"]
    assert_equal 1, card_row["proxies"]
  end
end
