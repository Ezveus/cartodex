class DecksController < ApplicationController
  def index
    @decks = current_user.decks.includes(:deck_cards)
  end

  def show
    @deck = current_user.decks.includes(deck_cards: :card, deck_results: []).find(params[:id])
  end
end
