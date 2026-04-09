class CardsController < ApplicationController
  def show
    @card = Card.includes(:attacks, :abilities, :pokemon_subtype).find(params[:id])
  end
end
