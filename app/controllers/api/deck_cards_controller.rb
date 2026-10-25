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
      deck_card = refusing { write_update(card, deck_card_params) }
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
      from_card = @deck.deck_cards.find_by!(card_id: params.expect(move: [ :from_card_id ])[:from_card_id]).card
      result = refusing { Decks::CopyMover.call(deck: @deck, from_card: from_card, to_card: to_card) }
      return if performed?

      render json: deck_card_json(result.to_deck_card).merge(fingerprint_payload(to_card))
    end

    # The sub-rows of a card's "Other printings" — every printing of it neither played nor owned —
    # which the page fetches the first time the list is opened rather than rendering them hidden
    # in every row. Keyed on the fingerprint, so any printing of the card names the list; a card
    # the deck plays in no printing is a 404, like every card this API is asked about.
    def other_printings
      card = Card.find(params[:id])
      deck = current_user.decks.includes(deck_cards: :card).find(@deck.id)
      state = Decks::FingerprintStates.call(user: current_user, deck: deck)[card.fingerprint_key]
      raise ActiveRecord::RecordNotFound unless state

      html = render_to_string(Decks::OtherPrintingRows.new(state: state, deck: deck), layout: false)
      render json: { fingerprint_key: state.key, html: html }
    end

    # "+ add to my collection and use it here".
    def collection_copy
      card = Card.find(params[:id])
      deck_card = refusing { Decks::CollectionCopyAdder.call(deck: @deck, card: card) }
      return if performed?

      render json: deck_card_json(deck_card).merge(fingerprint_payload(card))
    end

    private

    # `expect` rather than `require.permit`: a body whose `deck_card` is not a hash is a 400, where
    # `permit` on a String was a NoMethodError and a 500.
    def deck_card_params
      params.expect(deck_card: [ :card_id, :quantity, :owned_copies, :quantity_delta, :owned_copies_delta ])
    end

    # The deck page's steppers send a step (`*_delta`), which the setter resolves against the
    # stored row; an absolute count is still taken from the API's other callers.
    def write_update(card, attributes)
      if attributes.key?(:owned_copies_delta)
        Decks::OwnedCopiesSetter.call(deck: @deck, card: card, delta: attributes[:owned_copies_delta].to_i)
      elsif attributes.key?(:owned_copies)
        Decks::OwnedCopiesSetter.call(deck: @deck, card: card, owned_copies: attributes[:owned_copies].to_i)
      elsif attributes.key?(:quantity_delta)
        Decks::DeckCardQuantitySetter.call(deck: @deck, card: card, delta: attributes[:quantity_delta].to_i)
      else
        Decks::DeckCardQuantitySetter.call(deck: @deck, card: card, quantity: attributes[:quantity].to_i)
      end
    end

    # `removed` is what tells the caller the row no longer exists.
    def written(deck_card)
      deck_card ? deck_card_json(deck_card) : { removed: true }
    end
  end
end
