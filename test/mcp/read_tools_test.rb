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

  test "SearchCardsTool treats an underscore in the query as a literal, not a wildcard" do
    assert_includes payload(SearchCardsTool.call(query: "budew", server_context: @context)).map { |c| c["name"] },
      "Budew", "sanity: the unescaped spelling must match"

    response = SearchCardsTool.call(query: "b_dew", server_context: @context)

    assert_empty payload(response)
  end

  test "SearchCardsTool treats a percent sign in the query as a literal, not a wildcard" do
    response = SearchCardsTool.call(query: "bud%w", server_context: @context)

    assert_empty payload(response)
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

  test "SearchCardsTool finds a card when set_code is given in lowercase" do
    response = SearchCardsTool.call(query: "honed", set_code: "por", server_context: @context)
    names = payload(response).map { |c| c["name"] }

    assert_includes names, "Honedge"
  end

  test "SearchCardsTool finds a card when set_code is given in uppercase" do
    response = SearchCardsTool.call(query: "honed", set_code: "POR", server_context: @context)
    names = payload(response).map { |c| c["name"] }

    assert_includes names, "Honedge"
  end

  test "SearchCardsTool clamps a limit of 0 up to at least 1 result" do
    response = SearchCardsTool.call(query: "honed", limit: 0, server_context: @context)
    results = payload(response)

    assert_operator results.size, :>=, 1
    assert_operator results.size, :<=, 1
  end

  test "ListCollectionTool with a matching query returns that entry" do
    response = ListCollectionTool.call(query: "honed", server_context: @context)
    card_ids = payload(response).map { |c| c["card_id"] }

    assert_includes card_ids, cards(:honedge).id
  end

  test "ListCollectionTool with a non-matching query returns an empty array" do
    response = ListCollectionTool.call(query: "zzz_no_such_card", server_context: @context)

    assert_equal [], payload(response)
  end

  test "ListDeckCardsTool exposes owned_copies and proxies" do
    physical = @user.decks.create!(name: "Phys", physical: true)
    @user.collections.find_or_create_by!(card: cards(:honedge)).update!(quantity: 1)
    physical.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 1)

    response = ListDeckCardsTool.call(deck_id: physical.id, server_context: @context)
    entry = payload(response).find { |c| c["card_id"] == cards(:honedge).id }

    assert_equal 3, entry["quantity"]
    assert_equal 1, entry["owned_copies"]
    assert_equal 2, entry["proxies"]
  end

  test "ListCollectionTool exposes owned, committed and available" do
    card = cards(:honedge)
    @user.collections.find_or_create_by!(card: card).update!(quantity: 3)
    deck = @user.decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: card, quantity: 2, owned_copies: 2)

    response = ListCollectionTool.call(server_context: @context)
    entry = payload(response).find { |c| c["card_id"] == card.id }

    assert_equal 3, entry["owned"]
    assert_equal 2, entry["committed"]
    assert_equal 1, entry["available"]
  end

  test "ListOverAllocationsTool reports over-committed cards" do
    card = cards(:honedge)
    @user.collections.find_or_create_by!(card: card).update!(quantity: 1)
    deck = @user.decks.create!(name: "Phys", physical: true)
    deck.deck_cards.create!(card: card, quantity: 2, owned_copies: 2)

    response = ListOverAllocationsTool.call(server_context: @context)
    card_ids = payload(response).map { |e| e["card_id"] }

    assert_includes card_ids, card.id
  end

  test "SuggestOwnedEquivalentsTool lists owned equivalent printings" do
    @user.collections.find_or_create_by!(card: cards(:budew_pre)).update!(quantity: 2)

    response = SuggestOwnedEquivalentsTool.call(card_id: cards(:budew_asc).id, server_context: @context)
    card_ids = payload(response).map { |e| e["card_id"] }

    assert_includes card_ids, cards(:budew_pre).id
  end
end
