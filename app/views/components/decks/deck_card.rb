module Decks
  class DeckCard < ApplicationComponent
    def initialize(deck:)
      @deck = deck
    end

    def view_template
      a(href: Rails.application.routes.url_helpers.deck_path(@deck), class: "deck-item", id: "deck-#{@deck.id}") do
        h2 { @deck.name }
        p(class: "deck-description") { @deck.description } if @deck.description.present?
        p(class: "deck-card-count") { "#{@deck.deck_cards.sum(&:quantity)} cards" }
      end
    end
  end
end
