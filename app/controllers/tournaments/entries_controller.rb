module Tournaments
  # One member's participation in one event. Every entry lookup goes through
  # current_user.tournament_entries, so a stranger's entry is a RecordNotFound rather than a
  # policy question; the *event* named in the URL is looked up unscoped, because it is public.
  class EntriesController < ApplicationController
    before_action :set_tournament
    before_action :set_entry, only: %i[show edit update destroy attach_results detach_result]
    before_action :set_form_collections, only: %i[new create edit update]
    before_action :set_periods, only: %i[edit update]

    def show
      authorize @entry
      @unassigned_results = @entry.deck.deck_results
        .where(tournament_entry_id: nil).order(played_at: :desc)
    end

    def new
      @entry = current_user.tournament_entries.build(tournament: @tournament)
      authorize @entry, :create?
    end

    def create
      @entry = current_user.tournament_entries.build(entry_params.merge(tournament: @tournament))
      authorize @entry, :create?

      if save_with_version(resolve: true)
        redirect_to tournament_entry_path(@tournament, @entry), notice: "Participation recorded."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @entry
    end

    def update
      authorize @entry
      @entry.assign_attributes(entry_params)

      # A new deck needs a version of its own; the one the select posted belongs to the old deck.
      if save_with_version(resolve: @entry.deck_id_changed?)
        redirect_to tournament_entry_path(@tournament, @entry), notice: "Participation updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @entry
      @entry.destroy
      redirect_to mine_tournaments_path, notice: "Participation deleted."
    end

    def attach_results
      authorize @entry, :attach_results?
      ids = Array(params[:deck_result_ids]).map(&:to_i)
      # update_all skips DeckResult#inherit_entry_version, so the version is written here too.
      @entry.deck.deck_results.where(id: ids, tournament_entry_id: nil)
        .update_all(tournament_entry_id: @entry.id, deck_version_id: @entry.deck_version_id)

      redirect_to tournament_entry_path(@tournament, @entry), notice: "Results attached."
    end

    def detach_result
      authorize @entry, :detach_result?
      @entry.deck_results.find(params[:deck_result_id]).update!(tournament_entry_id: nil)

      redirect_to tournament_entry_path(@tournament, @entry), notice: "Result detached."
    end

    private

    def set_tournament
      @tournament = Tournament.with_standard_pool.find(params[:tournament_id])
    end

    def set_entry
      # Scoped by @tournament too, not just current_user: the entry is the reader's own either
      # way, but Tournaments::Entries::Form prints the URL's tournament name and date in its
      # read-only header precisely so the user knows which event they are filling in — a
      # mismatched pair must 404 rather than render somebody else's event above this entry.
      @entry = current_user.tournament_entries
        .includes(:deck, :tournament_profile, deck_results: :archetype)
        .find_by!(id: params[:id], tournament_id: @tournament.id)
    end

    def set_form_collections
      @decks = current_user.decks.order(:name)
      @tournament_profiles = current_user.tournament_profiles.order(:player_name)
      # The edit form's version select. Read before #update assigns anything, so it lists the
      # versions of the deck the entry was saved with.
      @entry_versions = @entry&.persisted? ? @entry.deck.ordered_versions : []
    end

    # What the edit form's version select prints beside each version: when it was played.
    def set_periods
      @periods = Decks::VersionPeriods.call(@entry_versions)
    end

    def entry_params
      params.require(:tournament_entry).permit(
        :deck_id, :deck_version_id, :tournament_profile_id, :participant_count, :placement, :championship_points
      )
    end

    # Resolves the version and saves in one transaction, with save!, so a version snapshotted
    # for an entry that then fails validation does not survive it. A deck that is not the
    # member's is never resolved: the entry refuses it anyway, and resolving first would snapshot
    # a stranger's deck. On ChoiceRequired nothing has been written and the form asks.
    def save_with_version(resolve:)
      TournamentEntry.transaction do
        if resolve && (deck = current_user.decks.find_by(id: @entry.deck_id))
          @entry.deck_version = Decks::VersionResolver.call(deck: deck, choice: params[:version_choice])
        end
        @entry.save!
      end
      true
    rescue ActiveRecord::RecordInvalid
      false
    rescue Decks::VersionResolver::ChoiceRequired => e
      @version_prompt = { current: e.current_number, next: e.next_number, message: e.message }
      # Validate anyway, so the form shows any other error beside the question rather than
      # after it — valid? also fills errors[:deck_version], which the question answers.
      @entry.valid?
      @entry.errors.delete(:deck_version)
      false
    end
  end
end
