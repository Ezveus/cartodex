module Ui
  class DeckImport < ApplicationComponent
    def initialize(pending_imports: [])
      @pending_imports = pending_imports
    end

    def view_template
      importing_section
      import_modal
    end

    private

    def importing_section
      visible = @pending_imports.any?
      div(class: "importing-section", style: (visible ? nil : "display: none;"), data: { controller: "importing-list" }) do
        h3 { "Importing\u2026" }
        ul(id: "importing-decks", data: { decks_target: "importingList", importing_list_target: "list" }, class: "importing-list") do
          @pending_imports.each do |imp|
            li(id: "importing-#{imp.id}", class: "importing-item") do
              span(class: "importing-spinner")
              plain " #{imp.label}"
            end
          end
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
  end
end
