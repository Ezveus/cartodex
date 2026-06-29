module Decks
  class DeckCard < ApplicationComponent
    def initialize(deck:, with_actions: true)
      @deck = deck
      @with_actions = with_actions
    end

    def view_template
      div(class: "deck-item", id: "deck-#{@deck.id}") do
        input(
          type: "checkbox",
          class: "deck-compare-checkbox",
          value: @deck.id,
          aria_label: "Select #{@deck.name} to compare",
          data: { deck_compare_target: "checkbox", action: "deck-compare#toggle" }
        )
        a(href: Rails.application.routes.url_helpers.deck_path(@deck), class: "deck-item-link") do
          h2 { @deck.name }
          render Decks::ClassificationBadges.new(deck: @deck)
          p(class: "deck-description") { @deck.description } if @deck.description.present?
          p(class: "deck-card-count") { "#{@deck.deck_cards.sum(&:quantity)} cards" }
        end
        if @with_actions
          div(class: "deck-item-actions") do
            render Decks::ActionsDropdown.new(deck: @deck)
          end
        end
      end
    end
  end
end
