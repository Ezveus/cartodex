require "application_system_test_case"

# The sheet's filters run inside a Turbo Frame declared target="_top". Two things only a browser
# can see: that typing swaps the rows without visiting the page (which would replace the field
# and drop its focus), and that the rows' own links still leave the frame.
class TournamentSheetFiltersTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tournament = tournaments(:one)
    login_as @user, scope: :user
  end

  test "typing a player name narrows the sheet without leaving the field" do
    visit tournament_path(@tournament)
    assert_text "Giovanni"

    field = find("input[name=player]")
    field.fill_in with: "ketch"

    assert_no_text "Giovanni"
    assert_text "Ash Ketchum"
    assert_current_path(/player=ketch/)
    # Still the element the reader typed into, still holding what they typed: a full-page visit
    # would have replaced it with a fresh one.
    assert_equal "ketch", field.value
    assert page.evaluate_script("document.activeElement.name == 'player'"),
      "the field lost focus, which a full-page visit does"
  end

  test "choosing an archetype narrows the sheet, and Clear restores it" do
    card = Card.create!(name: "Filter Variant", set_name: "SFV", set_number: "1", card_type: "Pokémon",
                        hp: 60, rarity: "Common", type_symbol: "Colorless", retreat_cost: 1)
    variant = Archetype.create!(primary_card: card, name: "Filter Variant", custom_name: "1",
                                parent: archetypes(:standings_marker))
    @tournament.standings.create!(player_name: "Variant Player", division: "masters", archetype: variant)

    visit tournament_path(@tournament)
    find("select[name=archetype]").select "Filter Variant"

    assert_no_text "Giovanni"
    assert_text "Variant Player"

    click_on "Clear"

    assert_text "Giovanni"
    assert_text "Variant Player"
  end

  # The frame is target="_top": a row's link must navigate the page, not the frame — which would
  # answer "Content missing" in place of the table.
  test "a row's Edit link opens the edit page from a filtered sheet" do
    visit tournament_path(@tournament)
    find("input[name=player]").fill_in with: "giovanni"
    assert_no_text "Ash Ketchum"

    within(".data-table-row", text: "Giovanni") { click_on "Edit" }

    assert_field "Player name", with: "Giovanni"
    assert_no_text "Content missing"
  end

  test "a row's Decklist link opens the deck from a filtered sheet" do
    tournament_standings(:giovanni_masters).update!(deck: decks(:field_list))

    visit tournament_path(@tournament)
    find("input[name=player]").fill_in with: "giovanni"
    assert_no_text "Ash Ketchum"

    within(".data-table-row", text: "Giovanni") { click_on "Decklist" }

    assert_selector "h1", text: decks(:field_list).name
  end

  test "the pager walks a filtered sheet and keeps the filter" do
    TournamentStanding::SHEET_PER_PAGE.times do |i|
      @tournament.standings.create!(player_name: "Filler #{i}", division: "masters",
        placement: i + 1, archetype: archetypes(:standings_marker))
    end
    @tournament.standings.create!(player_name: "Filler Last", division: "masters",
      placement: 900, archetype: archetypes(:standings_marker))

    visit tournament_path(@tournament, player: "filler")

    assert_text "Page 1 / 2"
    # Tagged so a full-page visit, which replaces the body, is told apart from a frame swap.
    page.execute_script("document.querySelector('form.deck-filters').dataset.probe = '1'")
    click_on "Next →"

    assert_text "Page 2 / 2"
    assert_text "Filler Last"
    assert_no_text "Giovanni"
    assert_current_path(/page=2/)
    assert_current_path(/player=filler/)
    assert_equal "filler", find("input[name=player]").value
    assert_selector "form.deck-filters[data-probe='1']"
  end
end
