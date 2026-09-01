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

  # For a tournament the comparison is the pool legal on its date, not the newest
  # one: a March 2026 event anchored to the latest pool is a data-entry error, not
  # a deck to refresh.
  #
  # Scoped with assert_select rather than assert_match on the raw body: the pool
  # picker's own <select> already lists every pool by name (including TWM-ASC), so
  # a plain substring match would pass even without the notice rendering at all.
  test "editing a tournament whose anchor disagrees with its date says so" do
    tournaments(:one).update!(date: Date.new(2026, 1, 20), standard_pool: standard_pools(:twm_por))

    get edit_tournament_path(tournaments(:one))

    assert_response :success
    assert_select ".standard-pool-notice", text: /TWM-ASC/
  end

  test "a tournament correctly anchored for its date is not nagged" do
    tournaments(:one).update!(date: Date.new(2026, 3, 14), standard_pool: standard_pools(:twm_por))

    get edit_tournament_path(tournaments(:one))

    assert_response :success
    assert_select ".standard-pool-notice", count: 0
  end

  # No pool was legal yet on this date (StandardPool.at returns nil), so there is
  # nothing to compare the anchor against — the tournament predates the pool
  # calendar this app tracks, not a data-entry error.
  test "a tournament dated before any tracked pool is not nagged despite carrying an anchor" do
    tournaments(:one).update!(date: Date.new(2020, 1, 1), standard_pool: standard_pools(:twm_por))

    get edit_tournament_path(tournaments(:one))

    assert_response :success
    assert_select ".standard-pool-notice", count: 0
  end

  # The other direction from "disagrees with its date says so" above: there the
  # anchor was newer than the date calls for (the "else"/non-stale branch).
  # Here the anchor is older than the date calls for, which is the ordinary
  # staleness branch — reachable for a tournament too, not just a deck, and it
  # is exactly the branch whose copy previously named "this deck" by mistake.
  test "editing a tournament anchored to an older pool than its date calls for is nagged" do
    tournaments(:one).update!(date: Date.new(2026, 2, 1), standard_pool: standard_pools(:twm_asc))

    get edit_tournament_path(tournaments(:one))

    assert_response :success
    assert_select ".standard-pool-notice", text: /TWM-POR/
    assert_select ".standard-pool-notice", text: /released since/
    # Guards the regression that actually shipped and was caught by a human, not by a
    # test: this branch's copy used to read "update it if you still play this deck" on a
    # page that has no deck on it. Both assertions above passed against that wording, so
    # they proved the branch reachable and nothing more. These two only pass on copy that
    # names no record type — which is the contract Ui::StandardPoolNotice documents.
    assert_select ".standard-pool-notice", text: /update the anchor/
    notice = css_select(".standard-pool-notice").first.text
    refute_match(/deck/i, notice, "the notice must not name a record type: it renders for tournaments too")
  end

  # A failed update re-renders the form with whatever was submitted, so a blanked date
  # gets there. StandardPool.at(nil) answers with the newest pool by legal_on rather than
  # nothing, so an unguarded notice would compare the anchor against that and nag about a
  # date the user just erased.
  test "a rejected update that blanked the date is not nagged about the anchor" do
    @tournament.update!(date: Date.new(2026, 2, 1), standard_pool: standard_pools(:twm_asc))

    patch tournament_path(@tournament), params: { tournament: { date: "" } }

    assert_response :unprocessable_entity
    assert_select ".standard-pool-notice", count: 0
  end
end
