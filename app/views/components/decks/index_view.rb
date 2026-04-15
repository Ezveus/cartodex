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

        div(class: "decks-grid", id: "decks-grid") do
          if @decks.any?
            @decks.each { |deck| render Decks::DeckCard.new(deck: deck) }
          else
            p(id: "decks-empty") do
              plain "No decks yet. "
              link_to "Import one from the dashboard", helpers.dashboard_path
              plain "."
            end
          end
        end
      end
    end
  end
end
