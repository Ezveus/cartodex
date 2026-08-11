require "test_helper"

class CollectionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @collection = collections(:one)
    sign_in @user
  end

  test "renders the user's collection" do
    get collections_path

    assert_response :success
    assert_select "h1", text: "My Collection"
    assert_select ".collection-tile-name", text: @collection.card.name
  end

  test "filters by set code" do
    get collections_path(set: @collection.card.card_set&.code || "nope")

    assert_response :success
  end

  test "filters by card type" do
    get collections_path(type: "Pokémon")

    assert_response :success
    assert_select ".collection-tile-name", text: @collection.card.name
  end

  test "ignores invalid type filter" do
    get collections_path(type: "NotAType")

    assert_response :success
  end

  test "search by name" do
    get collections_path(q: @collection.card.name[0, 3])

    assert_response :success
    assert_select ".collection-tile-name", text: @collection.card.name
  end

  test "empty state when no cards match filters" do
    get collections_path(q: "ZZZ_does_not_match_ZZZ")

    assert_response :success
    assert_select ".collection-empty"
  end

  test "shows only the signed-in user's collection" do
    other = collections(:two)
    get collections_path

    assert_response :success
    assert_select ".collection-tile-name", text: @collection.card.name
    assert_select ".collection-tile-name", text: other.card.name, count: 0
  end

  test "search treats LIKE metacharacters as literals" do
    assert_equal "Honedge", @collection.card.name, "sanity: the patterns below target this fixture"

    get collections_path(q: "h_nedge")

    assert_response :success
    assert_select ".collection-tile-name", { text: "Honedge", count: 0 }, "_ must not act as a wildcard"

    get collections_path(q: "hon%ge")

    assert_response :success
    assert_select ".collection-tile-name", { text: "Honedge", count: 0 }, "% must not act as a wildcard"
  end

  # The page rendered one Availability lookup per tile, so its cost grew with
  # the user's collection. It must now be flat.
  test "index issues a constant number of queries regardless of collection size" do
    get collections_path # warm the session: the first request of a test also loads the Devise user

    small = count_queries { get collections_path }

    [ :doublade, :trainer_card, :froakie_cri, :basic_psychic_energy ].each do |name|
      @user.collections.find_or_create_by!(card: cards(name)) { |c| c.quantity = 0 }.update!(quantity: 2)
    end

    large = count_queries { get collections_path }

    assert_response :success
    assert_equal small, large, "query count grew with the collection: #{small} -> #{large}"
  end
end
