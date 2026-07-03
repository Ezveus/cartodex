module Decks
  # Sets the real (owned-backed) copy count of an existing card in a physical
  # deck. The new value is bounded by the deck_card's total and by availability,
  # so an edit can never create over-allocation (only a collection decrease can).
  class OwnedCopiesSetter < ApplicationService
    class NotPhysicalError < StandardError; end

    def initialize(deck:, card:, owned_copies:)
      @deck = deck
      @card = card
      @owned_copies = owned_copies
    end

    def call
      raise NotPhysicalError, "deck is not physical" unless @deck.physical?

      serialized_transaction do
        deck_card = @deck.deck_cards.find_by!(card: @card)
        max_owned = [ deck_card.quantity, availability.available ].min
        unless @owned_copies.is_a?(Integer) && @owned_copies.between?(0, max_owned)
          raise ArgumentError, "owned_copies must be between 0 and #{max_owned}"
        end

        deck_card.update!(owned_copies: @owned_copies)
        deck_card
      end
    end

    private

    def availability
      Allocations::Availability.call(user: @deck.user, card: @card, excluding_deck: @deck)
    end
  end
end
