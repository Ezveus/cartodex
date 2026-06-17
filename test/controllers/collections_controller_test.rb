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
end
