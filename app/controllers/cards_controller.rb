class CardsController < ApplicationController
  def show
    @card = Card.includes(:attacks, :abilities, :pokemon_subtype).find(params[:id])
    @alt_printings = Card.where(name: @card.name, fingerprint: @card.fingerprint)
                         .where.not(id: @card.id)
                         .order(:set_name)
  end
end
