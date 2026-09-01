require "test_helper"

class SearchControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user, name: "Ogerpon Toolbox")
    sign_in @user
  end

  test "requires authentication" do
    sign_out @user

    get search_path(q: "ogerpon")

    assert_redirected_to new_user_session_path
  end

  test "renders the frame with a group per matching type" do
    get search_path(q: "ogerpon")

    assert_response :success
    assert_select "turbo-frame#search_results"
    assert_select "[role=group][aria-labelledby=spotlight-group-decks] a[role=option]",
      text: /Ogerpon Toolbox/
    assert_select "[role=group][aria-labelledby=spotlight-group-cards] a[role=option]",
      text: /Teal Mask Ogerpon ex/
  end

  test "renders an empty frame for a query below the minimum length" do
    get search_path(q: "o")

    assert_response :success
    assert_select "turbo-frame#search_results"
    assert_select "a[role=option]", count: 0
    assert_select ".spotlight-empty", count: 0, msg: "a too-short query says nothing at all"
  end

  test "says so when the query matches nothing" do
    get search_path(q: "zzzznothing")

    assert_response :success
    assert_select ".spotlight-empty"
    assert_select "a[role=option]", count: 0
  end

  test "result links leave the frame" do
    get search_path(q: "ogerpon")

    assert_select "a[role=option][data-turbo-frame=_top]"
  end

  # aria-activedescendant only says where the highlight is; without aria-selected a screen reader
  # reads the row it points at without ever calling it selected. The Stimulus controller moves the
  # "true" around, so the server's job is to ship every row with the attribute present and false.
  test "every option ships with aria-selected for the keyboard walk to move" do
    get search_path(q: "ogerpon")

    assert_select "a[role=option][aria-selected=false]"
    assert_select "a[role=option]:not([aria-selected])", count: 0
  end

  # A listbox may only contain options and groups. The see-all row was a bare link inside one,
  # which made the panel's ARIA invalid and left it out of the arrow-key walk.
  test "the see-all row is an option of its group, addressable by id" do
    get search_path(q: "ogerpon")

    assert_select "a.spotlight-see-all[role=option][id=?]", "spotlight-group-decks-see-all"
    assert_select ".spotlight-listbox a:not([role=option])", count: 0
  end

  test "each group links to its index pre-filtered with the query" do
    get search_path(q: "ogerpon")

    assert_select "a.spotlight-see-all[href=?]", decks_path(q: "ogerpon")
    assert_select "a.spotlight-see-all[href=?]", cards_path(q: "ogerpon")
  end

  test "the see-all label is grammatically singular for exactly one match" do
    get search_path(q: "ogerpon")

    assert_select "a.spotlight-see-all[href=?]", decks_path(q: "ogerpon"), text: "See all 1 deck"
  end

  test "the group header reports the total when the cap truncated it" do
    7.times { |i| @user.decks.create!(name: "Ogerpon Build #{i}", standard_pool: standard_pools(:twm_por)) }

    get search_path(q: "ogerpon")

    assert_select "#spotlight-group-decks", text: /5 of 8/
  end

  test "does not render an empty group" do
    get search_path(q: "ogerpon")

    assert_select "#spotlight-group-tournaments", count: 0
  end

  # layout false: the response is the frame and nothing else. Don't assert on <html> — Nokogiri
  # adds html/body wrappers when parsing a fragment, so that assertion would fail even when the
  # layout is correctly skipped.
  test "renders without the application layout" do
    get search_path(q: "ogerpon")

    assert_select "nav.navbar", count: 0
    assert_select "form.spotlight-form", count: 0, msg: "the frame must not carry the input the user is typing in"
  end
end
