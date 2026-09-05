require "application_system_test_case"

# The two pages end to end, on both sides of the 768px breakpoint.
#
# What no controller test can reach: the catalog's filter is debounced JavaScript submitting into
# a Turbo Frame, and the sample selector is a `<select>` whose change event submits its form. Both
# are the page's only moving parts, and both are invisible to an integration test that just GETs a
# URL with the parameter already set.
class ArchetypeMetagameTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
  end

  test "a member filters the catalog, opens an archetype and switches rotation" do
    archetype = recorded_archetype

    visit dashboard_path
    click_nav_link "Archetypes"
    assert_selector "h1", text: "Archetypes"

    # The filter is debounced, so both assertions have to wait rather than read the first paint.
    fill_in "Search archetypes", with: "Kricketune"
    assert_text "No archetypes match this search."

    fill_in "Search archetypes", with: "Honedge"
    assert_link archetype.name

    click_on archetype.name
    assert_selector "h1", text: archetype.name

    # Defaults to the most recent pool, which here is deliberately the *smaller* sample — that is
    # the design decision, and it is also why the notice has to be here.
    assert_text "Small sample: every percentage below is computed over"
    assert_text "Recorded in Cartodex"

    # Crossing SMALL_SAMPLE is the point: the notice has to go away on its own, not merely be
    # absent from a page that never showed it.
    select "TWM-ASC — 12 lists", from: "Sample"
    assert_text "Across 12 lists"
    assert_no_text "Small sample: every percentage below is computed over"

    # The chosen sample has to survive a reload, or a copied link points at something else.
    assert_current_path(/pool=#{standard_pools(:twm_asc).id}/)
  end

  private

  # Two rotations, on purpose: the newest pool holds one list and the oldest twelve, which is the
  # shape the production data has (3 lists in the newest pool, 68 in the oldest) and the only one
  # that can tell "most recent" apart from "best populated". Twelve rather than three so the
  # larger sample sits above MetagameScope::SMALL_SAMPLE and the notice genuinely clears.
  def recorded_archetype
    archetype = Archetype.create!(primary_card: cards(:honedge))

    old_event = tournament("Rotation Past", Date.new(2025, 12, 6), standard_pools(:twm_asc))
    new_event = tournament("Rotation Present", Date.new(2026, 2, 7), standard_pools(:twm_por))

    12.times { |i| standing(old_event, archetype, "Past Player #{i}") }
    standing(new_event, archetype, "Present Player")

    archetype
  end

  def tournament(name, date, pool)
    Tournament.create!(name: name, date: date, tier: "regional", format: "standard",
                       standard_pool: pool)
  end

  # An ownerless field list: shared and never physical, which is what
  # Deck#ownerless_deck_is_shared_and_virtual requires.
  def standing(event, archetype, player_name)
    deck = Deck.create!(name: "#{player_name} — #{event.name}", shared: true, physical: false,
                        format: "standard", standard_pool: event.standard_pool)
    DeckCard.create!(deck: deck, card: cards(:teal_mask_ogerpon_ex), quantity: 2)
    DeckCard.create!(deck: deck, card: cards(:bosss_orders_meg), quantity: 1)

    TournamentStanding.create!(tournament: event, archetype: archetype, deck: deck,
                               player_name: player_name, division: "masters",
                               placement: 1 + TournamentStanding.where(tournament: event).count)
  end
end
