module Decks
  # Moves real (owned-backed) copies of a card from one physical deck to another
  # without changing either deck's size: the freed slot in the source becomes a
  # proxy, a proxy slot in the target becomes real. Global committed is unchanged,
  # so the invariant is preserved by construction.
  class OwnedCopiesReallocator < ApplicationService
    class NotPhysicalError < StandardError; end

    def initialize(from_deck:, to_deck:, card:, quantity:)
      @from_deck = from_deck
      @to_deck = to_deck
      @card = card
      @quantity = quantity
    end

    def call
      raise NotPhysicalError, "both decks must be physical" unless @from_deck.physical? && @to_deck.physical?
      raise ArgumentError, "quantity must be a positive integer" unless @quantity.is_a?(Integer) && @quantity.positive?
      raise ArgumentError, "from_deck and to_deck must differ" if @from_deck.id == @to_deck.id

      serialized_transaction do
        from = @from_deck.deck_cards.find_by!(card: @card)
        to = @to_deck.deck_cards.find_by!(card: @card)

        raise ArgumentError, "source deck has only #{from.owned_copies} real copies" if from.owned_copies < @quantity
        raise ArgumentError, "target deck has no proxy slots to convert" if to.owned_copies + @quantity > to.quantity

        from.update!(owned_copies: from.owned_copies - @quantity)
        to.update!(owned_copies: to.owned_copies + @quantity)
        [ from, to ]
      end
    end
  end
end
