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

  # --- periods (P2) ------------------------------------------------------------------------------

  test "index, show, edit and a refused update hand the view every listed version's period" do
    v2 = drift_and_snapshot

    get deck_versions_path(@deck)
    assert_equal [ @version.id, v2.id ].sort, periods.keys.sort
    period = periods[@version.id]
    assert_equal [ Date.new(2025, 1, 17), tournaments(:one).date, 1, 1 ],
      [ period.first_on, period.last_on, period.results, period.entries ]

    get deck_version_path(@deck, v2)
    assert_equal [ @version.id, v2.id ].sort, periods.keys.sort

    get edit_deck_version_path(@deck, @version)
    assert_equal [ @version.id ], periods.keys

    patch deck_version_path(@deck, @version), params: { deck_version: { effective_at: 2.days.from_now.iso8601 } }
    assert_response :unprocessable_entity
    assert_equal [ @version.id ], periods.keys
  end

  # --- new: defaults (P5) --------------------------------------------------------------------------

  # An earlier version is most likely played under the oldest known classification, not under the
  # deck's current one.
  test "new defaults the classification to the oldest version's" do
    @deck.update!(standard_pool: standard_pools(:twm_asc))

    get new_deck_version_path(@deck)

    form = controller.instance_variable_get(:@form)
    assert_equal "standard", form[:format]
    assert_equal standard_pools(:twm_por).id.to_s, form[:standard_pool_id]
    assert_equal "", form[:other_format_name]
  end

  test "new falls back to the deck's own classification when it has no version" do
    deck = @user.decks.create!(name: "Fresh", format: "other", other_format_name: "Theme Deck")

    get new_deck_version_path(deck)

    form = controller.instance_variable_get(:@form)
    assert_equal [ "other", "", "Theme Deck" ], form.values_at(:format, :standard_pool_id, :other_format_name)
  end

  # --- params.expect --------------------------------------------------------------------------------

  test "a scalar in place of the form is a 400 on both writes, not a 500" do
    assert_no_difference -> { DeckVersion.count } do
      post deck_versions_path(@deck), params: { deck_version: "x" }
    end
    assert_response :bad_request

    # Re-signed: the raised ParameterMissing skips committing the refreshed session.
    sign_in @user
    patch deck_version_path(@deck, @version), params: { deck_version: "x" }
    assert_response :bad_request
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

  # Read before the refused date is assigned: ranked by the date it was refused, v1 would print
  # as v2 on the re-rendered form.
  test "a refused update re-renders the version under its own number" do
    drift_and_snapshot

    patch deck_version_path(@deck, @version), params: { deck_version: { effective_at: 2.days.from_now.iso8601 } }

    assert_response :unprocessable_entity
    assert_equal 1, controller.instance_variable_get(:@version).number
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

  def periods = controller.instance_variable_get(:@periods)

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
