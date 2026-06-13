require "test_helper"

class Api::DecksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
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
    deck = @user.decks.create!(name: "Ogerpon")
    deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)

    get suggested_archetype_api_deck_path(deck)

    assert_response :success
    json = JSON.parse(response.body)
    assert json["matched"]
    assert_equal archetypes(:ogerpon).id, json["archetype"]["id"]
  end

  test "suggested_archetype returns candidate Pokémon when nothing matches" do
    deck = @user.decks.create!(name: "Budew pile")
    deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)

    get suggested_archetype_api_deck_path(deck)

    assert_response :success
    json = JSON.parse(response.body)
    assert_not json["matched"]
    assert_equal cards(:budew_pre).id, json["primary_pokemon"]["id"]
  end

  test "suggested_archetype is scoped to the current user" do
    other = users(:two).decks.create!(name: "Theirs")

    get suggested_archetype_api_deck_path(other)

    assert_response :not_found
  end
end
