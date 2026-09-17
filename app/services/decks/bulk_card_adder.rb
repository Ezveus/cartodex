module Decks
  # Adds many printings to one deck in a single transaction, and returns the receipt the Import row
  # and the MCP response are both built from.
  #
  # `resolved` is what Cards::ReferenceResolver hands back: [ { card:, quantity: } ], one row per
  # distinct printing, already summed.
  #
  # **The availability read is batched, and that it may be is a property of the allocation model
  # rather than an optimisation worth risking.** Decks::CardAdder recomputes Allocations::Availability
  # per card because the greedy backing rule needs the pool the collection leaves free to this deck.
  # But availability is keyed on `card_id`, and after the resolver's aggregation each `card_id`
  # appears exactly once — `collections` and `deck_cards` are both per-card-id, so adding printing A
  # never moves printing B's pool, even when the two are printings of the same card. That
  # equivalence lives in `fingerprint`, which allocation does not read. So one
  # Availability.for_cards for the whole batch answers every row: 3 statements for a 60-card list
  # instead of 180.
  #
  # The write itself still goes through Decks::CardAdder, which now takes the precomputed value.
  # Allocations::Backing.greedy therefore stays the only place the backing rule is written — a
  # second copy here could come to disagree with the one Cards::Printings projects for the picker,
  # and the user would be warned about the wrong thing.
  class BulkCardAdder < ApplicationService
    def initialize(deck:, resolved:)
      @deck = deck
      @resolved = resolved
    end

    def call
      serialized_transaction do
        cards = @resolved.map { |row| row[:card] }
        before = rows_before(cards)
        availability = availability_for(cards)

        @resolved.map do |row|
          card = row[:card]
          quantity_before, owned_before = before.fetch(card.id, [ 0, 0 ])
          deck_card = CardAdder.call(
            deck: @deck, card: card, quantity: row[:quantity], available: availability[card.id]&.available
          )
          entry(card, row[:quantity], quantity_before, owned_before, deck_card)
        end
      end
    end

    private

    # Read before any write, in one query: CardAdder returns the row as it is *after* the add, and
    # the receipt has to say where it came from.
    def rows_before(cards)
      @deck.deck_cards
           .where(card_id: cards.map(&:id))
           .pluck(:card_id, :quantity, :owned_copies)
           .to_h { |card_id, quantity, owned| [ card_id, [ quantity.to_i, owned.to_i ] ] }
    end

    # A non-physical deck consumes no collection, so there is nothing to read and CardAdder never
    # asks: its rows stay at owned_copies 0 by construction.
    def availability_for(cards)
      return {} unless @deck.physical?

      Allocations::Availability.for_cards(user: @deck.user, cards: cards, excluding_deck: @deck)
    end

    # String keys, for the reason Collections::BulkCardAdder#entry gives.
    def entry(card, quantity, quantity_before, owned_before, deck_card)
      {
        "card_id" => card.id, "set_name" => card.set_name, "set_number" => card.set_number,
        "name" => card.name, "quantity" => quantity,
        "before" => quantity_before, "after" => deck_card.quantity.to_i,
        "owned_before" => owned_before, "owned_after" => deck_card.owned_copies.to_i
      }
    end
  end
end
