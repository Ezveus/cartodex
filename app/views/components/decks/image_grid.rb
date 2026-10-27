module Decks
  # A deck page's list as card images: Decks::Layout's sections, headings and counts unchanged, each
  # row drawn as one Decks::CardTile per in-deck printing — a type-view row is a card and may hold
  # several, a set-view row is already one printing.
  class ImageGrid < ApplicationComponent
    def initialize(sections:)
      @sections = sections
    end

    def view_template
      render Decks::DeckSections.new(sections: @sections, row: method(:tiles))
    end

    private

    def tiles(row)
      printings = row.printing ? [ row.printing ] : row.state.in_deck
      printings.map { |printing| Decks::CardTile.new(printing: printing, name: row.state.name) }
    end
  end
end
