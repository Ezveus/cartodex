class CardsController < ApplicationController
  def index
    @blocks = CardSet.by_release
                     .includes(:cards)
                     .group_by(&:block_name)
    @current_set = if params[:set].present?
      CardSet.find_by(code: params[:set])
    end
    @cards = @current_set ? @current_set.cards.order(:set_number) : Card.none
  end

  def show
    @card = Card.includes(:attacks, :abilities, :pokemon_subtype).find(params[:id])
    @alt_printings = Card.where(name: @card.name, fingerprint: @card.fingerprint)
                         .where.not(id: @card.id)
                         .order(:set_name)
  end
end
