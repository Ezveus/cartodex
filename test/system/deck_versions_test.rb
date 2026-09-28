require "application_system_test_case"

# The three surfaces of deck versions a request test cannot reach: the result modal's
# version prompt is a 409 answered in JS, the earlier-version import is a form round trip
# followed by a second form, and the diff page is the compare table rendered with other links.
# Every record is built through the models, so no fixture another test edits can shift a number.
class DeckVersionsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
    @deck = @user.decks.create!(name: "Honedge Box", physical: true, standard_pool: standard_pools(:twm_por))
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
  end

  # v1 is the list as it stood; the Doublade added afterwards is the drift the modal has to ask
  # about, since nothing tells the server which of the two lists this match was played with.
  def drifted_deck_on_v1
    @v1 = Decks::VersionSnapshot.call(@deck, effective_at: 2.days.ago)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)
  end

  def log_a_win
    visit deck_path(@deck)
    click_button "Log Result"
    find(".result-type-btn.result-win").click
    click_button "Save"
  end

  def assert_prompt_offers(next_number:, current_number:)
    within "dialog.result-modal" do
      assert_button "Create version #{next_number}"
      assert_button "Attach to version #{current_number}"
      assert_selector ".result-version-prompt button", text: "Cancel"
    end
  end

  test "a drifted deck asks which list the match was played with, and Cancel writes nothing" do
    drifted_deck_on_v1
    log_a_win

    assert_prompt_offers(next_number: 2, current_number: 1)

    within(".result-version-prompt") { click_button "Cancel" }

    assert_no_selector ".result-version-prompt", visible: true
    # Still open, with Save usable again: cancelling the question is not cancelling the result
    # the reader has just filled in.
    assert_selector "dialog.result-modal[open]"
    assert_button "Save", disabled: false
    assert_equal 0, @deck.deck_results.count
    assert_equal 1, @deck.deck_versions.count
  end

  test "Create version 2 snapshots the live list and files the result under it" do
    drifted_deck_on_v1
    log_a_win

    assert_prompt_offers(next_number: 2, current_number: 1)
    click_button "Create version 2"

    assert_no_selector "dialog.result-modal[open]"
    assert_equal 2, @deck.deck_versions.count
    result = @deck.deck_results.sole
    assert_equal @deck.reload.latest_version, result.deck_version
    assert_not_equal @v1, result.deck_version
  end

  test "Attach to version 1 files the result under the version that already exists" do
    drifted_deck_on_v1
    log_a_win

    assert_prompt_offers(next_number: 2, current_number: 1)
    click_button "Attach to version 1"

    assert_no_selector "dialog.result-modal[open]"
    assert_equal 1, @deck.deck_versions.count
    assert_equal @v1, @deck.deck_results.sole.deck_version
  end

  # The one case the modal must not ask: with no version at all there is no "version N" to
  # offer, so the first result creates v1 silently.
  test "a deck with no version logs its first result without asking" do
    log_a_win

    assert_no_selector "dialog.result-modal[open]"
    assert_equal 1, @deck.deck_versions.count
    assert_equal 1, @deck.deck_results.count
  end

  test "an earlier version imported from a pasted list can take a result, and the stats show both" do
    current = Decks::VersionSnapshot.call(@deck, effective_at: 2.days.ago)
    result = @deck.deck_results.create!(result: "win", match_format: "bo1", played_at: 5.days.ago,
                                        deck_version: current)

    visit deck_versions_path(@deck)
    click_link "Add an earlier version"

    fill_in "Decklist", with: "3 Honedge POR 56\n1 Doublade POR 57"
    fill_in "Effective from", with: 10.days.ago.change(hour: 12, min: 0)
    select "Standard", from: "Format"
    select standard_pools(:twm_por).name, from: "Standard pool"
    click_button "Create version"

    # A refusal re-renders the same form, so its field going away is what says the write happened.
    assert_no_field "Decklist"
    assert_equal 2, @deck.deck_versions.count

    # Dated before the snapshot, the import is now v1 and the snapshot has become v2.
    earlier = @deck.reload.ordered_versions.first
    assert_not_equal current, earlier

    visit edit_deck_deck_result_path(@deck, result)
    select "v1", from: "Version"
    click_button "Update Result"

    assert_no_button "Update Result"
    assert_equal earlier, result.reload.deck_version

    visit stats_deck_path(@deck)

    within ".version-summary" do
      rows = all(".data-table-row", count: 2)
      assert_match(/\Av1\b.*100%/m, rows.first.text)
      # A version nothing was played with has no rate at all, rather than a rate of zero.
      assert_match(/\Av2\b.*—/m, rows.last.text)
      assert_no_match(/%/, rows.last.text)
    end
  end

  test "the diff page links its columns to versions, never to the deck, and marks the changed row" do
    first = Decks::VersionSnapshot.call(@deck, effective_at: 3.days.ago)
    @deck.deck_cards.find_by!(card: cards(:honedge)).update!(quantity: 3)
    second = Decks::VersionSnapshot.call(@deck, effective_at: 1.day.ago)

    visit deck_version_path(@deck, second)

    hrefs = all(".deck-compare-table thead a").map { |a| URI(a[:href]).path }
    assert_equal [ deck_version_path(@deck, first), deck_version_path(@deck, second) ], hrefs
    assert_not_includes all(".deck-compare-header a").map { |a| URI(a[:href]).path }, deck_path(@deck)

    assert_selector ".deck-compare-card-row.is-diff", text: "Honedge"
  end
end
