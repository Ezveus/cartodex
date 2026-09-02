require "test_helper"

class OverAllocationsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "renders each over-allocated card with the decks holding it" do
    deck = over_allocate(cards(:honedge), owned: 1, committed: 2)

    get over_allocations_path

    assert_response :success
    assert_select ".over-allocation-card", text: "Honedge"
    assert_select ".over-allocation-counts", text: "owned 1 · committed 2"
    assert_select ".over-allocation-deck-link", text: deck.name
  end

  test "each deck link addresses the deck by its key, not its id" do
    deck = over_allocate(cards(:honedge), owned: 1, committed: 2)

    get over_allocations_path

    assert_response :success
    # `deck_path(deck)` goes through to_param; the point of the test is the negative
    # assertion, because this is the one deck_path in the app that to_param cannot fix.
    assert_select ".over-allocation-deck-link[href=?]", deck_path(deck)
    assert_select ".over-allocation-deck-link[href=?]", "/decks/#{deck.id}", count: 0
  end

  test "offers the decks with proxy slots left as reallocation targets" do
    over_allocate(cards(:honedge), owned: 0, committed: 1)
    target = @user.decks.create!(name: "Target", physical: true, standard_pool: standard_pools(:twm_por))
    target.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 0)

    get over_allocations_path

    assert_response :success
    assert_select "select[name=to_deck_id] option[value=?]", target.id.to_s
  end

  # This page reports on over-allocated cards, so it is the one most exposed to a
  # per-card query: it used to look its reallocation targets up one card at a
  # time, on top of the service's own grouped queries.
  test "index issues a constant number of queries regardless of the number of over-allocated cards" do
    over_allocate(cards(:honedge), owned: 1, committed: 2)

    get over_allocations_path # warm the session: the first request of a test also loads the Devise user

    small = count_queries { get over_allocations_path }

    FLAT_COST_EXTRA_CARDS.each { |fixture_name| over_allocate(cards(fixture_name), owned: 0, committed: 1) }

    large = count_queries { get over_allocations_path }

    assert_response :success
    assert_operator @user.decks.where(physical: true).count, :>, 1, "sanity: several decks must be involved"
    assert_equal small, large, "query count grew with the number of over-allocated cards: #{small} -> #{large}"
  end

  private

  # Commits more real copies of the card across a fresh physical deck than the
  # user owns — the state a collection decrease leaves behind.
  def over_allocate(card, owned:, committed:)
    @user.collections.find_or_create_by!(card: card) { |c| c.quantity = 0 }.update!(quantity: owned)
    @user.decks.create!(name: "Deck #{card.id}", physical: true, standard_pool: standard_pools(:twm_por)).tap do |deck|
      deck.deck_cards.create!(card: card, quantity: committed, owned_copies: committed)
    end
  end
end
