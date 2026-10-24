module Api
  # Every write answers with the written row's keys (or `removed: true` once the row is gone) and
  # DeckCardPayload#fingerprint_payload, which is what lets the deck page redraw the card in place.
  # `?group=set` asks for the rows of the set view.
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
      deck_card = refusing { Decks::CardAdder.call(deck: @deck, card: card, quantity: deck_card_params[:quantity].to_i) }
      return if performed?

      render json: deck_card_json(deck_card).merge(fingerprint_payload(card)), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    def update
      card = Card.find(params[:id])
      deck_card = refusing do
        if deck_card_params.key?(:owned_copies)
          Decks::OwnedCopiesSetter.call(deck: @deck, card: card, owned_copies: deck_card_params[:owned_copies].to_i)
        else
          Decks::DeckCardQuantitySetter.call(deck: @deck, card: card, quantity: deck_card_params[:quantity].to_i)
        end
      end
      return if performed?

      render json: written(deck_card).merge(fingerprint_payload(card))
    end

    # Answers like every other write rather than with a 204: the page has a row to take away and,
    # when it was the section's last, a section with it.
    def destroy
      deck_card = @deck.deck_cards.find_by!(card_id: params[:id])
      deck_card.destroy!
      render json: written(nil).merge(fingerprint_payload(deck_card.card))
    end

    # ⇄: one copy from `from_card_id` onto the printing in the URL, the deck's size unchanged. The
    # source has to be in the deck — a 404 otherwise, like every card this API is asked about —
    # while the target need not be: landing on a printing the deck does not play is the point.
    def move
      to_card = Card.find(params[:id])
      from_card = @deck.deck_cards.find_by!(card_id: params.require(:move).require(:from_card_id)).card
      result = refusing { Decks::CopyMover.call(deck: @deck, from_card: from_card, to_card: to_card) }
      return if performed?

      render json: deck_card_json(result.to_deck_card).merge(fingerprint_payload(to_card))
    end

    # "+ add to my collection and use it here".
    def collection_copy
      card = Card.find(params[:id])
      deck_card = refusing { Decks::CollectionCopyAdder.call(deck: @deck, card: card) }
      return if performed?

      render json: deck_card_json(deck_card).merge(fingerprint_payload(card))
    end

    private

    def deck_card_params
      params.require(:deck_card).permit(:card_id, :quantity, :owned_copies)
    end

    # `removed` is what tells the caller the row no longer exists.
    def written(deck_card)
      deck_card ? deck_card_json(deck_card) : { removed: true }
    end
  end
end
