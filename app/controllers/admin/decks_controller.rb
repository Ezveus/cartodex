module Admin
  class DecksController < BaseController
    def index
      @decks = Deck.includes(:user, :deck_cards).order(created_at: :desc)
    end

    def show
      @deck = Deck.includes(deck_cards: :card, deck_results: []).find(params[:id])
    end
  end
end
