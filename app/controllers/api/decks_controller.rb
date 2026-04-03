module Api
  class DecksController < ApplicationController
    before_action :authenticate_user!
    before_action :set_deck, only: [ :show, :update, :destroy ]

    def index
      decks = current_user.decks.includes(:deck_cards, :cards)
      render json: decks.map { |deck| deck_json(deck) }
    end

    def show
      render json: deck_json(@deck)
    end

    def create
      deck = current_user.decks.build(deck_params)

      if deck.save
        render json: deck_json(deck), status: :created
      else
        render json: { errors: deck.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def update
      if @deck.update(deck_params)
        render json: deck_json(@deck)
      else
        render json: { errors: @deck.errors.full_messages }, status: :unprocessable_entity
      end
    end

    def destroy
      @deck.destroy
      head :no_content
    end

    private

    def set_deck
      @deck = current_user.decks.find(params[:id])
    end

    def deck_params
      params.require(:deck).permit(:name, :description)
    end

    def deck_json(deck)
      {
        id: deck.id,
        name: deck.name,
        description: deck.description,
        cards: deck.deck_cards.map { |dc| deck_card_json(dc) },
        results: {
          wins: deck.deck_results.where(result: "win").count,
          losses: deck.deck_results.where(result: "loss").count
        }
      }
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
