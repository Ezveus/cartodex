module Cards
  # Every printing physically interchangeable with the given card — i.e. sharing its
  # Card#fingerprint — annotated for one user, newest set first.
  #
  # Sibling of Collections::OwnedEquivalents, which filters to printings the user owns.
  # This one does not: switching a deck slot to a printing you do not own is a legitimate
  # move (you proxy it, or you buy it next week), so owned/available are annotations here
  # rather than the filter. Nothing is ever scraped — a printing the database does not hold
  # is simply not on the list.
  #
  # Given a deck, each entry also carries what that deck already holds of the printing and
  # the real/proxy split a swap onto it would produce, so the picker can warn before the
  # write rather than after. The projection is left nil when there is none to make: no deck,
  # or a deck that consumes no collection.
  class Printings < ApplicationService
    # Which of these cards have at least one other printing, as a Set of ids — what the deck page
    # needs to decide which rows get a picker at all. One grouped query for the whole page: asking
    # per row would be an N+1 the size of a decklist.
    def self.swappable_card_ids(cards)
      # `.presence`, not just a nil check: a blank fingerprint matches every other blank, which is
      # why #printings and PrintingSwapper both refuse to treat it as an equivalence.
      fingerprints = cards.filter_map { |card| card.fingerprint.presence }.uniq
      return Set.new if fingerprints.empty?

      reprinted = Card.where(fingerprint: fingerprints).group(:fingerprint).count.select { |_, n| n > 1 }
      cards.select { |card| reprinted.key?(card.fingerprint) }.map(&:id).to_set
    end

    def initialize(user:, card:, deck: nil)
      @user = user
      @card = card
      @deck = deck
    end

    def call
      availability = Allocations::Availability.for_cards(user: @user, cards: printings, excluding_deck: @deck)

      printings.map do |printing|
        counts = availability[printing.id]
        entry = {
          card_id: printing.id,
          set_name: printing.set_name,
          set_number: printing.set_number,
          rarity: printing.rarity,
          owned: counts.owned,
          available: counts.available,
          in_deck: deck_row(printing.id)&.quantity.to_i,
          current: printing.id == @card.id
        }
        entry.merge(projection(printing, counts.available))
      end
    end

    private

    # A card with no fingerprint has no known equivalent — not even a mistaken one, since a
    # blank value would match every other blank. It is the only printing of itself.
    def printings
      @printings ||= if @card.fingerprint.blank?
        [ @card ]
      else
        Card.where(fingerprint: @card.fingerprint)
            .left_joins(:card_set)
            .order(Arel.sql("card_sets.release_date IS NULL, card_sets.release_date DESC"))
            .order(:set_name, :set_number)
            .to_a
      end
    end

    # One query for every row the deck holds of any of these printings — the source row
    # included, since its quantity is what a swap moves.
    def deck_rows
      @deck_rows ||= if @deck
        @deck.deck_cards.where(card_id: printings.map(&:id)).index_by(&:card_id)
      else
        {}
      end
    end

    def deck_row(card_id) = deck_rows[card_id]

    def projection(printing, available)
      return { real_after: nil, proxies_after: nil } unless @deck&.physical?

      source = deck_row(@card.id)

      if printing.id == @card.id
        # Swapping a printing for itself is a no-op, so the current entry reports today's
        # split rather than a re-derivation that free copies could make look like a change.
        real = source&.owned_copies.to_i
        total = source&.quantity.to_i
      else
        target = deck_row(printing.id)
        total = source&.quantity.to_i + target&.quantity.to_i
        real = Allocations::Backing.greedy(
          quantity: total, current_owned: target&.owned_copies.to_i, available: available
        )
      end

      { real_after: real, proxies_after: total - real }
    end
  end
end
