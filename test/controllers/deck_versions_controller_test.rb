require "test_helper"

# Owner only, behind the rule #stats uses. The lookup is current_user.decks, so a stranger's
# request never finds the deck — a 404, like DeckResultsController's, never a 403 that would out
# the deck's existence.
class DeckVersionsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @version = deck_versions(:one)
    sign_in @user
  end

  # --- reads (these render lane-2 views) ------------------------------------------------------

  test "index lists the versions" do
    get deck_versions_path(@deck)

    assert_response :success
  end

  test "show answers the diff with the previous version" do
    v2 = drift_and_snapshot

    get deck_version_path(@deck, v2)
    assert_response :success

    get deck_version_path(@deck, @version)
    assert_response :success
  end

  test "new renders the earlier-version form" do
    get new_deck_version_path(@deck)

    assert_response :success
  end

  test "edit renders the date form" do
    get edit_deck_version_path(@deck, @version)

    assert_response :success
  end

  # --- snapshot ---------------------------------------------------------------------------------

  test "snapshot is refused while the live list matches the latest version" do
    assert_no_difference -> { DeckVersion.count } do
      post snapshot_deck_versions_path(@deck)
    end

    assert_redirected_to deck_versions_path(@deck)
    assert_predicate flash[:alert], :present?
  end

  test "snapshot with drift records the live list as the next version" do
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 2)

    assert_difference -> { DeckVersion.count }, 1 do
      post snapshot_deck_versions_path(@deck)
    end

    version = @deck.latest_version
    assert_redirected_to deck_version_path(@deck, version)
    assert_equal @deck.deck_cards.pluck(:card_id, :quantity).sort,
      version.deck_version_cards.pluck(:card_id, :quantity).sort
  end

  test "snapshot on a deck with no version at all records version 1" do
    deck = @user.decks.create!(name: "Fresh", standard_pool: standard_pools(:twm_por))

    assert_difference -> { deck.deck_versions.count }, 1 do
      post snapshot_deck_versions_path(deck)
    end
  end

  # --- create (an earlier version) --------------------------------------------------------------

  test "create imports an earlier version and renumbers" do
    assert_difference -> { DeckVersion.count }, 1 do
      post deck_versions_path(@deck), params: { deck_version: {
        decklist: "2 Doublade POR 57", effective_at: "2024-06-01T10:00",
        format: "standard", standard_pool_id: standard_pools(:twm_por).id
      } }
    end

    earlier = DeckVersion.order(:id).last
    assert_redirected_to deck_version_path(@deck, earlier)
    assert_equal 1, earlier.number
    assert_equal 2, @version.number
  end

  test "create refuses an unresolved line and writes nothing" do
    assert_no_difference -> { DeckVersion.count } do
      post deck_versions_path(@deck), params: { deck_version: {
        decklist: "2 Missing POR 999", effective_at: "2024-06-01T10:00",
        format: "standard", standard_pool_id: standard_pools(:twm_por).id
      } }
    end

    assert_response :unprocessable_entity
  end

  # --- update (effective_at only) ---------------------------------------------------------------

  test "update moves effective_at" do
    patch deck_version_path(@deck, @version), params: { deck_version: { effective_at: "2024-01-02T03:04" } }

    assert_redirected_to deck_versions_path(@deck)
    assert_equal Time.zone.parse("2024-01-02 03:04"), @version.reload.effective_at
  end

  test "update refuses a future effective_at" do
    was = @version.effective_at

    patch deck_version_path(@deck, @version),
      params: { deck_version: { effective_at: 2.days.from_now.iso8601 } }

    assert_response :unprocessable_entity
    assert_equal was, @version.reload.effective_at
  end

  test "update never touches the version's content" do
    patch deck_version_path(@deck, @version), params: { deck_version: {
      effective_at: "2024-01-02T03:04", format: "expanded", other_format_name: "x"
    } }

    assert_equal "standard", @version.reload.format
  end

  # --- destroy ----------------------------------------------------------------------------------

  test "destroy refuses a version a result hangs off, naming the count" do
    assert_no_difference -> { DeckVersion.count } do
      delete deck_version_path(@deck, @version)
    end

    assert_redirected_to deck_versions_path(@deck)
    assert_match "1 result", flash[:alert]
  end

  test "destroy refuses a version a participation hangs off, naming the count" do
    deck_results(:one).destroy!

    assert_no_difference -> { DeckVersion.count } do
      delete deck_version_path(@deck, @version)
    end

    assert_match "1 participation", flash[:alert]
  end

  test "destroy removes an empty version and its cards" do
    v2 = drift_and_snapshot

    assert_difference({ -> { DeckVersion.count } => -1, -> { DeckVersionCard.count } => -2 }) do
      delete deck_version_path(@deck, v2)
    end

    assert_redirected_to deck_versions_path(@deck)
  end

  # --- owner only -------------------------------------------------------------------------------

  test "a stranger gets a 404 on every action and changes nothing" do
    stranger_requests.each do |label, request|
      sign_in users(:two)
      assert_no_difference [ -> { DeckVersion.count }, -> { DeckVersionCard.count } ] do
        request.call
      end
      assert_response :not_found, "expected #{label} to 404 for a stranger"
    end

    assert_equal @version.effective_at, @version.reload.effective_at
  end

  private

  def drift_and_snapshot
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)
    Decks::VersionSnapshot.call(@deck)
  end

  # Re-signed before each request, for the reason DeckResultsControllerTest gives: an
  # unhandled RecordNotFound in a before_action skips committing the refreshed session.
  def stranger_requests
    {
      "index" => -> { get deck_versions_path(@deck) },
      "show" => -> { get deck_version_path(@deck, @version) },
      "new" => -> { get new_deck_version_path(@deck) },
      "edit" => -> { get edit_deck_version_path(@deck, @version) },
      "create" => -> {
        post deck_versions_path(@deck), params: { deck_version: {
          decklist: "2 Doublade POR 57", effective_at: "2024-06-01T10:00", format: "expanded"
        } }
      },
      "update" => -> { patch deck_version_path(@deck, @version), params: { deck_version: { effective_at: "2024-01-01" } } },
      "destroy" => -> { delete deck_version_path(@deck, @version) },
      "snapshot" => -> { post snapshot_deck_versions_path(@deck) }
    }
  end
end
