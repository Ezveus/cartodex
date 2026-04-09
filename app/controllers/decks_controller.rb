class DecksController < ApplicationController
  def index
    @decks = current_user.decks.includes(:deck_cards)
  end
end
