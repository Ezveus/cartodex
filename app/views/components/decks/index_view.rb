module Decks
  class IndexView < ApplicationComponent
    def initialize(decks:, pending_deck_imports: [])
      @decks = decks
      @pending_deck_imports = pending_deck_imports
    end

    def view_template
      div(class: "decks-container", data: { controller: "decks" }) do
        div(class: "decks-header") do
          h1 { "My Decks" }
          div(class: "decks-header-actions") do
            link_to "New Deck", helpers.new_deck_path, class: "btn btn-primary"
            link_to "Import Deck", "#", class: "btn btn-secondary", data: { action: "decks#openImport" }
          end
        end

        render Ui::DeckImport.new(pending_imports: @pending_deck_imports)

        if @decks.any?
          div(class: "decks-grid") do
            @decks.each { |deck| deck_item(deck) }
          end
        else
          p do
            plain "No decks yet. "
            link_to "Import one from the dashboard", helpers.dashboard_path
            plain "."
          end
        end
      end
    end

    private

    def deck_item(deck)
      link_to helpers.deck_path(deck), class: "deck-item" do
        h2 { deck.name }
        p(class: "deck-description") { deck.description } if deck.description.present?
        p(class: "deck-card-count") { "#{deck.deck_cards.sum(&:quantity)} cards" }
      end
    end
  end
end
