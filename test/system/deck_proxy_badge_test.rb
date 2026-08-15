require "application_system_test_case"
require_relative "../support/deck_card_rows"

# Locks down the one thing about the derived "Proxies" badge that no request test can see: that it
# keeps up with the steppers on the same page.
#
# The badge is derived from `deck_cards.owned_copies`, and the deck page edits that number in place
# over the JSON API. The badge lives in the `deck-header` turbo frame — a different subtree from the
# steppers — so nothing reaches it by bubbling; it only moves because each write answers with the
# deck-wide state and `deck-proxies` relays it. A request test sees each response alone and would
# stay green with the relay ripped out.
class DeckProxyBadgeTest < ApplicationSystemTestCase
  include DeckCardRows

  setup do
    @user = users(:one)
    @user.collections.find_or_initialize_by(card: cards(:honedge)).update!(quantity: 3)
    @deck = @user.decks.create!(name: "Proxy Watch", physical: true)

    login_as @user, scope: :user
  end

  test "demoting a real copy raises the badge, and backing it again retires it" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)

    visit deck_path(@deck)
    assert_no_proxies_badge # a fully backed deck starts without it

    within_allocation_of("Honedge") { click_on "−" }

    assert_selector ".deck-card-alloc-label", text: "1 real · 1 proxy"
    assert_proxies_badge

    within_allocation_of("Honedge") { click_on "+" }

    assert_selector ".deck-card-alloc-label", text: "2 real · 0 proxy"
    assert_no_proxies_badge
  end

  # The card that carries the deck's only proxy is also the row that disappears, so the answer the
  # badge needs arrives on a response about a resource that no longer exists. That is why the
  # endpoint stopped replying with a body-less 204 here.
  test "removing the deck's last unbacked card retires the badge" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 1, owned_copies: 0)

    visit deck_path(@deck)
    assert_proxies_badge # the unbacked Doublade puts the deck in proxy territory

    within_quantity_of("Doublade") { click_on "-" }

    assert_no_selector "li.deck-card-item", text: "Doublade"
    assert_no_proxies_badge
  end

  # Raising a card's total past what backs it creates a proxy without touching owned_copies, so the
  # badge has to move on a quantity write too — not just on the allocation stepper.
  test "outgrowing the backed copies raises the badge" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 2, owned_copies: 2)

    visit deck_path(@deck)
    assert_no_proxies_badge

    within_quantity_of("Honedge") { click_on "+" }

    assert_selector ".deck-card-qty", text: "3"
    assert_proxies_badge
  end

  private

  # Capybara ignores hidden elements, which is exactly how the badge is retired — it stays in the
  # DOM so the Stimulus controller has something to toggle. "To review" is a badge-warning too, so
  # the text is what separates them.
  def assert_proxies_badge
    assert_selector "turbo-frame#deck-header .badge-warning", text: "Proxies"
  end

  def assert_no_proxies_badge
    assert_no_selector "turbo-frame#deck-header .badge-warning", text: "Proxies"
  end
end
