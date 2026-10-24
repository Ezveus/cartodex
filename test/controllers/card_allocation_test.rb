require "test_helper"

# The "Your copies" section of a card's page: owned, committed and available for this exact
# printing, and the physical decks committing real copies of it.
class CardAllocationTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @card = cards(:honedge)
    # Two variant rows of one printing: owned is their sum (3), which the page's own "In collection"
    # counter — one row — does not say.
    @user.collections.find_by!(card: @card).update!(quantity: 2)
    @user.collections.create!(card: @card, quantity: 1, language: "fr", finish: "reverse_holo")
  end

  def deck(name, physical: true, user: @user)
    user.decks.create!(name: name, physical: physical, standard_pool: standard_pools(:twm_por))
  end

  def stat(label)
    css_select(".card-allocation-stat").find { |node| node.at_css("dt").text.strip == label }&.at_css("dd")&.text&.strip
  end

  test "a member sees owned, committed and available, and each deck committing real copies" do
    first = deck("Blade A")
    second = deck("Blade B")
    first.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)
    second.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)
    sign_in @user

    get card_path(@card)

    assert_response :success
    assert_equal "3", stat("Owned")
    assert_equal "3", stat("Committed")
    assert_equal "0", stat("Available")
    rows = css_select(".card-allocation-deck")
    assert_equal [ "Blade A", "Blade B" ], rows.map { |row| row.at_css("a").text.strip }
    assert_equal [ deck_path(first), deck_path(second) ], rows.map { |row| row.at_css("a")["href"] }
    assert_equal [ "2 copies", "1 copy" ], rows.map { |row| row.at_css(".card-allocation-deck-count").text.strip }
    assert_select ".card-allocation-over", count: 0
  end

  test "decks that take no real copy are not listed and do not count" do
    deck("TCG Live", physical: false).deck_cards.create!(card: @card, quantity: 4, owned_copies: 0)
    deck("All proxies").deck_cards.create!(card: @card, quantity: 2, owned_copies: 0)
    deck("Somebody else's", user: users(:two)).deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)
    deck("Mine").deck_cards.create!(card: @card, quantity: 2, owned_copies: 1)
    sign_in @user

    get card_path(@card)

    assert_equal "1", stat("Committed")
    assert_equal "2", stat("Available")
    assert_equal [ "Mine" ], css_select(".card-allocation-deck a").map { |a| a.text.strip }
  end

  test "a printing no deck commits says so rather than printing an empty list" do
    sign_in @user

    get card_path(@card)

    assert_equal "3", stat("Available")
    assert_select ".card-allocation-deck", count: 0
    assert_select ".card-allocation-empty", text: /No physical deck uses a real copy/
  end

  test "an over-allocated printing says by how much and links to the report" do
    deck("Greedy").deck_cards.create!(card: @card, quantity: 4, owned_copies: 4)
    deck("Also greedy").deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)
    sign_in @user

    get card_path(@card)

    assert_equal "0", stat("Available")
    assert_select ".card-allocation-over", text: /2 more copies than you own/
    assert_select ".card-allocation-over a[href=?]", over_allocations_path
  end

  test "an over-allocation by one copy is worded in the singular" do
    deck("Greedy").deck_cards.create!(card: @card, quantity: 4, owned_copies: 4)
    sign_in @user

    get card_path(@card)

    assert_select ".card-allocation-over", text: /1 more copy than you own/
  end

  # The frame the counter reloads must be on the page under the id the reload asks for, or Turbo
  # renders "Content missing" in its place. `_top`, or a deck link would load the deck page into
  # the frame and find no matching frame there.
  test "the section is a frame that reloads from this card's page" do
    sign_in @user

    get card_path(@card)

    assert_select "turbo-frame#card-allocation[target=_top][data-controller=card-allocation]" \
                  "[data-card-allocation-url-value=?][data-action=?]", card_path(@card),
                  "collection-quantity:changed@window->card-allocation#refresh"
  end

  test "a visitor sees no section and the page reads no deck" do
    deck("Blade A").deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    queries = capture_queries { get card_path(@card) }

    assert_response :success
    assert_select "#card-allocation", count: 0
    assert_empty queries.grep(/deck_cards|"collections"/)
  end
end
