require "test_helper"

class CardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    sign_in users(:one)
  end

  test "index without params shows the empty prompt and the search form" do
    get cards_path

    assert_response :success
    assert_select "p.cards-empty"
    assert_select "form.cards-search"
  end

  test "index filters by name" do
    get cards_path(q: "Honedge")

    assert_response :success
    assert_select ".card-grid-name", text: "Honedge"
    assert_select ".card-grid-name", { text: "Doublade", count: 0 }
  end

  test "index filters by card type" do
    get cards_path(type: "Trainer")

    assert_response :success
    assert_select ".card-grid-name", text: "Boss's Orders", minimum: 1
    assert_select ".card-grid-name", { text: "Honedge", count: 0 }
  end

  test "index filters by energy type" do
    get cards_path(energy: "Metal")

    assert_response :success
    assert_select ".card-grid-name", text: "Honedge"
    assert_select ".card-grid-name", { text: "Budew", count: 0 }
  end

  test "index filters by regulation mark" do
    get cards_path(mark: "H")

    assert_response :success
    assert_select ".card-grid-name", text: "Budew", count: 1
  end

  test "index restricts search to the selected set" do
    get cards_path(q: "Honedge", set: card_sets(:por).code)

    assert_response :success
    assert_select ".card-grid-name", text: "Honedge", count: 1
  end

  test "index returns nothing when search is scoped to an unrelated set" do
    get cards_path(q: "Honedge", set: card_sets(:asc).code)

    assert_response :success
    assert_select "p.cards-empty"
  end

  test "index parses name, set code and number tokens together" do
    get cards_path(q: "Budew ASC 16")

    assert_response :success
    assert_select ".card-grid-name", text: "Budew", count: 1
  end

  test "index without a search shows the selected set grid" do
    get cards_path(set: card_sets(:por).code)

    assert_response :success
    assert_select "turbo-frame#card_results h2", text: card_sets(:por).name
  end

  test "index treats LIKE metacharacters in the query as literals" do
    get cards_path(q: "b_dew")

    assert_response :success
    assert_select ".card-grid-name", { text: "Budew", count: 0 }, "_ must not act as a wildcard"

    get cards_path(q: "bud%w")

    assert_response :success
    assert_select ".card-grid-name", { text: "Budew", count: 0 }, "% must not act as a wildcard"
  end

  test "the cards index does not instantiate the catalog to count it" do
    get cards_path # warm the session and the caches

    assert_no_difference -> { Card.count } do
      # The guard is on rows instantiated, not queries: the sidebar needs a count per set,
      # and includes(:cards) built every Card object in the database to get it.
      records = 0
      subscriber = ActiveSupport::Notifications.subscribe("instantiation.active_record") do |*, payload|
        records += payload[:record_count] if payload[:class_name] == "Card"
      end
      get cards_path
      ActiveSupport::Notifications.unsubscribe(subscriber)

      assert_equal 0, records, "the index instantiated #{records} Card objects without a search"
    end
    assert_response :success
  end

  test "the sidebar still shows a card count per set" do
    get cards_path

    assert_response :success
    assert_select ".set-code", text: /\(\d+\)/
  end
end
