module Decks
  # Renders the classification of a deck (format, support, proxies) as a row
  # of badges. Shared between the deck list and the deck show header.
  class ClassificationBadges < ApplicationComponent
    def initialize(deck:, over_allocated: false)
      @deck = deck
      @over_allocated = over_allocated
    end

    def view_template
      div(class: "deck-badges") do
        span(class: "badge badge-format") { @deck.format_label }
        archetype_badge if @deck.archetype
        span(class: "badge") { "Physical" } if @deck.physical?
        span(class: "badge") { "TCG Live" } if @deck.tcg_live?
        span(class: "badge badge-warning") { "Proxies" } if @deck.has_proxies?
        span(class: "badge badge-warning") { "To review" } if @over_allocated
      end
    end

    private

    # The archetype badge is tinted by its lead Pokémon's energy type, with a
    # colour pip. Falls back to the neutral archetype style when the type is
    # unknown.
    def archetype_badge
      slug = @deck.archetype.primary_energy_type&.downcase

      if slug
        span(class: "badge badge-energy badge-#{slug}") do
          span(class: "badge-pip")
          plain @deck.archetype.name
        end
      else
        span(class: "badge badge-archetype") { @deck.archetype.name }
      end
    end
  end
end
