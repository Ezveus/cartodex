module Decks
  # "+ add to my collection and use it here": records one more physical copy of a printing and
  # backs one of the deck's proxies with it, in one transaction.
  #
  # It refuses whenever the click would mean something else. With no proxy there is nothing to
  # back. With a free copy already in the collection the real + is the move, and allowing this
  # would let one click claim several reals — the free one and the new one. And on an
  # over-allocated printing one more copy only brings the collection back towards what other decks
  # already back, so it cannot become this deck's: the collection write is rolled back with the
  # refusal rather than leaving a copy nobody asked for.
  class CollectionCopyAdder < ApplicationService
    def initialize(deck:, card:)
      @deck = deck
      @card = card
    end

    def call
      raise OwnedCopiesSetter::NotPhysicalError, "deck is not physical" unless @deck.physical?

      serialized_transaction do
        deck_card = @deck.deck_cards.find_by!(card: @card)
        raise ArgumentError, "no proxy left to back" if deck_card.owned_copies >= deck_card.quantity
        if available > deck_card.owned_copies
          raise ArgumentError, "a free copy is already available — use the real copy +"
        end

        Collections::CardAdder.call(user: @deck.user, card: @card, quantity: 1)

        backed = Allocations::Backing.greedy(
          quantity: deck_card.quantity, current_owned: deck_card.owned_copies, available: available
        )
        unless backed == deck_card.owned_copies + 1
          raise ArgumentError, "this printing is over-allocated: the new copy would not be free for this deck"
        end

        deck_card.update!(owned_copies: backed)
        deck_card
      end
    end

    private

    # Read fresh on every call: the second read has to see the copy just added.
    def available
      Allocations::Availability.call(user: @deck.user, card: @card, excluding_deck: @deck).available
    end
  end
end
