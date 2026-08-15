require "application_system_test_case"
require_relative "../support/deck_card_rows"

# The card viewer itself, below the breakpoint, where it is a full-screen <dialog> rather than the
# hover pane the desktop side shows. `deck_card_mobile_test.rb` covers which *taps* reach it — the
# steppers must not, the card must — and stops at "a dialog exists". What the dialog then shows, and
# what closes it, was untested: the sweep running every test on both sides is the floor, not a
# substitute for assertions about behaviour only one side has.
#
# Two cards, because a modal showing the wrong one still shows one. The modal is a single element
# reused for every row (`preview_section` renders it once per page), so the realistic defect is a
# stale src rather than a missing one, and that is only visible with something to be stale about.
#
# The fixtures carry no image_url, which is why the row's data-card-preview-url is normally nil and
# the existing test could not assert on it; setup gives them one. The src is asserted as an
# attribute rather than as a rendered image: it names the card through /cards/:id/image, which is
# the identity this is about.
#
# That URL is still fetched for real by the browser, and CardsController#image proxies it through
# HttpFetcher — so it has to point somewhere that resolves. A remote host does not: HttpFetcher
# wraps a non-success *response* in FetchError but lets a connection error escape, the action 500s,
# and a system test re-raises server exceptions, so every test here died on DNS. Pointing it at the
# test server's own /icon.png keeps the proxy honest without leaving the machine.
class CardPreviewModalTest < ApplicationSystemTestCase
  include DeckCardRows

  drive_at 390, 844

  setup do
    @user = users(:one)
    @honedge = cards(:honedge)
    @doublade = cards(:doublade)
    [ @honedge, @doublade ].each { |card| card.update!(image_url: "#{page.server.base_url}/icon.png") }

    @deck = @user.decks.create!(name: "Pocket Deck", physical: false)
    @deck.deck_cards.create!(card: @honedge, quantity: 2)
    @deck.deck_cards.create!(card: @doublade, quantity: 1)

    login_as @user, scope: :user
  end

  test "opening the viewer shows the card that was tapped" do
    visit deck_path(@deck)

    open_viewer_on "Doublade"

    assert_selector "dialog.card-preview-modal"
    assert_equal image_card_path(@doublade), URI.parse(modal_image_src).path
    assert_equal card_path(@doublade), URI.parse(modal_link_href).path
  end

  # The dialog is one element reused by every row, so opening it a second time has to overwrite what
  # the first opening left in it. A viewer that only ever showed the first card tapped would satisfy
  # the test above.
  test "opening the viewer on another card replaces the previous one" do
    visit deck_path(@deck)

    open_viewer_on "Honedge"
    assert_equal image_card_path(@honedge), URI.parse(modal_image_src).path
    close_viewer

    open_viewer_on "Doublade"

    assert_equal image_card_path(@doublade), URI.parse(modal_image_src).path
    assert_equal card_path(@doublade), URI.parse(modal_link_href).path
  end

  test "the Close button closes the viewer" do
    visit deck_path(@deck)
    open_viewer_on "Honedge"

    within("dialog.card-preview-modal") { click_on "Close" }

    assert_no_selector "dialog.card-preview-modal"
  end

  # The <dialog> fills the screen and its content is a centred box, so everything around that box is
  # the backdrop — tapping there is how a phone dismisses this kind of sheet.
  test "tapping the backdrop closes the viewer" do
    visit deck_path(@deck)
    open_viewer_on "Honedge"

    tap_backdrop

    assert_no_selector "dialog.card-preview-modal"
  end

  # The other half of `backdropClose`'s `event.target === this.modalTarget` guard. The click listener
  # sits on the dialog, so every click inside the content bubbles to it too: without the guard the
  # viewer would shut the instant the user touched the card they opened it to look at — and the test
  # above would still pass.
  test "tapping the card inside the viewer does not close it" do
    visit deck_path(@deck)
    open_viewer_on "Honedge"

    find(".card-preview-modal-image").click

    assert_selector "dialog.card-preview-modal"
  end

  private

  def open_viewer_on(card_name)
    within(row_of(card_name)) { find(".deck-card-name").click }
    assert_selector "dialog.card-preview-modal"
  end

  def close_viewer
    within("dialog.card-preview-modal") { click_on "Close" }
    assert_no_selector "dialog.card-preview-modal"
  end

  # Capybara's offsets are measured from the element's centre, which is exactly where the content
  # box sits. A quarter of the viewport up and to the left of that lands on the dialog itself.
  def tap_backdrop
    find("dialog.card-preview-modal").click(x: -150, y: -350)
  end

  def modal_image_src
    find(".card-preview-modal-image", visible: :all)[:src]
  end

  def modal_link_href
    find("dialog.card-preview-modal").find_link("View card details")[:href]
  end
end
