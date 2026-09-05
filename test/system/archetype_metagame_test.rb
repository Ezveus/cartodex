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

    # Both events here are Standard, so nothing on this page is counted under "All formats" and
    # under no pool. The note that explains that distinction must not appear where there is no
    # instance of it — on the production data it appeared on every archetype.
    assert_no_text "Events outside Standard carry no pool"

    # Crossing SMALL_SAMPLE is the point: the notice has to go away on its own, not merely be
    # absent from a page that never showed it.
    select "TWM-ASC — 12 lists", from: "Sample"
    assert_text "Across 12 lists"
    assert_no_text "Small sample: every percentage below is computed over"

    # The chosen sample has to survive a reload, or a copied link points at something else.
    assert_current_path(/pool=#{standard_pools(:twm_asc).id}/)
  end

  # One list is not a sample of itself: every card in it is played by "every list" and always in
  # "the same number" for want of a second list to differ from, so the settled-core sentence would
  # republish the whole decklist under the word "fixed" — measured on the production data,
  # archetype 47 read "Across 1 list, 25 cards accounting for 60 copies are played by every list".
  #
  # Here rather than only in a component test because the two halves of the correction are decided
  # in two different places: Archetypes::CardReport writes the sentence, and the flag is suppressed
  # three components down. Only a rendered page proves they agree — and only a rendered page proves
  # the selector is gone, since "one pool plus All formats" is a scope the controller builds and no
  # component can be asked for.
  test "an archetype with one recorded list says so instead of calling it a settled core" do
    archetype = single_list_archetype

    visit archetype_path(archetype)
    assert_selector "h1", text: archetype.name

    assert_text "Only one list is recorded for this sample, so there is nothing to compare it " \
                "against — what follows is that list."
    assert_no_text "are played by every list"
    assert_no_selector ".archetype-fixed-flag"

    # Two labels over one sample is a filter that cannot filter, so there is no filter.
    assert_no_selector "select[name='pool']"
    # …and the small-sample notice stops at a full stop rather than pointing at a fuller sample
    # that does not exist.
    assert_text "supports no conclusion about the archetype."
    assert_no_text "one click away"

    # The counters agree with themselves at one, which is the size this whole page is about.
    # Anchored at the end, or "1 standings" would satisfy "1 standing".
    assert_selector ".stat", text: /1\s+standing\z/
    assert_selector ".stat", text: /1\s+event\z/
    assert_selector ".stat", text: /1\s+list\z/
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

  # One event, one standing, one list — everything the two rules above turn on, and nothing else.
  # A card fixture no other test in this file touches, since two archetypes sharing a primary card
  # would collide on the fingerprint pair.
  def single_list_archetype
    archetype = Archetype.create!(primary_card: cards(:doublade))
    event = tournament("Lone Record", Date.new(2026, 2, 14), standard_pools(:twm_por))
    standing(event, archetype, "Only Player")

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
