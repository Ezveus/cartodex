module Decks
  # Moves a deck slot from one printing of a card to another — same card, different set and
  # number. Two things make this an allocation write rather than a `card_id` update:
  #
  # - the target printing may already be in the deck (running a mixed set is normal), and
  #   (deck_id, card_id) is unique, so the two rows must merge rather than collide;
  # - owned_copies is per exact printing, so the backing cannot be carried across — writing
  #   it as-is would break `Σ owned_copies ≤ owned` for the target the instant it lands. It
  #   is re-derived against the target's availability, which may legitimately turn real
  #   copies into proxies.
  #
  # The deck's size never changes: a swap moves copies between printings, it does not add or
  # remove any.
  class PrintingSwapper < ApplicationService
    # Greedy backing, the rule Decks::CardAdder applies on an add: claim as many real copies
    # as the collection leaves free to this deck, capped at the row's total, and never below
    # what the deck already backs of that printing. `available` must already exclude this
    # deck's own commitments, or the deck would be made to compete with itself.
    def self.projected_owned_copies(quantity:, current_owned:, available:)
      [ quantity, [ current_owned, available ].max ].min
    end

    def initialize(deck:, card:, target_card:)
      @deck = deck
      @card = card
      @target_card = target_card
    end

    def call
      raise ArgumentError, "the deck already uses this printing" if @card.id == @target_card.id
      unless equivalent_printing?
        raise ArgumentError, "#{@target_card.name} #{@target_card.set_name} #{@target_card.set_number} " \
                             "is not another printing of #{@card.name}"
      end

      serialized_transaction do
        source = @deck.deck_cards.find_by!(card: @card)
        target = @deck.deck_cards.find_by(card: @target_card)
        quantity = source.quantity + target&.quantity.to_i

        source.destroy!
        target ||= @deck.deck_cards.build(card: @target_card)
        target.quantity = quantity
        target.owned_copies = backing_for(quantity, target)
        target.save!
        target
      end
    end

    private

    # Card#fingerprint hashes name, HP, type, attacks and abilities while deliberately
    # excluding set and number, so all printings of a card share one value. A blank one
    # matches every other blank, which is why it is not an equivalence at all here.
    def equivalent_printing?
      @card.fingerprint.present? && @card.fingerprint == @target_card.fingerprint
    end

    def backing_for(quantity, target)
      return 0 unless @deck.physical?

      available = Allocations::Availability.call(
        user: @deck.user, card: @target_card, excluding_deck: @deck
      ).available

      self.class.projected_owned_copies(
        quantity: quantity, current_owned: target.owned_copies.to_i, available: available
      )
    end
  end
end
