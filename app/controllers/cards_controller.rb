class CardsController < ApplicationController
  def index
    @sets = Card.group(:set_name, :set_full_name)
               .order(:set_full_name)
               .count
    @current_set = params[:set]
    @cards = if @current_set.present?
      Card.where(set_name: @current_set).order(:set_number)
    else
      Card.none
    end
  end

  def show
    @card = Card.includes(:attacks, :abilities, :pokemon_subtype).find(params[:id])
    @alt_printings = Card.where(name: @card.name, fingerprint: @card.fingerprint)
                         .where.not(id: @card.id)
                         .order(:set_name)
  end
end
