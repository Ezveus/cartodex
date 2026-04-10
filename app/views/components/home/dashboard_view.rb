module Home
  class DashboardView < ApplicationComponent
    def initialize(current_user:)
      @current_user = current_user
    end

    def view_template
      div(class: "dashboard-container", data: { controller: "decks" }) do
        h1 { "Welcome, #{@current_user.email}" }

        div(class: "dashboard-grid") do
          collection_card
          decks_card
        end

        import_modal
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
        div(class: "importing-section", style: "display: none;", data: { controller: "importing-list" }) do
          h3 { "Importing\u2026" }
          ul(id: "importing-decks", data: { decks_target: "importingList", importing_list_target: "list" }, class: "importing-list")
        end
      end
    end

    def import_modal
      div(id: "import-modal", class: "modal", data: { decks_target: "importModal" }) do
        div(class: "modal-content") do
          h2 { "Import Deck" }
          div(class: "form-group") do
            label(class: "form-label", for: "import-deck-name") { "Deck name" }
            input(type: "text", id: "import-deck-name", class: "form-input", data: { decks_target: "importName" }, placeholder: "My Deck")
          end
          div(class: "form-group") do
            label(class: "form-label", for: "import-decklist") { "Decklist" }
            textarea(id: "import-decklist", class: "form-input", data: { decks_target: "importDecklist" }, rows: "10", placeholder: "4 Comfey LOR 79\n2 Giratina VSTAR LOR 131\n...")
          end
          div(class: "form-actions import-actions") do
            button(class: "btn btn-primary", data: { action: "decks#submitImport", decks_target: "importSubmit" }) { "Import" }
            button(class: "btn btn-secondary", data: { action: "decks#closeImport" }) { "Cancel" }
          end
        end
      end
    end

    def scanner_modal
      div(id: "scanner-modal", class: "modal", data: { collection_target: "scannerModal" }) do
        div(class: "modal-content") do
          h2 { "Scan Card" }
          video(id: "scanner-video", data: { collection_target: "video" })
          button(class: "btn btn-secondary", data: { action: "collection#closeScanner" }) { "Close" }
        end
      end
    end
  end
end
