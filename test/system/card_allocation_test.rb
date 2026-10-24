require "application_system_test_case"

# The card page's "Your copies" frame follows the "In collection" counter, which writes through
# /api/collections without reloading the page. The frame reloads from the server on each change,
# so this drives the real counter and reads what the server answered.
class CardAllocationSystemTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @card = cards(:honedge) # users(:one) owns one copy, by fixture
    @deck = @user.decks.create!(name: "Blade Deck", physical: true, standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)
    login_as @user, scope: :user
  end

  def stat(label)
    find(".card-allocation-stat", text: label).find("dd")
  end

  test "the section follows the collection counter and its deck link leaves the card page" do
    visit card_path(@card)

    assert_equal "1", stat("Owned").text
    assert_equal "0", stat("Available").text
    assert_selector ".card-allocation-over", text: "1 more copy than you own"

    click_button "Increment"
    assert_selector ".card-allocation-stat", text: /\AOwned\s+2\z/
    assert_no_selector ".card-allocation-over"

    click_button "Increment"
    assert_selector ".card-allocation-stat", text: /\AAvailable\s+1\z/

    click_button "Decrement"
    assert_selector ".card-allocation-stat", text: /\AAvailable\s+0\z/

    click_link "Blade Deck"
    assert_current_path deck_path(@deck)
    assert_selector "h1", text: "Blade Deck"
  end

  # Owned is a sum over the printing's collection rows; Remove deletes the one the counter shows.
  # The frame must report what is left, which is why it reloads rather than computing from the
  # counter's own delta.
  test "removing one variant row leaves the others counted" do
    @user.collections.create!(card: @card, quantity: 1, language: "fr", finish: "reverse_holo")
    visit card_path(@card)
    assert_selector ".card-allocation-stat", text: /\AOwned\s+2\z/

    click_button "Remove"

    assert_selector ".card-allocation-stat", text: /\AOwned\s+1\z/
    assert_selector ".card-allocation-over", text: "1 more copy than you own"
  end
end
