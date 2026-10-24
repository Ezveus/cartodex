module Api
  # Reads the printings a deck slot could move to, and moves it. Separate from DeckCardsController
  # because that one identifies a row by its card id — the very thing a swap changes. No page calls
  # either action since ⇄ replaced the printing picker; both stay for API clients, and the swap
  # answers with the same fingerprint payload as every other deck write.
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
      result = refusing { Decks::PrintingSwapper.call(deck: @deck, card: @card, target_card: target) }
      return if performed?

      deck_card = result.deck_card
      render json: deck_card_json(deck_card).merge(merged: result.merged, **row_state(deck_card))
                                            .merge(fingerprint_payload(target))
    end

    private

    def set_card
      @card = Card.find(params[:card_id])
    end

    def printing_params
      params.expect(printing: [ :card_id ])
    end

    # Everything about the row that the new printing changes and deck_card_json does not carry —
    # what the printing picker rewrote its row from. The picker is gone and the page now redraws
    # from the fingerprint payload, but the answer keeps its keys for any other caller.
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
