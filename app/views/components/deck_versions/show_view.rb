module DeckVersions
  # A version against the one before it, in the deck compare table. The columns are versions of
  # one deck, so every link the table carries is re-pointed at a version: the compare page's own
  # `deck_path(deck)` would build a deck address out of a version id.
  class ShowView < ApplicationComponent
    def initialize(deck:, version:, previous:, comparison:, periods: {})
      @deck = deck
      @periods = periods || {}
      @version = version
      @previous = previous
      @comparison = comparison
    end

    def view_template
      div(class: "deck-version-show") do
        p(class: "deck-version-summary") do
          plain "#{@version.label}: #{@version.format_label}, #{DeckVersions::Labels.played(@periods[@version.id])}. "
          plain(@previous ? "Compared with #{@previous.label}." : "The first version: nothing to compare it with.")
        end

        render Decks::CompareView.new(
          comparison: @comparison,
          title: "#{@deck.name} — #{@version.label}",
          back_label: "Back to Versions",
          back_path: deck_versions_path(@deck),
          column_path: ->(version) { deck_version_path(@deck, version) }
        )
      end
    end
  end
end
