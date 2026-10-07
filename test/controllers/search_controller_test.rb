require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Ogerpon Toolbox")
    sign_in @user
  end

  # The spotlight's form targets the results frame, so every request it makes carries this header.
  # Without it /search answers as a page — see the tests at the bottom.
  def get_spotlight(q:)
    get search_path(q: q), headers: { "Turbo-Frame" => Search::ResultsView::FRAME_ID }
  end

  # /search is public — its reachability without a session is covered by
  # test/controllers/public_access_test.rb, along with every other action that left the
  # `authenticate :user` block.

  test "renders the frame with a group per matching type" do
    get_spotlight(q: "ogerpon")

    assert_response :success
    assert_select "turbo-frame#search_results"
    assert_select "[role=group][aria-labelledby=spotlight-group-decks] a[role=option]",
      text: /Ogerpon Toolbox/
    assert_select "[role=group][aria-labelledby=spotlight-group-cards] a[role=option]",
      text: /Teal Mask Ogerpon ex/
  end

  test "renders an empty frame for a query below the minimum length" do
    get_spotlight(q: "o")

    assert_response :success
    assert_select "turbo-frame#search_results"
    assert_select "a[role=option]", count: 0
    assert_select ".spotlight-empty", count: 0, msg: "a too-short query says nothing at all"
    assert_select "turbo-frame#search_results *", count: 0,
      msg: "the page's 'at least 2 characters' hint must not reach the spotlight's first keystroke"
  end

  test "says so when the query matches nothing" do
    get_spotlight(q: "zzzznothing")

    assert_response :success
    assert_select ".spotlight-empty"
    assert_select "a[role=option]", count: 0
  end

  test "result links leave the frame" do
    get_spotlight(q: "ogerpon")

    assert_select "a[role=option][data-turbo-frame=_top]"
  end

  # aria-activedescendant only says where the highlight is; without aria-selected a screen reader
  # reads the row it points at without ever calling it selected. The Stimulus controller moves the
  # "true" around, so the server's job is to ship every row with the attribute present and false.
  test "every option ships with aria-selected for the keyboard walk to move" do
    get_spotlight(q: "ogerpon")

    assert_select "a[role=option][aria-selected=false]"
    assert_select "a[role=option]:not([aria-selected])", count: 0
  end

  # A listbox may only contain options and groups. The see-all row was a bare link inside one,
  # which made the panel's ARIA invalid and left it out of the arrow-key walk.
  test "the see-all row is an option of its group, addressable by id" do
    get_spotlight(q: "ogerpon")

    assert_select "a.spotlight-see-all[role=option][id=?]", "spotlight-group-decks-see-all"
    assert_select ".spotlight-listbox a:not([role=option])", count: 0
  end

  test "each group links to its index pre-filtered with the query" do
    get_spotlight(q: "ogerpon")

    assert_select "a.spotlight-see-all[href=?]", decks_path(q: "ogerpon")
    assert_select "a.spotlight-see-all[href=?]", cards_path(q: "ogerpon")
  end

  test "the see-all label is grammatically singular for exactly one match" do
    get_spotlight(q: "ogerpon")

    assert_select "a.spotlight-see-all[href=?]", decks_path(q: "ogerpon"), text: "See all 1 deck"
  end

  test "the group header reports the total when the cap truncated it" do
    7.times { |i| @user.decks.create!(name: "Ogerpon Build #{i}", standard_pool: standard_pools(:twm_por)) }

    get_spotlight(q: "ogerpon")

    assert_select "#spotlight-group-decks", text: /5 of 8/
  end

  test "does not render an empty group" do
    get_spotlight(q: "ogerpon")

    assert_select "#spotlight-group-tournaments", count: 0
  end

  # layout false: the response is the frame and nothing else. Don't assert on <html> — Nokogiri
  # adds html/body wrappers when parsing a fragment, so that assertion would fail even when the
  # layout is correctly skipped.
  test "renders without the application layout" do
    get_spotlight(q: "ogerpon")

    assert_select "nav.navbar", count: 0
    assert_select "form.spotlight-form", count: 0, msg: "the frame must not carry the input the user is typing in"
  end

  # What a browser's search engine opens: no Turbo-Frame header.
  test "opened as a page, renders the layout around the spotlight's list" do
    get search_path(q: "ogerpon")

    assert_response :success
    assert_select "nav.navbar"
    assert_select "title", text: /ogerpon/
    assert_select ".search-page-results .spotlight-listbox a[role=option]", text: /Ogerpon Toolbox/
    assert_select "turbo-frame#search_results", count: 1,
      msg: "only the overlay's frame: the page must not carry a second element with that id"
  end

  # The request: the engine runs EXACTLY the spotlight's search. Same rows, same order, same
  # see-all links, compared rather than restated, so a change to either surface alone goes red.
  test "the page lists exactly what the spotlight lists" do
    7.times { |i| @user.decks.create!(name: "Ogerpon Build #{i}", standard_pool: standard_pools(:twm_por)) }

    get_spotlight(q: "ogerpon")
    spotlight = css_select("a[role=option]").map { |a| [ a["href"], a.text.squish ] }

    get search_path(q: "ogerpon")
    page = css_select(".search-page-results a[role=option]").map { |a| [ a["href"], a.text.squish ] }

    assert_operator spotlight.size, :>, 5
    assert_equal spotlight, page
  end

  test "opened as a page with a too-short query, says how long it must be" do
    get search_path(q: "o")

    assert_response :success
    assert_select ".search-page-hint", text: /at least 2 characters/
    assert_select ".search-page-results", count: 0
  end

  test "opened as a page with no query at all, says the same rather than failing" do
    get search_path

    assert_response :success
    assert_select ".search-page-hint", text: /at least 2 characters/
  end

  test "opened as a page by a visitor, runs the visitor's search" do
    sign_out @user

    get search_path(q: "ogerpon")

    assert_response :success
    assert_select ".search-page-results a[role=option]", text: /Teal Mask Ogerpon ex/
    assert_select ".search-page-results a[role=option]", text: /Ogerpon Toolbox/, count: 0
  end
end
