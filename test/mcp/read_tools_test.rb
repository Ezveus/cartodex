require "test_helper"
require "json"

class ReadToolsTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @context = { user: @user }
  end

  def payload(response)
    JSON.parse(response.content.first[:text])
  end

  test "SearchCardsTool finds cards by name substring" do
    response = SearchCardsTool.call(query: "honed", server_context: @context)
    names = payload(response).map { |c| c["name"] }

    assert_includes names, "Honedge"
  end

  test "ListDecksTool returns only the user's decks" do
    response = ListDecksTool.call(server_context: @context)
    ids = payload(response).map { |d| d["id"] }

    assert_includes ids, decks(:one).id
    assert_not_includes ids, decks(:two).id
  end

  test "ListCollectionTool returns the user's collection entries" do
    response = ListCollectionTool.call(server_context: @context)
    card_ids = payload(response).map { |c| c["card_id"] }

    assert_includes card_ids, cards(:honedge).id
  end

  test "ListDeckCardsTool returns the cards in an owned deck" do
    response = ListDeckCardsTool.call(deck_id: decks(:one).id, server_context: @context)
    card_ids = payload(response).map { |c| c["card_id"] }

    assert_includes card_ids, cards(:honedge).id
  end

  test "ListDeckCardsTool reports an error for a deck the user does not own" do
    response = ListDeckCardsTool.call(deck_id: decks(:two).id, server_context: @context)

    assert_match(/Error/i, response.content.first[:text])
  end
end
