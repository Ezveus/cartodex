module Api
  class CardsController < ApplicationController
    before_action :authenticate_user!

    def index
      query = params[:q].to_s.strip
      cards = if query.length >= 2
        scope = search_scope(query)
        scope = scope.where(card_type: params[:type]) if params[:type].present?
        scope.limit(20)
      else
        Card.none
      end
      render json: cards.map { |c| card_json(c) }
    end

    private

    def search_scope(query)
      tokens = query.split(/\s+/)
      number = tokens.pop if tokens.length > 1 && tokens.last.match?(/\A\d+\z/)
      code = tokens.pop if tokens.length > 1 && set_code?(tokens.last)
      name = tokens.join(" ")

      scope = Card.all
      scope = scope.where("name LIKE ?", "%#{name}%") if name.present?
      scope = scope.where("UPPER(set_name) = ?", code.upcase) if code
      scope = scope.where(set_number: number) if number
      scope
    end

    def set_code?(token)
      token.match?(/\A[a-zA-Z]{2,5}\z/) &&
        CardSet.where("UPPER(code) = ?", token.upcase).exists?
    end

    def card_json(card)
      { id: card.id, name: card.name, card_type: card.card_type,
        set_name: card.set_name, set_number: card.set_number,
        image_url: card.image_url }
    end
  end
end
