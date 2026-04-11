class DeckResultsController < ApplicationController
  before_action :set_deck
  before_action :set_result, only: [ :edit, :update, :destroy ]

  def index
    @results = @deck.deck_results.includes(archetype: :primary_pokemon).order(played_at: :desc)
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
    @deck = current_user.decks.find(params[:deck_id])
  end

  def set_result
    @result = @deck.deck_results.find(params[:id])
  end

  def result_params
    params.require(:deck_result).permit(:result, :archetype_id, :notes, :played_at)
  end
end
