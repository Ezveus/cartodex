require "test_helper"

class Api::CollectionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @card = cards(:budew_pre)
  end

  test "collection_json includes owned/committed/available" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 4)
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
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 1)

    post api_collections_path,
      params: { collection: { card_id: @card.id, quantity: 2 } }, as: :json

    assert_response :created
    assert_equal 3, JSON.parse(response.body)["quantity"]
  end

  test "update sets exact quantity via QuantitySetter" do
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 5)

    patch api_collection_path(@card),
      params: { collection: { quantity: 2 } }, as: :json

    assert_response :success
    assert_equal 2, JSON.parse(response.body)["quantity"]
  end

  test "index issues a constant number of queries regardless of collection size" do
    get api_collections_path # warm the session: the first request of a test also loads the Devise user

    small = count_queries { get api_collections_path }

    [ :doublade, :trainer_card, :froakie_cri, :basic_psychic_energy ].each do |name|
      @user.collections.find_or_create_by!(card: cards(name)) { |c| c.quantity = 0 }.update!(quantity: 2)
    end

    large = count_queries { get api_collections_path }

    assert_response :success
    assert_equal small, large, "query count grew with the collection: #{small} -> #{large}"
  end

  test "index still reports owned, committed and available per row" do
    card = cards(:honedge)
    @user.collections.find_or_create_by!(card: card) { |c| c.quantity = 0 }.update!(quantity: 3)
    deck = @user.decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: card, quantity: 2, owned_copies: 2)

    get api_collections_path
    row = JSON.parse(response.body)["collections"].find { |c| c["card_id"] == card.id }

    assert_equal [ 3, 2, 1 ], [ row["owned"], row["committed"], row["available"] ]
  end
end
