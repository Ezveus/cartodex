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

  # A browser test because nothing else can tell the two outcomes apart. Decks::HeaderFrame renders
  # the badge row inside `turbo_frame_tag("deck-header")`, so an anchor without a breakout is
  # frame-scoped: Turbo fetches /archetypes/N, finds no frame of that id in the response, and
  # replaces the deck header with its missing-frame error. The markup is identical either way, and
  # a request test sees a 200 for a page nobody ever reaches.
  test "the archetype badge on a deck page leaves its frame and opens the archetype" do
    archetype = Archetype.create!(primary_card: cards(:honedge))
    deck = decks(:one)
    deck.update!(user: @user, archetype: archetype)

    visit deck_path(deck)
    assert_selector "h1", text: deck.name

    click_on archetype.name

    assert_current_path archetype_path(archetype)
    assert_selector "h1", text: archetype.name
    assert_no_text "Content missing"
  end

  # The catalog's note about online play, checked as *geometry* rather than as text, and that is
  # the point: below 768px `.data-table-row .data-table-cell` is `display: flex; align-items:
  # center`, so a `<p>` added beside the badge's link becomes a sibling flex item and lands on the
  # same line — right-aligned to the card's edge, squeezing the badge into three wrapped lines and
  # growing the row from 29px to 64px. A margin cannot move it; only a column wrapper can.
  #
  # No system test visited /archetypes before this one, which is exactly why the mobile sweep — a
  # CI job of its own — saw nothing. Asserting the text alone would still see nothing: the note
  # renders either way, it renders in the *wrong place*.
  test "the catalog's online note sits under the badge rather than beside it, on both sides of the breakpoint" do
    archetype = archetype_with_online_results

    visit archetypes_path
    assert_text "Includes 1 standing from online play"

    row = find(".data-table-row", text: archetype.name)
    link = row.find("a", match: :first)
    note = row.find(".archetype-row-note")

    link_bottom = evaluate_script("arguments[0].getBoundingClientRect().bottom", link)
    note_top = evaluate_script("arguments[0].getBoundingClientRect().top", note)

    assert_operator note_top, :>=, link_bottom - 1,
      "the note overlaps the badge's line instead of sitting under it " \
      "(link bottom #{link_bottom}, note top #{note_top})"
  end

  # `.archetype-card-label` carries `flex-basis: 100%`, so it always lands on a line of its own
  # below the name text — deterministically, not "when the browser happens to run out of room",
  # which is why this holds at both sides of the sweep rather than needing a pinned width. Checked
  # against the name *text* specifically (a span added for exactly this), not the name cell as a
  # whole: the cell's own box already contains the badge once it wraps beneath it, so comparing
  # the badge to the cell can never fail for a badge sharing the name's line — only the text's own
  # box tells the two layouts apart.
  test "the label badge sits on its own line, below the card name" do
    archetype = labelled_archetype

    visit archetype_path(archetype)
    assert_selector "h1", text: archetype.name

    row = find(".archetype-card-row", text: "ACE SPEC")
    name_text = row.find(".archetype-card-name-text")
    badge = row.find(".archetype-card-label")

    name_bottom = evaluate_script("arguments[0].getBoundingClientRect().bottom", name_text)
    badge_top = evaluate_script("arguments[0].getBoundingClientRect().top", badge)

    assert_operator badge_top, :>=, name_bottom - 1,
      "the badge sits beside the name instead of below it " \
      "(name bottom #{name_bottom}, badge top #{badge_top})"
  end

  private

  # One paper standing and one online one, so the note has a mixture to describe.
  def archetype_with_online_results
    archetype = Archetype.create!(primary_card: cards(:doublade))
    paper = tournament("Paper Cup", Date.new(2026, 2, 7), standard_pools(:twm_por))
    weekly = tournament("Pumpkaweekly", Date.new(2026, 2, 14), standard_pools(:twm_por), online: true)
    standing(paper, archetype, "Paper Player")
    standing(weekly, archetype, "Online Player", division: "open")

    archetype
  end

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

  # A fresh primary card, not one of this file's shared fixtures — Archetype's
  # (primary_fingerprint, secondary_fingerprint) pair is UNIQUE, and the fixture set already holds
  # an archetype anchored to teal_mask_ogerpon_ex.
  def labelled_archetype
    card = Card.create!(
      name: "Labelled Primary", set_name: "LBL", set_number: "1",
      card_type: "Pokémon", hp: 60, rarity: "Common", type_symbol: "Colorless", retreat_cost: 1
    )
    archetype = Archetype.create!(primary_card: card)
    event = tournament("Label Cup", Date.new(2026, 2, 14), standard_pools(:twm_por))
    place = standing(event, archetype, "Label Player")

    labelled_card = place.deck.deck_cards.first.card
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    label.assignments.create!(fingerprint: labelled_card.fingerprint, card: labelled_card, source: "imported")

    archetype
  end

  def tournament(name, date, pool, online: false)
    Tournament.create!(name: name, date: date, tier: online ? "other" : "regional",
                       format: "standard", standard_pool: pool, online: online)
  end

  # An ownerless field list: shared and never physical, which is what
  # Deck#ownerless_deck_is_shared_and_virtual requires.
  def standing(event, archetype, player_name, division: "masters")
    deck = Deck.create!(name: "#{player_name} — #{event.name}", shared: true, physical: false,
                        format: "standard", standard_pool: event.standard_pool)
    DeckCard.create!(deck: deck, card: cards(:teal_mask_ogerpon_ex), quantity: 2)
    DeckCard.create!(deck: deck, card: cards(:bosss_orders_meg), quantity: 1)

    TournamentStanding.create!(tournament: event, archetype: archetype, deck: deck,
                               player_name: player_name, division: division,
                               placement: 1 + TournamentStanding.where(tournament: event).count)
  end
end
