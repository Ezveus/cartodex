module Api
  class DeckCardsController < ApplicationController
    include DeckCardPayload

    before_action :authenticate_user!
    before_action :set_deck

    def index
      deck_cards = @deck.deck_cards.includes(:card)
      render json: deck_cards.map { |dc| deck_card_json(dc) }
    end

    def create
      card = Card.find(deck_card_params[:card_id])
      deck_card = Decks::CardAdder.call(deck: @deck, card: card, quantity: deck_card_params[:quantity].to_i)
      render json: with_deck_state(deck_card_json(deck_card)), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def update
      card = Card.find(params[:id])

      if deck_card_params.key?(:owned_copies)
        deck_card = Decks::OwnedCopiesSetter.call(deck: @deck, card: card, owned_copies: deck_card_params[:owned_copies].to_i)
        render json: with_deck_state(deck_card_json(deck_card))
      else
        deck_card = Decks::DeckCardQuantitySetter.call(deck: @deck, card: card, quantity: deck_card_params[:quantity].to_i)
        if deck_card.nil?
          # The row is gone, but the deck-level answer still has to reach the page: dropping the
          # deck's last unbacked card retires its "Proxies" badge, and a body-less 204 could not
          # say so. `removed` is what tells the caller the resource no longer exists.
          render json: { removed: true, deck: deck_state }
        else
          render json: with_deck_state(deck_card_json(deck_card))
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

    def deck_card_params
      params.require(:deck_card).permit(:card_id, :quantity, :owned_copies)
    end
  end
end
