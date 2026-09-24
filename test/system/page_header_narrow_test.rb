require "application_system_test_case"

# A page header's action row at a phone's width. Below the breakpoint `.admin-header` stacks and
# the action row sizes to its content; unwrapped, that content is every button side by side, so the
# row ran off the screen while each button shrank to its longest word and grew three or four lines
# tall — six of them on an event page where the reader holds two participations. The sweep's mobile
# half renders at 500 (Chrome's floor), where a two-button row still fits, so the width is pinned.
class PageHeaderNarrowTest < ApplicationSystemTestCase
  drive_at 344, 780

  # One line of a .btn-sm-sized label is ~30px. A full-size .btn is ~48px and a squeezed one is a
  # multiple of that, so the bound catches both the overflow's symptom and the oversized buttons.
  MAX_BUTTON_HEIGHT = 40

  setup do
    @user = users(:one)
    login_as @user, scope: :user
  end

  test "sanity: the browser really is at a phone's width" do
    visit tournaments_path

    assert_operator page.evaluate_script("window.innerWidth"), :<=, 400
  end

  test "a card the reader owns keeps its collection control and Back on screen" do
    visit card_path(collections(:one).card)
    assert_selector ".card-collection-counter"

    assert_header_fits
  end

  test "an event with two of the reader's participations keeps its six buttons on screen" do
    tournament = tournaments(:one)
    tournament.entries.create!(user: @user, deck: decks(:one), tournament_profile: tournament_profiles(:misty),
      participant_count: 64, placement: 12)

    visit tournament_path(tournament)
    assert_selector ".admin-header .btn", text: "Your entry (Misty)"

    assert_header_fits
  end

  test "a participation page keeps its buttons on screen" do
    entry = tournament_entries(:one)
    visit tournament_entry_path(entry.tournament, entry)
    assert_selector ".admin-header .btn", text: "Tournament page"

    assert_header_fits
  end

  test "an archetype's deck list keeps its header on screen" do
    visit archetype_path(archetypes(:standings_marker))
    assert_selector ".admin-header .btn", text: "Analysis"

    assert_header_fits
  end

  test "an archetype's analysis keeps its header on screen" do
    visit analysis_archetype_path(archetypes(:standings_marker))
    assert_selector ".admin-header .btn", text: "Decks"

    assert_header_fits
  end

  private

  def assert_header_fits
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, viewport_width,
      "the page scrolls sideways"

    buttons = all(".admin-header .btn, .card-show-header .btn")
    assert_not_empty buttons

    buttons.each do |button|
      rect = page.evaluate_script("JSON.parse(JSON.stringify(arguments[0].getBoundingClientRect()))", button)
      label = button.text

      assert_operator rect["right"], :<=, viewport_width, "#{label}: runs off the right edge"
      assert_operator rect["height"], :<=, MAX_BUTTON_HEIGHT, "#{label}: #{rect["height"]}px tall"
    end
  end

  def viewport_width
    page.evaluate_script("document.documentElement.clientWidth")
  end
end
