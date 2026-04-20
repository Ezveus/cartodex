require "test_helper"

class TournamentProfilesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @profile = tournament_profiles(:ash)
    sign_in @user
  end

  test "index lists the current user's profiles" do
    get tournament_profiles_path

    assert_response :success
    assert_select ".data-table-row", count: 2
  end

  test "index does not list another user's profiles" do
    get tournament_profiles_path

    assert_select ".data-table-row", text: /Giovanni/, count: 0
  end

  test "new renders the form" do
    get new_tournament_profile_path

    assert_response :success
    assert_select "form input[name='tournament_profile[player_name]']"
  end

  test "create with valid params saves and redirects" do
    assert_difference -> { @user.tournament_profiles.count }, 1 do
      post tournament_profiles_path, params: {
        tournament_profile: {
          player_name: "Brock",
          player_id: "5555555",
          date_of_birth: "2011-04-01"
        }
      }
    end

    assert_redirected_to tournament_profiles_path
  end

  test "create with invalid params re-renders the form" do
    assert_no_difference -> { TournamentProfile.count } do
      post tournament_profiles_path, params: {
        tournament_profile: { player_name: "", player_id: "", date_of_birth: "" }
      }
    end

    assert_response :unprocessable_entity
  end

  test "edit renders the form" do
    get edit_tournament_profile_path(@profile)

    assert_response :success
    assert_select "form input[name='tournament_profile[player_name]'][value=?]", @profile.player_name
  end

  test "update with valid params saves and redirects" do
    patch tournament_profile_path(@profile), params: {
      tournament_profile: { player_name: "Renamed" }
    }

    assert_redirected_to tournament_profiles_path
    assert_equal "Renamed", @profile.reload.player_name
  end

  test "update with invalid params re-renders the form" do
    patch tournament_profile_path(@profile), params: {
      tournament_profile: { player_name: "" }
    }

    assert_response :unprocessable_entity
    assert_equal "Ash Ketchum", @profile.reload.player_name
  end

  test "destroy removes the profile and redirects" do
    assert_difference -> { TournamentProfile.count }, -1 do
      delete tournament_profile_path(@profile)
    end

    assert_redirected_to tournament_profiles_path
  end

  test "cannot edit another user's profile" do
    get edit_tournament_profile_path(tournament_profiles(:giovanni))

    assert_response :not_found
  end

  test "cannot update another user's profile" do
    patch tournament_profile_path(tournament_profiles(:giovanni)), params: {
      tournament_profile: { player_name: "Hacked" }
    }

    assert_response :not_found
    assert_equal "Giovanni", tournament_profiles(:giovanni).reload.player_name
  end

  test "cannot destroy another user's profile" do
    assert_no_difference -> { TournamentProfile.count } do
      delete tournament_profile_path(tournament_profiles(:giovanni))
    end

    assert_response :not_found
  end
end
