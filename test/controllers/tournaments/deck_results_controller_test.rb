require "test_helper"

module Tournaments
  class DeckResultsControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = users(:one)
      @tournament = tournaments(:one)
      @deck = @tournament.deck
      sign_in @user
    end

    test "attach links unassigned results from the same deck to the tournament" do
      result = @deck.deck_results.create!(result: "win", played_at: Time.current)

      post attach_tournament_deck_results_path(@tournament), params: { deck_result_ids: [ result.id ] }

      assert_redirected_to tournament_path(@tournament)
      assert_equal @tournament, result.reload.tournament
    end

    test "attach ignores results from a different deck" do
      other_result = decks(:two).deck_results.create!(result: "win", played_at: Time.current)

      post attach_tournament_deck_results_path(@tournament), params: { deck_result_ids: [ other_result.id ] }

      assert_nil other_result.reload.tournament
    end

    test "detach clears the tournament from a linked result" do
      result = @deck.deck_results.create!(result: "win", played_at: Time.current, tournament: @tournament)

      delete detach_tournament_deck_result_path(@tournament, result)

      assert_redirected_to tournament_path(@tournament)
      assert_nil result.reload.tournament
    end

    test "cannot attach results to another user's tournament" do
      post attach_tournament_deck_results_path(tournaments(:two)), params: { deck_result_ids: [] }

      assert_response :not_found
    end
  end
end
