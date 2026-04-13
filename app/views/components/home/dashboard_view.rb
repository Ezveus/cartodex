module Home
  class DashboardView < ApplicationComponent
    def initialize(current_user:, pending_deck_imports: [])
      @current_user = current_user
      @pending_deck_imports = pending_deck_imports
    end

    def view_template
      div(class: "dashboard-container", data: { controller: "decks" }) do
        h1 { "Welcome, #{@current_user.email}" }

        div(class: "dashboard-grid") do
          collection_card
          decks_card
        end

        render Ui::DeckImport.new(pending_imports: @pending_deck_imports)
        scanner_modal
      end
    end

    private

    def collection_card
      div(class: "dashboard-card", data: { controller: "collection" }) do
        h2 { "My Collection" }
        div(class: "card-count") do
          span(data: { collection_target: "count" }) { "0" }
          plain " cards"
        end
        div(class: "card-actions") do
          link_to "View Collection", "#", class: "btn btn-primary", data: { action: "collection#view" }
          link_to "Scan Card", "#", class: "btn btn-secondary", data: { action: "collection#openScanner" }
        end
      end
    end

    def decks_card
      div(class: "dashboard-card") do
        h2 { "My Decks" }
        div(class: "deck-count") do
          span(id: "deck-count", data: { decks_target: "count" }) { "0" }
          plain " decks"
        end
        div(class: "deck-actions") do
          link_to "View Decks", helpers.decks_path, class: "btn btn-primary"
          link_to "Create Deck", helpers.new_deck_path, class: "btn btn-secondary"
          link_to "Import Deck", "#", class: "btn btn-secondary", data: { action: "decks#openImport" }
        end
      end
    end

    def scanner_modal
      render Ui::Modal.new(id: "scanner-modal", title: "Scan Card", collection_target: "scannerModal") do
        video(id: "scanner-video", data: { collection_target: "video" })
        button(class: "btn btn-secondary", data: { action: "collection#closeScanner" }) { "Close" }
      end
    end
  end
end
