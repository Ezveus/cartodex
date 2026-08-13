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
          participant_count: 20,
          placement: 2
        }
      }
    end

    assert_redirected_to tournament_path(Tournament.last)
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
                              format: "standard", tier: "league_cup")

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
end
