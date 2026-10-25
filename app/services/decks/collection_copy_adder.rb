module Decks
  # "+ add to my collection and use it here": records one more physical copy of a printing and
  # backs the deck's proxies greedily with what the collection then leaves free, in one
  # transaction.
  #
  # A free copy already in the collection does not stop it: the owner chose one click that may back
  # several proxies — the free copies and the new one — over sending the member to the real + first.
  # It refuses only when the click would mean something else. With no proxy there is nothing to
  # back. And on an over-allocated printing one more copy only brings the collection back towards
  # what other decks already back, so it cannot become this deck's: when the new copy makes nothing
  # more real here, the collection write is rolled back with the refusal rather than leaving a copy
  # nobody asked for.
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

        Collections::CardAdder.call(user: @deck.user, card: @card, quantity: 1)

        backed = Allocations::Backing.greedy(
          quantity: deck_card.quantity, current_owned: deck_card.owned_copies, available: available
        )
        # Not over-allocated, the copies free for this deck were at least the ones it backs, so with a
        # proxy left the new copy makes at least one more real; over-allocated, it makes none.
        unless backed > deck_card.owned_copies
          raise ArgumentError, "this printing is over-allocated: the new copy would not be free for this deck"
        end

        deck_card.update!(owned_copies: backed)
        deck_card
      end
    end

    private

    # Read after the collection write, so it counts the copy just added.
    def available
      Allocations::Availability.call(user: @deck.user, card: @card, excluding_deck: @deck).available
    end
  end
end
