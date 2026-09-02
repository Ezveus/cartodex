require "application_system_test_case"

class DeckSharingTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, shared: false)
    login_as @user, scope: :user
  end

  test "the owner shares a deck, gets a link to copy, and can take it back" do
    visit deck_path(@deck)

    find(".deck-actions-bar .dropdown button", text: "Actions").click
    click_on "Share…"
    check "shared"

    # A path suffix, not deck_url: no system test in this suite builds a full URL, nothing sets
    # default_url_options for them, and the page's host is Capybara's server, not the test's.
    assert_field "share-url", with: %r{/decks/#{@deck.key}\z}
    assert_predicate @deck.reload, :shared?

    # The un-share half is the one a bare check_box_tag breaks (no param posted at all), and
    # the one the controller tests cannot reproduce from a browser's point of view.
    uncheck "shared"

    assert_no_field "share-url"
    refute_predicate @deck.reload, :shared?
  end
end
