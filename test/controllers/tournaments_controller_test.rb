require "test_helper"

class TournamentsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @tournament = tournaments(:one)
    sign_in @user
  end

  test "index lists the current user's tournaments" do
    get tournaments_path

    assert_response :success
    assert_select ".data-table-row", count: 1
  end

  test "index does not list another user's tournaments" do
    get tournaments_path

    assert_select ".data-table-row", text: /Local League Cup/, count: 0
  end

  test "show renders the tournament" do
    get tournament_path(@tournament)

    assert_response :success
    assert_select "h1", text: @tournament.name
  end

  test "cannot show another user's tournament" do
    get tournament_path(tournaments(:two))

    assert_response :not_found
  end

  test "new renders the form" do
    get new_tournament_path

    assert_response :success
    assert_select "form input[name='tournament[name]']"
  end

  test "create with valid params saves and redirects" do
    assert_difference -> { @user.tournaments.count }, 1 do
      post tournaments_path, params: {
        tournament: {
          name: "City Championship",
          date: "2026-05-01",
          deck_id: @deck.id,
          tier: "league_cup",
          format: "standard",
          standard_pool_id: standard_pools(:twm_por).id,
          participant_count: 20,
          placement: 2
        }
      }
    end

    assert_redirected_to tournament_path(Tournament.last)
  end

  test "create with an explicit standard_pool_id anchors the tournament to that pool" do
    post tournaments_path, params: {
      tournament: {
        name: "City Championship",
        date: "2026-05-01",
        deck_id: @deck.id,
        tier: "league_cup",
        format: "standard",
        standard_pool_id: standard_pools(:twm_asc).id
      }
    }

    assert_redirected_to tournament_path(Tournament.last)
    assert_equal standard_pools(:twm_asc), Tournament.last.standard_pool
  end

  test "create with invalid params re-renders the form" do
    assert_no_difference -> { Tournament.count } do
      post tournaments_path, params: { tournament: { name: "", deck_id: @deck.id } }
    end

    assert_response :unprocessable_entity
  end

  test "create rejects a deck belonging to another user" do
    assert_no_difference -> { Tournament.count } do
      post tournaments_path, params: {
        tournament: { name: "Sneaky", date: "2026-05-01", deck_id: decks(:two).id, tier: "regional" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "update with valid params saves and redirects" do
    patch tournament_path(@tournament), params: { tournament: { name: "Renamed" } }

    assert_redirected_to tournament_path(@tournament)
    assert_equal "Renamed", @tournament.reload.name
  end

  # format: "other" clears standard_pool_id (Tournament#clear_inapplicable_classification), so
  # this tournament's selected pool can only come from the date-based default — never from a
  # stored anchor. The date sits strictly inside twm_asc's window and before twm_por.legal_on,
  # so a correct default differs from StandardPool.current (twm_por): this proves the form
  # picks the pool legal on the tournament's own date, not merely the newest pool.
  test "edit defaults the standard pool selection to the pool legal on the tournament's date" do
    tournament = @user.tournaments.create!(
      deck: @deck, name: "Cup Under An Older Pool", date: Date.new(2025, 12, 1),
      format: "other", other_format_name: "Special Event", tier: "league_cup"
    )

    get edit_tournament_path(tournament)

    assert_response :success
    assert_select "select#tournament_standard_pool_id option[selected][value=?]", standard_pools(:twm_asc).id.to_s
  end

  test "cannot update another user's tournament" do
    patch tournament_path(tournaments(:two)), params: { tournament: { name: "Hacked" } }

    assert_response :not_found
  end

  test "destroy removes the tournament and redirects" do
    assert_difference -> { Tournament.count }, -1 do
      delete tournament_path(@tournament)
    end

    assert_redirected_to tournaments_path
  end

  test "cannot destroy another user's tournament" do
    assert_no_difference -> { Tournament.count } do
      delete tournament_path(tournaments(:two))
    end

    assert_response :not_found
  end

  test "index filters tournaments by name" do
    @user.tournaments.create!(deck: @deck, name: "League Cup Lyon", date: Date.new(2026, 5, 1),
                              format: "standard", standard_pool: standard_pools(:twm_por), tier: "league_cup")

    get tournaments_path(q: "lyon")

    assert_response :success
    assert_select ".data-table-row", count: 1
    assert_select ".data-table-row", text: /League Cup Lyon/
  end

  test "index ignores a blank q" do
    get tournaments_path(q: "   ")

    assert_response :success
    assert_select ".data-table-row", count: 1
  end

  test "index keeps the query in the search field" do
    get tournaments_path(q: "lyon")

    assert_select "form.tournaments-search input[name=q][value=lyon]"
  end

  # The filter form targets this frame (instead of a full-page visit) so the search field
  # survives the live-filtering debounce — see Tournaments::IndexView::FRAME_ID.
  test "index wraps the results table in a turbo frame the filter form targets" do
    get tournaments_path

    assert_response :success
    assert_select "turbo-frame#tournament_results .data-table-row"
    assert_select "form.tournaments-search[data-turbo-frame=tournament_results][data-turbo-action=replace]"
  end

  # The spotlight renders "See all N tournaments" from Search::Global; this page must then show N.
  test "index shows exactly as many tournaments as the spotlight's total promises" do
    @user.tournaments.create!(deck: @deck, name: "Ogerpon Cup", date: Date.new(2026, 5, 1),
                              format: "standard", standard_pool: standard_pools(:twm_por), tier: "league_cup")
    @user.tournaments.create!(deck: @deck, name: "Ogerpon League", date: Date.new(2026, 5, 2),
                              format: "standard", standard_pool: standard_pools(:twm_por), tier: "league_cup")

    get tournaments_path(q: "ogerpon")

    assert_response :success
    assert_equal Search::Global.call(user: @user, query: "ogerpon").tournament_total,
      css_select(".data-table-row").size
  end

  test "a q request renders the matching tournaments inside the turbo frame" do
    @user.tournaments.create!(deck: @deck, name: "League Cup Lyon", date: Date.new(2026, 5, 1),
                              format: "standard", standard_pool: standard_pools(:twm_por), tier: "league_cup")

    get tournaments_path(q: "lyon")

    assert_response :success
    assert_select "turbo-frame#tournament_results .data-table-row", text: /League Cup Lyon/
    assert_select "turbo-frame#tournament_results .data-table-row", count: 1
  end
end
