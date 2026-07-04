module Tournaments
  class DeckResultsController < ApplicationController
    before_action :set_tournament

    def attach
      ids = Array(params[:deck_result_ids]).map(&:to_i)
      @tournament.deck.deck_results.where(id: ids, tournament_id: nil).update_all(tournament_id: @tournament.id)
      redirect_to @tournament, notice: "Results attached."
    end

    def detach
      result = @tournament.deck_results.find(params[:id])
      result.update!(tournament_id: nil)
      redirect_to @tournament, notice: "Result detached."
    end

    private

    def set_tournament
      @tournament = current_user.tournaments.find(params[:tournament_id])
    end
  end
end
