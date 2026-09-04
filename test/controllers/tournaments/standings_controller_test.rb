require "test_helper"

class Tournaments::StandingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @tournament = tournaments(:one)
    @standing = tournament_standings(:giovanni_masters) # created_by users(:two)
    sign_in @user
  end

  test "a member records a standing on an event they did not catalogue" do
    sign_in users(:two) # tournaments(:one) was catalogued by users(:one)

    assert_difference -> { TournamentStanding.count }, 1 do
      post tournament_standings_path(@tournament), params: { tournament_standing: {
        player_name: "Brock", division: "masters", placement: 4,
        wins: 6, losses: 2, ties: 1, archetype_id: archetypes(:ogerpon).id
      } }
    end

    assert_redirected_to tournament_path(@tournament)
    standing = TournamentStanding.order(:id).last
    assert_equal "Brock", standing.player_name
    assert_equal "brock", standing.player_name_normalized
    assert_equal users(:two), standing.created_by
  end

  # Wiki governance, decision 3: correcting a public record is not a property question.
  test "a member may edit and delete a row another member typed" do
    patch tournament_standing_path(@tournament, @standing),
      params: { tournament_standing: { placement: 3 } }

    assert_redirected_to tournament_path(@tournament)
    assert_equal 3, @standing.reload.placement

    assert_difference -> { TournamentStanding.count }, -1 do
      delete tournament_standing_path(@tournament, @standing)
    end
  end

  test "a row belonging to another event 404s rather than rendering under this header" do
    get edit_tournament_standing_path(tournaments(:two), @standing)

    assert_response :not_found
  end

  # Without this, the wiki edit form would let any member attach their own participation to a row
  # naming somebody else, or detach yours. The link is written only by claim/unclaim.
  test "tournament_entry_id is not mass-assignable" do
    patch tournament_standing_path(@tournament, @standing), params: { tournament_standing: {
      placement: 5, tournament_entry_id: tournament_entries(:one).id
    } }

    assert_redirected_to tournament_path(@tournament)
    assert_equal 5, @standing.reload.placement
    assert_nil @standing.tournament_entry_id
  end

  test "the uniqueness error renders a link to the clashing row" do
    assert_no_difference -> { TournamentStanding.count } do
      post tournament_standings_path(@tournament), params: { tournament_standing: {
        player_name: "  GIOVANNI  ", division: "masters", archetype_id: archetypes(:ogerpon).id
      } }
    end

    assert_response :unprocessable_entity
    assert_select ".form-hint", text: /already has a standing/
    assert_select ".form-hint a[href=?]", tournament_path(@tournament)
  end

  test "new prefills from the reader's own participation" do
    get new_tournament_standing_path(@tournament, tournament_entry_id: tournament_entries(:one).id)

    assert_response :success
    # tournament_profiles(:ash) was born in 2014, so the 2026 season puts them in juniors.
    assert_select "input[name=?][value=?]", "tournament_standing[player_name]", "Ash Ketchum"
    assert_select "select[name=?] option[selected][value=?]", "tournament_standing[division]", "junior"
    assert_select "input[name=?][value=?]", "tournament_standing[placement]", "33"
    # The hidden field is what carries the link through to #create, outside the permitted params.
    assert_select "input[type=hidden][name=tournament_entry_id][value=?]",
      tournament_entries(:one).id.to_s
  end

  test "prefilling from another member's participation 404s" do
    get new_tournament_standing_path(@tournament,
      tournament_entry_id: tournament_entries(:shared_event).id) # users(:two)'s

    assert_response :not_found
  end

  test "creating from a prefill links the participation" do
    post tournament_standings_path(@tournament), params: {
      tournament_entry_id: tournament_entries(:one).id,
      tournament_standing: {
        player_name: "Ash Ketchum", division: "junior",
        archetype_id: archetypes(:ogerpon).id
      }
    }

    assert_redirected_to tournament_path(@tournament)
    assert_equal tournament_entries(:one), TournamentStanding.order(:id).last.tournament_entry
  end

  test "a signed-out request is sent to sign in and writes nothing" do
    sign_out @user
    placement_was = @standing.placement

    post tournament_standings_path(@tournament), params: { tournament_standing: {
      player_name: "Brock", division: "masters", archetype_id: archetypes(:ogerpon).id
    } }
    assert_redirected_to new_user_session_path

    patch tournament_standing_path(@tournament, @standing),
      params: { tournament_standing: { placement: 1 } }
    assert_redirected_to new_user_session_path

    delete tournament_standing_path(@tournament, @standing)
    assert_redirected_to new_user_session_path

    assert_equal placement_was, @standing.reload.placement
    assert_equal 2, TournamentStanding.count
  end

  test "the event page offers the write controls to a member and none to a visitor" do
    get tournament_path(@tournament)
    assert_select "a[href=?]", new_tournament_standing_path(@tournament), text: "Add a standing"
    assert_select "a[href=?]", edit_tournament_standing_path(@tournament, @standing)

    sign_out @user
    get tournament_path(@tournament)
    assert_select "a[href=?]", new_tournament_standing_path(@tournament), count: 0
    assert_select "a[href=?]", edit_tournament_standing_path(@tournament, @standing), count: 0
  end

  test "a member claims a row somebody else typed" do
    post claim_tournament_standing_path(@tournament, @standing,
      tournament_entry_id: tournament_entries(:one).id)

    assert_redirected_to tournament_path(@tournament)
    assert_equal tournament_entries(:one), @standing.reload.tournament_entry
  end

  test "claiming with another member's participation 404s and links nothing" do
    post claim_tournament_standing_path(@tournament, @standing,
      tournament_entry_id: tournament_entries(:shared_event).id) # users(:two)'s

    assert_response :not_found
    assert_nil @standing.reload.tournament_entry_id
  end

  test "claiming with a participation from another event 404s" do
    post claim_tournament_standing_path(@tournament, @standing,
      tournament_entry_id: tournament_entries(:two).id) # users(:two)'s, and another event

    assert_response :not_found
  end

  # The partial UNIQUE index on tournament_entry_id is what stops a member publishing themselves
  # twice under two spellings of their own name, which the player-name key cannot see.
  # Preflight ruling 4: if this does not raise through the request stack (Rails 8 test env uses
  # show_exceptions = :rescuable, and RecordNotUnique is not rescuable, so it should), move the
  # test to test/models/tournament_standing_test.rb and assert the raise on
  # standing.update!(tournament_entry: …) directly. The property under test is the partial UNIQUE
  # index — a database guarantee, not a controller behaviour.
  test "one participation may back only one row" do
    @standing.update!(tournament_entry: tournament_entries(:one))

    assert_raises ActiveRecord::RecordNotUnique do
      post claim_tournament_standing_path(@tournament, tournament_standings(:ash_masters),
        tournament_entry_id: tournament_entries(:one).id)
    end
  end

  test "the member whose participation is linked may sever the link" do
    @standing.update!(tournament_entry: tournament_entries(:one))

    delete unclaim_tournament_standing_path(@tournament, @standing)

    assert_redirected_to tournament_path(@tournament)
    assert_nil @standing.reload.tournament_entry_id
  end

  # The one owner-scoped rule in this controller: anybody may correct the public data on a row,
  # only its claimant may unlink it.
  test "another member may not sever somebody else's link" do
    @standing.update!(tournament_entry: tournament_entries(:one)) # users(:one)'s
    sign_in users(:two)

    delete unclaim_tournament_standing_path(@tournament, @standing)

    # A redirect with an alert, not a 403 and not a 404: an event and its sheet are public, so the
    # refusal has somewhere to send the member — the same answer TournamentsController gives a
    # member who may not edit an event. See the controller's own refuse_with_redirect.
    assert_redirected_to tournament_path(@tournament)
    assert_match(/can unlink it/, flash[:alert])
    assert_equal tournament_entries(:one), @standing.reload.tournament_entry
  end
end
