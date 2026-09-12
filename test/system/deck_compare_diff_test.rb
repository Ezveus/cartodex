require "application_system_test_case"

# The "Differences only" checkbox on the compare page. Nothing about it is visible to a request
# test once the page has been served: the hiding is a CSS rule keyed on a class the Stimulus
# controller moves, and the address it writes is a history.replaceState the server never sees.
class DeckCompareDiffTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @left = @user.decks.create!(name: "Left", standard_pool: standard_pools(:twm_por))
    @right = @user.decks.create!(name: "Right", standard_pool: standard_pools(:twm_por))

    # Pokémon: the decks agree on Honedge and disagree on Doublade, so the group survives the
    # filter while one of its rows does not — row-level hiding, inside a group that stays.
    @left.deck_cards.create!(card: cards(:honedge), quantity: 2)
    @right.deck_cards.create!(card: cards(:honedge), quantity: 2)
    @left.deck_cards.create!(card: cards(:doublade), quantity: 1)

    # Energy: identical on both sides, so the whole group goes — header and subtotal included.
    @left.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 3)
    @right.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 3)

    login_as @user, scope: :user
  end

  # The group headers are `text-transform: uppercase`, and Capybara matches the *rendered* text —
  # so a plain `text: "Energy"` never matches, which would leave the absence assertions passing on
  # a page where nothing was hidden at all.
  def assert_group_header(type)
    assert_selector ".deck-compare-group-header", text: /\A#{type}\z/i
  end

  def assert_no_group_header(type)
    assert_no_selector ".deck-compare-group-header", text: /\A#{type}\z/i
  end

  test "ticking the box drops the agreed rows and whole agreed groups, and unticking restores them" do
    visit compare_decks_path(ids: [ @left.key, @right.key ])

    assert_selector ".deck-compare-card-row", text: "Honedge"
    assert_group_header "Energy"

    check "Differences only"

    # The row the decks agree on goes; the one they disagree on stays, which is what tells this
    # apart from a rule that hid the table.
    assert_no_selector ".deck-compare-card-row", text: "Honedge"
    assert_selector ".deck-compare-card-row", text: "Doublade"

    # The Energy group agrees throughout, so its header and its subtotal go with its rows.
    assert_no_group_header "Energy"
    assert_group_header "Pokémon"

    # The totals keep describing the whole decks — 6 cards on the left, 5 on the right — and say
    # beside each how many copies sit on a row the decks disagree about.
    assert_selector ".deck-compare-total td", text: "6 (1)"
    assert_selector ".deck-compare-total td", text: "5 (0)"

    # The state is in the address, so the reader can share or reload what they are looking at.
    assert_match(/diff=1/, page.current_url)

    uncheck "Differences only"

    assert_selector ".deck-compare-card-row", text: "Honedge"
    assert_group_header "Energy"
    assert_no_match(/diff=1/, page.current_url)
  end

  test "a link carrying diff=1 arrives already filtered" do
    visit compare_decks_path(ids: [ @left.key, @right.key ], diff: "1")

    assert_checked_field "Differences only"
    assert_no_selector ".deck-compare-card-row", text: "Honedge"
    assert_selector ".deck-compare-card-row", text: "Doublade"
  end

  test "decks that agree on everything say so rather than showing an empty table" do
    @left.deck_cards.find_by!(card: cards(:doublade)).destroy!

    visit compare_decks_path(ids: [ @left.key, @right.key ])

    assert_no_selector ".deck-compare-no-diff"

    check "Differences only"

    assert_selector ".deck-compare-no-diff", text: "same cards"
  end
end
