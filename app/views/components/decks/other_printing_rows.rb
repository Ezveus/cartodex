module Decks
  # The printings of a card that the deck does not play — the ones the member owns first, then the
  # rest, each in catalogue order (FingerprintStates' order) — as the sub-rows of the card's
  # "Other printings" list.
  #
  # Two callers, one markup: a write's answer renders them inside the row it re-renders
  # (Decks::FingerprintRow with `others: :rendered`), and Api::DeckCardsController#other_printings
  # renders them alone for the page, which fetches them the first time the list is opened.
  class OtherPrintingRows < ApplicationComponent
    def self.printings(state) = state.printings.reject { |printing| printing.group == :deck }

    def initialize(state:, deck:)
      @state = state
      @deck = deck
    end

    def view_template
      self.class.printings(@state).each do |printing|
        render PrintingRow.new(printing: printing, state: @state, deck: @deck)
      end
    end
  end
end
