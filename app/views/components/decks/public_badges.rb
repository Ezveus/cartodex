module Decks
  # The badges a visitor may see: the format and the archetype, and nothing else.
  #
  # Deliberately not ClassificationBadges with a flag. "Physical" and "TCG Live" say how the
  # owner plays the deck and are of no use to a reader; "Proxies" and "To review" report what
  # the owner does and does not own, which is collection data reached through a deck.
  class PublicBadges < ApplicationComponent
    def initialize(deck:)
      @deck = deck
    end

    def view_template
      div(class: "deck-badges") do
        span(class: "badge badge-format") { @deck.format_label }
        render Ui::ArchetypeBadge.new(archetype: @deck.archetype) if @deck.archetype
      end
    end
  end
end
