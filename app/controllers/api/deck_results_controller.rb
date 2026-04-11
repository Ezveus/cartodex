module Api
  class DeckResultsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_deck

    def create
      result = @deck.deck_results.build(deck_result_params)
      result.played_at ||= Time.current

      if result.save
        render json: {
          id: result.id,
          result: result.result,
          archetype: result.archetype&.name,
          notes: result.notes,
          created_at: result.created_at,
          deck_stats: {
            wins: @deck.deck_results.where(result: "win").count,
            losses: @deck.deck_results.where(result: "loss").count,
            draws: @deck.deck_results.where(result: "draw").count,
            timeouts: @deck.deck_results.where(result: "timeout").count
          }
        }, status: :created
      else
        render json: { errors: result.errors.full_messages }, status: :unprocessable_entity
      end
    end

    private

    def set_deck
      @deck = current_user.decks.find(params[:deck_id])
    end

    def deck_result_params
      params.require(:deck_result).permit(:result, :archetype_id, :notes, :played_at)
    end
  end
end
