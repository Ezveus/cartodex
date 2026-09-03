require "test_helper"

module Tournaments
  class EntriesControllerTest < ActionDispatch::IntegrationTest
    include Devise::Test::IntegrationHelpers

    setup do
      @user = users(:one)
      @entry = tournament_entries(:one)
      @tournament = @entry.tournament
      @deck = @entry.deck
      sign_in @user
    end

    test "show renders the participation and the event's own facts" do
      get tournament_entry_path(@tournament, @entry)

      assert_response :success
      assert_select "h1", text: /#{@tournament.name}/
      assert_select ".tournament-details", text: /#{@tournament.tier_label}/
      assert_select ".data-table-cell", text: "##{@entry.placement} / #{@entry.participant_count}"
    end

    test "cannot show another member's participation" do
      get tournament_entry_path(tournaments(:two), tournament_entries(:two))

      assert_response :not_found
    end

    test "cannot show the reader's own participation under a different event's URL" do
      # @entry belongs to @tournament (tournaments(:one)); asking for it via tournaments(:two)'s
      # URL must 404 rather than render, since the read-only header would otherwise show
      # tournaments(:two)'s name and date above tournaments(:one)'s participation.
      get tournament_entry_path(tournaments(:two), @entry)

      assert_response :not_found
    end

    test "new renders the participation form and nothing about the event's own fields" do
      get new_tournament_entry_path(tournaments(:two))

      assert_response :success
      assert_select "form select[name='tournament_entry[deck_id]']"
      assert_select "form input[name='tournament_entry[name]']", count: 0
    end

    test "create records the participation against the event" do
      assert_difference -> { @user.tournament_entries.count }, 1 do
        post tournament_entries_path(tournaments(:two)), params: {
          tournament_entry: { deck_id: @deck.id, participant_count: 20, placement: 2 }
        }
      end

      created = @user.tournament_entries.order(:id).last
      assert_equal tournaments(:two), created.tournament
      assert_redirected_to tournament_entry_path(tournaments(:two), created)
    end

    test "create refuses a second participation for the same player" do
      assert_no_difference -> { TournamentEntry.count } do
        post tournament_entries_path(@tournament), params: {
          tournament_entry: { deck_id: @deck.id, tournament_profile_id: @entry.tournament_profile_id }
        }
      end

      assert_response :unprocessable_entity
    end

    test "create refuses a deck belonging to another member" do
      assert_no_difference -> { TournamentEntry.count } do
        post tournament_entries_path(tournaments(:two)), params: {
          tournament_entry: { deck_id: decks(:two).id }
        }
      end

      assert_response :unprocessable_entity
    end

    test "update saves the participation" do
      patch tournament_entry_path(@tournament, @entry), params: {
        tournament_entry: { placement: 4 }
      }

      assert_redirected_to tournament_entry_path(@tournament, @entry)
      assert_equal 4, @entry.reload.placement
    end

    test "cannot update another member's participation" do
      patch tournament_entry_path(tournaments(:two), tournament_entries(:two)), params: {
        tournament_entry: { placement: 1 }
      }

      assert_response :not_found
    end

    test "destroy removes the participation and leaves the event standing" do
      assert_difference -> { TournamentEntry.count }, -1 do
        assert_no_difference -> { Tournament.count } do
          delete tournament_entry_path(@tournament, @entry)
        end
      end

      assert_redirected_to mine_tournaments_path
    end

    test "attach_results links unassigned results from the same deck to the participation" do
      result = @deck.deck_results.create!(result: "win", played_at: Time.current)

      post attach_results_tournament_entry_path(@tournament, @entry), params: { deck_result_ids: [ result.id ] }

      assert_redirected_to tournament_entry_path(@tournament, @entry)
      assert_equal @entry, result.reload.tournament_entry
    end

    test "attach_results ignores results from a different deck" do
      other = decks(:two).deck_results.create!(result: "win", played_at: Time.current)

      post attach_results_tournament_entry_path(@tournament, @entry), params: { deck_result_ids: [ other.id ] }

      assert_nil other.reload.tournament_entry
    end

    test "detach_result clears the participation from a linked result" do
      result = @deck.deck_results.create!(result: "win", played_at: Time.current, tournament_entry: @entry)

      delete detach_result_tournament_entry_path(@tournament, @entry), params: { deck_result_id: result.id }

      assert_redirected_to tournament_entry_path(@tournament, @entry)
      assert_nil result.reload.tournament_entry
    end

    test "cannot attach results to another member's participation" do
      post attach_results_tournament_entry_path(tournaments(:two), tournament_entries(:two)),
        params: { deck_result_ids: [] }

      assert_response :not_found
    end
  end
end
