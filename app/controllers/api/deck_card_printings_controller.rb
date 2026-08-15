module Api
  # Reads the printings a deck slot could move to, and moves it. Separate from DeckCardsController
  # because that one identifies a row by its card id — the very thing a swap changes.
  class DeckCardPrintingsController < ApplicationController
    include DeckCardPayload

    before_action :authenticate_user!
    before_action :set_deck
    before_action :set_card

    def index
      render json: Cards::Printings.call(user: current_user, card: @card, deck: @deck)
    end

    def update
      target = Card.find(printing_params[:card_id])
      # Read before the write: afterwards the two rows are one, and nothing tells them apart.
      merged = @deck.deck_cards.exists?(card_id: target.id)

      deck_card = Decks::PrintingSwapper.call(deck: @deck, card: @card, target_card: target)

      render json: with_deck_state(deck_card_json(deck_card).merge(merged: merged, **row_state(deck_card)))
    rescue ArgumentError => e
      render json: { errors: [ e.message ] }, status: :unprocessable_entity
    end

    private

    def set_card
      @card = Card.find(params[:card_id])
    end

    def printing_params
      params.require(:printing).permit(:card_id)
    end

    # Everything about the row that the new printing changes and deck_card_json does not carry.
    # The page rewrites the row in place, so anything left out of here stays on screen describing
    # the printing that is no longer there.
    #
    # One availability lookup answers both numbers: `committed` counts every physical deck (this
    # one included, post-write), while `available` already excludes this deck — which is exactly
    # the bound Decks::ShowView caps the allocation stepper with.
    def row_state(deck_card)
      card = deck_card.card
      availability = Allocations::Availability.call(user: current_user, card: card, excluding_deck: @deck)

      {
        max_owned: @deck.physical? ? [ deck_card.quantity, availability.available ].min : 0,
        over_allocated: availability.committed > availability.owned,
        image_path: card.image_url.present? ? image_card_path(card) : nil
      }
    end
  end
end
