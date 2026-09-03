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
end
