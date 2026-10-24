module Decks
  # Sets the real (owned-backed) copy count of an existing card in a physical
  # deck. The new value is bounded by the deck_card's total and by availability,
  # so an edit can never create over-allocation (only a collection decrease can).
  #
  # Either `owned_copies:` (an absolute count) or `delta:` (the deck page's step), never both. A
  # step is resolved against the row read inside the transaction, so a stale tab's "−" is refused
  # at 0 rather than sent as an absolute value that claims reals.
  class OwnedCopiesSetter < ApplicationService
    class NotPhysicalError < StandardError; end

    def initialize(deck:, card:, owned_copies: nil, delta: nil)
      @deck = deck
      @card = card
      @owned_copies = owned_copies
      @delta = delta
    end

    def call
      raise NotPhysicalError, "deck is not physical" unless @deck.physical?
      raise ArgumentError, "give exactly one of owned_copies and delta" if @owned_copies.nil? == @delta.nil?
      raise ArgumentError, "delta must be an integer" unless @delta.nil? || @delta.is_a?(Integer)

      serialized_transaction do
        deck_card = @deck.deck_cards.find_by!(card: @card)
        owned_copies = @delta.nil? ? @owned_copies : deck_card.owned_copies.to_i + @delta
        max_owned = [ deck_card.quantity, availability.available ].min
        unless owned_copies.is_a?(Integer) && owned_copies.between?(0, max_owned)
          raise ArgumentError, "owned_copies must be between 0 and #{max_owned}"
        end

        deck_card.update!(owned_copies: owned_copies)
        deck_card
      end
    end

    private

    def availability
      Allocations::Availability.call(user: @deck.user, card: @card, excluding_deck: @deck)
    end
  end
end
