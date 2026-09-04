require "test_helper"

# DeckResultsController is not PubliclyReachable: every action stays behind authenticate_user!,
# and #set_deck scopes the lookup to current_user.decks, so a stranger's request never finds the
# deck at all — RecordNotFound renders 404, the same page an unknown key renders elsewhere in
# the app, rather than a 403 that would out the deck's existence.
class DeckResultsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user)
    @result = @deck.deck_results.create!(result: "win")
  end

  test "signed out, every action redirects to sign in and changes nothing" do
    get deck_deck_results_path(@deck)
    assert_redirected_to new_user_session_path

    get edit_deck_deck_result_path(@deck, @result)
    assert_redirected_to new_user_session_path

    patch deck_deck_result_path(@deck, @result), params: { deck_result: { result: "loss" } }
    assert_redirected_to new_user_session_path

    delete deck_deck_result_path(@deck, @result)
    assert_redirected_to new_user_session_path

    assert_equal "win", @result.reload.result
    assert DeckResult.exists?(@result.id)
  end

  test "signed in as the owner, index and edit answer, update and destroy act" do
    sign_in @user

    get deck_deck_results_path(@deck)
    assert_response :success

    get edit_deck_deck_result_path(@deck, @result)
    assert_response :success

    patch deck_deck_result_path(@deck, @result), params: { deck_result: { result: "loss" } }
    assert_redirected_to deck_deck_results_path(@deck)
    assert_equal "loss", @result.reload.result

    delete deck_deck_result_path(@deck, @result)
    assert_redirected_to deck_deck_results_path(@deck)
    assert_not DeckResult.exists?(@result.id)
  end

  # The same picker as Decks::ResultModal, and the same trap: one deck can carry two
  # participations in one event, one per Play! Pokémon profile.
  test "the edit form tells two participations in one event apart" do
    sign_in @user
    second = @user.tournament_entries.create!(
      tournament: tournaments(:one), deck: @deck, tournament_profile: tournament_profiles(:misty)
    )

    get edit_deck_deck_result_path(@deck, @result)

    assert_response :success
    assert_select "option[value=?]", tournament_entries(:one).id.to_s, text: /Ash Ketchum/
    assert_select "option[value=?]", second.id.to_s, text: /Misty/
  end

  # Same picker, same preload obligation: DeckResults::EditView prints picker_label, which reads
  # both the event and the profile. An event and a profile of its own per participation, or rows
  # sharing an id issue identical SQL the query cache serves and count_queries never sees.
  test "edit issues a constant number of queries regardless of how many participations" do
    sign_in @user
    get edit_deck_deck_result_path(@deck, @result) # warm the session

    small = count_queries { get edit_deck_deck_result_path(@deck, @result) }

    3.times { |i| participation_of_its_own(i) }

    large = count_queries { get edit_deck_deck_result_path(@deck, @result) }

    assert_response :success
    assert_equal small, large, "query count grew with the participation count: #{small} -> #{large}"
  end

  test "signed in as a stranger, every action 404s and changes nothing" do
    # Re-sign in before each request: an unhandled RecordNotFound raised inside a before_action
    # propagates straight past the session middleware (it never reaches the point where it
    # would commit a refreshed session cookie), which the *next* request in the same
    # integration session then reads as signed out. One assertion per fresh session avoids
    # attributing that framework quirk to the controller under test.
    sign_in users(:two)
    get deck_deck_results_path(@deck)
    assert_response :not_found

    sign_in users(:two)
    get edit_deck_deck_result_path(@deck, @result)
    assert_response :not_found

    sign_in users(:two)
    patch deck_deck_result_path(@deck, @result), params: { deck_result: { result: "loss" } }
    assert_response :not_found

    sign_in users(:two)
    delete deck_deck_result_path(@deck, @result)
    assert_response :not_found

    assert_equal "win", @result.reload.result
    assert DeckResult.exists?(@result.id)
  end
  private

  def participation_of_its_own(index)
    event = Tournament.create!(
      name: "Quiet Open #{index}", date: Date.new(2026, 5, 1) + index,
      tier: "league_cup", format: "expanded", created_by: @user
    )
    profile = @user.tournament_profiles.create!(
      player_name: "Player #{index}", player_id: "200000#{index}", date_of_birth: Date.new(2000, 1, 1)
    )
    @user.tournament_entries.create!(tournament: event, deck: @deck, tournament_profile: profile)
  end
end
