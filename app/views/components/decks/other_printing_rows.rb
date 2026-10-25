module Decks
  # The printings of a card that the deck does not play and the member does not own (the :other
  # group, in catalogue order) as the sub-rows of the card's "Other printings" list. The owned ones
  # are not here: Decks::FingerprintRow renders them in the expansion itself.
  #
  # Two callers, one markup: a write's answer renders them inside the row it re-renders
  # (Decks::FingerprintRow with `others: :rendered`), and Api::DeckCardsController#other_printings
  # renders them alone for the page, which fetches them the first time the list is opened.
  class OtherPrintingRows < ApplicationComponent
    def self.printings(state) = state.printings.select { |printing| printing.group == :other }

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
