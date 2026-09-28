module Api
  class DeckResultsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_deck

    def create
      outcome = Decks::ResultRecorder.call(
        deck: @deck, attributes: deck_result_params, choice: params[:version_choice]
      )
      result = outcome.result

      if outcome.errors.empty?
        render json: {
          id: result.id,
          result: result.result,
          archetype: result.archetype&.name,
          notes: result.notes,
          created_at: result.created_at,
          deck_version: { number: result.deck_version.number, id: result.deck_version_id },
          deck_stats: {
            wins: @deck.deck_results.where(result: "win").count,
            losses: @deck.deck_results.where(result: "loss").count,
            draws: @deck.deck_results.where(result: "draw").count,
            timeouts: @deck.deck_results.where(result: "timeout").count
          }
        }, status: :created
      else
        render json: { errors: outcome.errors }, status: :unprocessable_entity
      end
    rescue Decks::VersionResolver::ChoiceRequired => e
      # Nothing has been written: the modal shows the choices and resubmits with one.
      render json: {
        error: "version_choice_required", current_version: e.current_number, next_version: e.next_number
      }, status: :conflict
    end

    private

    def set_deck
      @deck = current_user.decks.find_by!(key: params[:deck_id])
    end

    def deck_result_params
      params.require(:deck_result).permit(:result, :archetype_id, :notes, :played_at, :match_format, :score, :tournament_entry_id)
    end
  end
end
