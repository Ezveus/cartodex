module Decks
  # Sets the total quantity of a card in a deck. quantity <= 0 removes the card.
  #
  # Either `quantity:` (an absolute count — the MCP tool and the API) or `delta:` (a step — the
  # deck page's steppers), never both. A step is resolved against the row read inside the
  # transaction, a missing row counting as 0: a page sending an absolute value from a stale tab
  # would turn its "−" into an increase whenever another tab had lowered the count meanwhile.
  #
  # Only an increase claims real copies, under the backing rule (Allocations::Backing.greedy) that
  # Decks::CardAdder applies, so a quantity + leaves the real + something it can still do. A
  # decrease never claims: the copies it drops are proxies first, and reals only once no proxy is
  # left. Re-deriving greedily on every write would let a − silently turn a proxy into a real.
  class DeckCardQuantitySetter < ApplicationService
    def initialize(deck:, card:, quantity: nil, delta: nil)
      @deck = deck
      @card = card
      @quantity = quantity
      @delta = delta
    end

    def call
      validate_arguments!

      # The availability read and the write share one write lock, or two concurrent increases
      # would each see the same free copy and both claim it.
      serialized_transaction do
        deck_card = @deck.deck_cards.find_by(card: @card)
        quantity = @delta.nil? ? @quantity : deck_card&.quantity.to_i + @delta

        if quantity <= 0
          deck_card&.destroy!
          next nil
        end

        deck_card ||= @deck.deck_cards.build(card: @card)
        increase = quantity > deck_card.quantity.to_i
        deck_card.quantity = quantity
        deck_card.owned_copies = if @deck.physical? && increase
          greedy_owned_copies(deck_card)
        else
          [ deck_card.owned_copies.to_i, quantity ].min
        end
        deck_card.save!
        deck_card
      end
    end

    private

    def validate_arguments!
      raise ArgumentError, "give exactly one of quantity and delta" if @quantity.nil? == @delta.nil?
      raise ArgumentError, "quantity must be an integer" unless @quantity.nil? || @quantity.is_a?(Integer)
      raise ArgumentError, "delta must be an integer" unless @delta.nil? || @delta.is_a?(Integer)
    end

    def greedy_owned_copies(deck_card)
      available = Allocations::Availability.call(user: @deck.user, card: @card, excluding_deck: @deck).available

      Allocations::Backing.greedy(
        quantity: deck_card.quantity, current_owned: deck_card.owned_copies.to_i, available: available
      )
    end
  end
end
