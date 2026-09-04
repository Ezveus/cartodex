class DeckResultsController < ApplicationController
  before_action :set_deck
  before_action :preload_tournament_entries, only: [ :edit, :update ]
  before_action :set_result, only: [ :edit, :update, :destroy ]

  def index
    @results = @deck.deck_results.includes(archetype: :primary_card).order(played_at: :desc)
  end

  def edit; end

  def update
    if @result.update(result_params)
      redirect_to deck_deck_results_path(@deck), notice: "Result updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @result.destroy
    redirect_to deck_deck_results_path(@deck), notice: "Result deleted."
  end

  private

  def set_deck
    @deck = current_user.decks.find_by!(key: params[:deck_id])
    authorize @deck, :results?
  end

  # The edit form's tournament picker prints TournamentEntry#picker_label, which reads both the
  # event and the profile — two N+1s without this. Reloaded here rather than preloaded in
  # set_deck because #index and #destroy render no picker and would pay for it too; one extra
  # primary-key SELECT is the same price DecksController pays to preload after authorize.
  def preload_tournament_entries
    @deck = current_user.decks
      .includes(tournament_entries: [ :tournament, :tournament_profile ]).find(@deck.id)
  end

  def set_result
    @result = @deck.deck_results.find(params[:id])
  end

  def result_params
    params.require(:deck_result).permit(:result, :archetype_id, :notes, :played_at, :match_format, :score, :tournament_entry_id)
  end
end
