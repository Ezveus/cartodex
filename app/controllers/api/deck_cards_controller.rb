module Api
  # Every write answers with the written row's keys (or `removed: true` once the row is gone) and
  # DeckCardPayload#fingerprint_payload, which is what lets the deck page redraw the card in place.
  # `?group=set` asks for the rows of the set view.
  class DeckCardsController < ApplicationController
    include DeckCardPayload

    before_action :authenticate_user!
    before_action :set_deck

    # A count or a step the API takes. Far past any deck, and far inside the 8-byte integer column,
    # whose overflow raised a 500 from `save!`.
    COUNT_RANGE = -9_999..9_999
    # An add only adds: Decks::CardAdder sums what it is given, so a negative quantity took copies
    # away under a 201.
    ADD_RANGE = 1..COUNT_RANGE.max

    def index
      deck_cards = @deck.deck_cards.includes(:card)
      render json: deck_cards.map { |dc| deck_card_json(dc) }
    end

    def create
      card = Card.find(deck_card_params[:card_id])
      deck_card = refusing(card) do
        Decks::CardAdder.call(deck: @deck, card: card, quantity: count_param(deck_card_params, :quantity, range: ADD_RANGE))
      end
      return if performed?

      render json: deck_card_json(deck_card).merge(fingerprint_payload(card)), status: :created
    end

    def update
      card = Card.find(params[:id])
      deck_card = refusing(card) { write_update(card, deck_card_params) }
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
      result = refusing(to_card) { Decks::CopyMover.call(deck: @deck, from_card: from_card, to_card: to_card) }
      return if performed?

      render json: deck_card_json(result.to_deck_card).merge(fingerprint_payload(to_card))
    end

    # The sub-rows of a card's "Other printings" — every printing of it neither played nor owned —
    # which the page fetches the first time the list is opened rather than rendering them hidden
    # in every row. Keyed on the fingerprint, so any printing of the card names the list; a card
    # the deck plays in no printing is a 404, like every card this API is asked about.
    #
    # `?group=set` is a set-view row's list: it hangs off that row's printing, which every ⇄ in it
    # moves from (Decks::PrintingRow), so the printing in the URL has to be one the deck plays.
    def other_printings
      card = Card.find(params[:id])
      deck = current_user.decks.includes(deck_cards: :card).find(@deck.id)
      state = Decks::FingerprintStates.call(user: current_user, deck: deck)[card.fingerprint_key]
      set_view = params[:group] == "set"
      raise ActiveRecord::RecordNotFound unless state
      raise ActiveRecord::RecordNotFound if set_view && deck.deck_cards.none? { |row| row.card_id == card.id }

      rows = Decks::OtherPrintingRows.new(state: state, deck: deck, group: set_view ? :set : :type,
                                          source: (card if set_view))
      render json: { fingerprint_key: state.key, html: render_to_string(rows, layout: false) }
    end

    # "+ add to my collection and use it here".
    def collection_copy
      card = Card.find(params[:id])
      deck_card = refusing(card) { Decks::CollectionCopyAdder.call(deck: @deck, card: card) }
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
    #
    # Exactly one of the four counts: given two, the precedence below used one and dropped the other
    # without a word, whichever the caller meant.
    def write_update(card, attributes)
      given = %i[owned_copies_delta owned_copies quantity_delta quantity].select { |key| attributes.key?(key) }
      if given.size > 1
        raise ArgumentError, "give exactly one of quantity, quantity_delta, owned_copies and owned_copies_delta"
      end

      if attributes.key?(:owned_copies_delta)
        Decks::OwnedCopiesSetter.call(deck: @deck, card: card, delta: count_param(attributes, :owned_copies_delta))
      elsif attributes.key?(:owned_copies)
        Decks::OwnedCopiesSetter.call(deck: @deck, card: card, owned_copies: count_param(attributes, :owned_copies))
      elsif attributes.key?(:quantity_delta)
        Decks::DeckCardQuantitySetter.call(deck: @deck, card: card, delta: count_param(attributes, :quantity_delta))
      else
        Decks::DeckCardQuantitySetter.call(deck: @deck, card: card, quantity: count_param(attributes, :quantity))
      end
    end

    # An Integer from JSON, or the decimal string a form posts; anything else is refused (a 422
    # through `refusing`) rather than read by `to_i`, which took 1.5 as 1, "abc" and a missing
    # value as 0 — and a missing `quantity` as "remove the card".
    def count_param(attributes, key, range: COUNT_RANGE)
      value = attributes[key]
      value = Integer(value, 10) if value.is_a?(String) && value.match?(/\A[+-]?\d+\z/)
      unless value.is_a?(Integer) && range.cover?(value)
        raise ArgumentError, "#{key} must be an integer between #{range.min} and #{range.max}"
      end

      value
    end

    # `removed` is what tells the caller the row no longer exists.
    def written(deck_card)
      deck_card ? deck_card_json(deck_card) : { removed: true }
    end
  end
end
