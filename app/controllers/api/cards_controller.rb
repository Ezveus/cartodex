module Api
  class CardsController < ApplicationController
    before_action :authenticate_user!

    def index
      query = params[:q].to_s.strip
      cards = if query.length >= 2
        scope = Card.where("name LIKE ?", "%#{query}%")
        scope = scope.where(card_type: params[:type]) if params[:type].present?
        scope.limit(20)
      else
        Card.none
      end
      render json: cards.map { |c| card_json(c) }
    end

    private

    def card_json(card)
      { id: card.id, name: card.name, card_type: card.card_type,
        set_name: card.set_name, set_number: card.set_number,
        image_url: card.image_url }
    end
  end
end
