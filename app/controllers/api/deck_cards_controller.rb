module Api
  class DeckCardsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_deck

    def index
      deck_cards = @deck.deck_cards.includes(:card)
      render json: deck_cards.map { |dc| deck_card_json(dc) }
    end

    def create
      deck_card = @deck.deck_cards.find_or_initialize_by(card_id: deck_card_params[:card_id])
      deck_card.quantity = deck_card.quantity.to_i + deck_card_params[:quantity].to_i

      if deck_card.save
        render json: deck_card_json(deck_card), status: :created
      else
        render json: { errors: deck_card.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      deck_card = @deck.deck_cards.find_by!(card_id: params[:id])
      new_quantity = deck_card_params[:quantity].to_i

      if new_quantity <= 0
        deck_card.destroy
        head :no_content
      elsif deck_card.update(quantity: new_quantity)
        render json: deck_card_json(deck_card)
      else
        render json: { errors: deck_card.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      deck_card = @deck.deck_cards.find_by!(card_id: params[:id])
      deck_card.destroy
      head :no_content
    end

    private

    def set_deck
      @deck = current_user.decks.find(params[:deck_id])
    end

    def deck_card_params
      params.require(:deck_card).permit(:card_id, :quantity)
    end

    def deck_card_json(deck_card)
      {
        id: deck_card.id,
        quantity: deck_card.quantity,
        card: {
          id: deck_card.card.id,
          name: deck_card.card.name,
          card_type: deck_card.card.card_type,
          set_name: deck_card.card.set_name,
          set_number: deck_card.card.set_number,
          rarity: deck_card.card.rarity,
          hp: deck_card.card.hp,
          type_symbol: deck_card.card.type_symbol
        }
      }
    end
  end
end
