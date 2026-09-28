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

    # set_tournament loads the event through Tournament.with_standard_pool — the pool and both of
    # its card-set bounds, because Tournaments::EventDetails prints format_label and
    # StandardPool#name reads them. A view that reaches the event through entry.tournament
    # instead throws all of that away and re-reads it lazily, four queries at a time.
    test "show reuses the preloaded event rather than re-reading it through the entry" do
      get tournament_entry_path(@tournament, @entry) # warm the session

      log = capture_queries { get tournament_entry_path(@tournament, @entry) }

      assert_response :success
      { "tournaments" => 1, "standard_pools" => 1, "card_sets" => 1 }.each do |table, expected|
        actual = log.count { |sql| sql.include?(%(FROM "#{table}")) }
        assert_equal expected, actual, "#{table} read #{actual} times:\n#{log.join("\n")}"
      end
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
      result = @deck.deck_results.create!(result: "win", played_at: Time.current, deck_version: deck_versions(:one))

      post attach_results_tournament_entry_path(@tournament, @entry), params: { deck_result_ids: [ result.id ] }

      assert_redirected_to tournament_entry_path(@tournament, @entry)
      assert_equal @entry, result.reload.tournament_entry
    end

    test "attach_results ignores results from a different deck" do
      other = decks(:two).deck_results.create!(result: "win", played_at: Time.current, deck_version: deck_versions(:two))

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

    test "create on a drifted deck asks which version and writes nothing" do
      drift(@deck)

      assert_no_difference [ -> { TournamentEntry.count }, -> { DeckVersion.count }, -> { DeckVersionCard.count } ] do
        post tournament_entries_path(tournaments(:two)), params: {
          tournament_entry: { deck_id: @deck.id }
        }
      end

      assert_response :unprocessable_entity
      assert_select "input[type=radio][name=version_choice][value=new]"
      assert_select "input[type=radio][name=version_choice][value=current]"
      assert_select "label", text: "Create version 2 from the current list"
      assert_select "label", text: "Attach to version 1"
    end

    test "create on a drifted deck with new records the participation on version 2" do
      drift(@deck)

      assert_difference -> { DeckVersion.count }, 1 do
        post tournament_entries_path(tournaments(:two)), params: {
          tournament_entry: { deck_id: @deck.id }, version_choice: "new"
        }
      end

      created = @user.tournament_entries.order(:id).last
      assert_redirected_to tournament_entry_path(tournaments(:two), created)
      assert_equal @deck.latest_version, created.deck_version
      assert_equal 2, created.deck_version.number
    end

    test "create on a drifted deck with current records the participation on version 1" do
      drift(@deck)

      assert_no_difference -> { DeckVersion.count } do
        post tournament_entries_path(tournaments(:two)), params: {
          tournament_entry: { deck_id: @deck.id }, version_choice: "current"
        }
      end

      assert_equal deck_versions(:one), @user.tournament_entries.order(:id).last.deck_version
    end

    # Resolving a stranger's drifted deck would ask the member a question about somebody else's
    # list — and, answered "new", snapshot it inside a transaction only the refusal rolls back.
    test "create with somebody else's deck neither versions it nor asks" do
      drift(decks(:two))

      assert_no_difference [ -> { TournamentEntry.count }, -> { DeckVersion.count } ] do
        post tournament_entries_path(tournaments(:two)), params: {
          tournament_entry: { deck_id: decks(:two).id }
        }
      end

      assert_response :unprocessable_entity
      assert_select "input[name=version_choice]", count: 0
    end

    test "attach_results files the results on the participation's version" do
      v2 = Decks::VersionSnapshot.call(@deck)
      result = @deck.deck_results.create!(result: "win", played_at: Time.current, deck_version: v2)

      post attach_results_tournament_entry_path(@tournament, @entry), params: { deck_result_ids: [ result.id ] }

      assert_equal deck_versions(:one), result.reload.deck_version
    end

    test "update moves the participation and its results to another version" do
      result = @deck.deck_results.create!(result: "win", tournament_entry: @entry)
      v2 = Decks::VersionSnapshot.call(@deck)

      patch tournament_entry_path(@tournament, @entry), params: {
        tournament_entry: { deck_version_id: v2.id }
      }

      assert_redirected_to tournament_entry_path(@tournament, @entry)
      assert_equal v2, @entry.reload.deck_version
      assert_equal v2, result.reload.deck_version
    end

    test "update refuses a version of another deck" do
      patch tournament_entry_path(@tournament, @entry), params: {
        tournament_entry: { deck_version_id: deck_versions(:two).id }
      }

      assert_response :unprocessable_entity
      assert_equal deck_versions(:one), @entry.reload.deck_version
    end

    test "update to a drifted deck asks which version, then files it on the choice" do
      other = @user.decks.create!(name: "Other", standard_pool: standard_pools(:twm_por))
      drift(other)

      assert_no_difference -> { DeckVersion.count } do
        patch tournament_entry_path(@tournament, @entry), params: { tournament_entry: { deck_id: other.id } }
      end
      assert_response :unprocessable_entity
      assert_equal @deck, @entry.reload.deck

      patch tournament_entry_path(@tournament, @entry), params: {
        tournament_entry: { deck_id: other.id }, version_choice: "current"
      }
      assert_redirected_to tournament_entry_path(@tournament, @entry)
      assert_equal other, @entry.reload.deck
      assert_equal other.latest_version, @entry.deck_version
    end

    test "edit costs the same with one version as with four" do
      get edit_tournament_entry_path(@tournament, @entry) # warm the session

      small = ActiveRecord::Base.uncached { count_queries { get edit_tournament_entry_path(@tournament, @entry) } }
      3.times { |i| Decks::VersionSnapshot.call(@deck, effective_at: (i + 1).days.ago) }
      large = ActiveRecord::Base.uncached { count_queries { get edit_tournament_entry_path(@tournament, @entry) } }

      assert_response :success
      assert_equal small, large, "query count grew with the version count: #{small} -> #{large}"
    end

    private

    # Leaves the deck on a version its live list no longer matches.
    def drift(deck)
      deck_version_for(deck)
      deck.deck_cards.create!(card: cards(:froakie_twm), quantity: 1)
    end
  end
end
