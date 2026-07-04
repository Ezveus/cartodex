module Api
  class DeckCardsController < ApplicationController
    before_action :authenticate_user!
    before_action :set_deck

    def index
      deck_cards = @deck.deck_cards.includes(:card)
      render json: deck_cards.map { |dc| deck_card_json(dc) }
    end

    def create
      card = Card.find(deck_card_params[:card_id])
      deck_card = Decks::CardAdder.call(deck: @deck, card: card, quantity: deck_card_params[:quantity].to_i)
      render json: deck_card_json(deck_card), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def update
      card = Card.find(params[:id])

      if deck_card_params.key?(:owned_copies)
        deck_card = Decks::OwnedCopiesSetter.call(deck: @deck, card: card, owned_copies: deck_card_params[:owned_copies].to_i)
        render json: deck_card_json(deck_card)
      else
        deck_card = Decks::DeckCardQuantitySetter.call(deck: @deck, card: card, quantity: deck_card_params[:quantity].to_i)
        if deck_card.nil?
          head :no_content
        else
          render json: deck_card_json(deck_card)
        end
      end
    rescue ArgumentError, Decks::OwnedCopiesSetter::NotPhysicalError => e
      render json: { errors: [ e.message ] }, status: :unprocessable_entity
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
      params.require(:deck_card).permit(:card_id, :quantity, :owned_copies)
    end

    def deck_card_json(deck_card)
      {
        id: deck_card.id,
        quantity: deck_card.quantity,
        owned_copies: deck_card.owned_copies,
        proxies: deck_card.proxies,
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
