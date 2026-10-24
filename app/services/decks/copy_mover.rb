module Decks
  # Moves one copy of a card from one of its printings to another inside a deck: the deck page's
  # ⇄. Decks::PrintingSwapper moves a whole row; this moves a single copy, so splitting 3× MEG 114
  # into 1× PAL 172 + 2× MEG 114 is one action rather than four.
  #
  # Both halves follow the setter's rule. The source loses one copy the way a quantity − does — a
  # proxy first — and the target gains one the way a quantity + does, greedily backed by what the
  # collection leaves free. The deck's size never changes.
  class CopyMover < ApplicationService
    # `from_deck_card` is nil when the move emptied the source row, which it then destroyed.
    Result = Struct.new(:from_deck_card, :to_deck_card, keyword_init: true)

    def initialize(deck:, from_card:, to_card:)
      @deck = deck
      @from_card = from_card
      @to_card = to_card
    end

    def call
      raise ArgumentError, "a copy cannot move onto the same printing" if @from_card.id == @to_card.id
      unless equivalent_printing?
        raise ArgumentError, "#{@to_card.name} #{@to_card.set_name} #{@to_card.set_number} " \
                             "is not another printing of #{@from_card.name}"
      end

      serialized_transaction do
        source = @deck.deck_cards.find_by(card: @from_card)
        unless source
          raise ArgumentError, "#{@from_card.name} #{@from_card.set_name} #{@from_card.set_number} is not in the deck"
        end

        from_deck_card = take_one(source)
        Result.new(from_deck_card: from_deck_card, to_deck_card: land_one)
      end
    end

    private

    # The PrintingSwapper rule: a blank fingerprint matches every other blank, so it is no
    # evidence that two cards are one.
    def equivalent_printing?
      @from_card.fingerprint.present? && @from_card.fingerprint == @to_card.fingerprint
    end

    def take_one(source)
      quantity = source.quantity - 1
      if quantity.zero?
        source.destroy!
        return nil
      end

      source.update!(quantity: quantity, owned_copies: [ source.owned_copies.to_i, quantity ].min)
      source
    end

    # Availability is read after the source write. A real freed on the source belongs to another
    # printing and cannot change the target's pool, but reading after costs nothing and keeps the
    # answer true if that ever stops holding.
    def land_one
      target = @deck.deck_cards.find_or_initialize_by(card: @to_card)
      target.quantity = target.quantity.to_i + 1
      target.owned_copies = if @deck.physical?
        available = Allocations::Availability.call(user: @deck.user, card: @to_card, excluding_deck: @deck).available
        Allocations::Backing.greedy(
          quantity: target.quantity, current_owned: target.owned_copies.to_i, available: available
        )
      else
        0
      end
      target.save!
      target
    end
  end
end
