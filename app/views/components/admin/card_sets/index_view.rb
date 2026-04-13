module Admin
  module CardSets
    class IndexView < ApplicationComponent
      def initialize(card_sets:, pending_set_imports: [])
        @card_sets = card_sets
        @pending_set_imports = pending_set_imports
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Card Sets") do
            link_to "New Set", helpers.new_admin_card_set_path, class: "btn btn-primary"
          end

          import_section

          render Ui::AdminTable.new(columns: [ "Code", "Name", "Block", "Release Date", "Cards", "Actions" ]) do
            @card_sets.each do |card_set|
              tr do
                td { card_set.code }
                td { link_to card_set.name, helpers.admin_card_set_path(card_set) }
                td { card_set.block_name }
                td { card_set.release_date&.strftime("%Y-%m-%d") }
                td { card_set.cards.size.to_s }
                td { render Ui::AdminActions.new(edit_path: helpers.edit_admin_card_set_path(card_set), delete_path: helpers.admin_card_set_path(card_set), confirm_message: "Delete #{card_set.name}?") }
              end
            end
          end
        end
      end

      private

      def import_section
        div(data: { controller: "set-import" }) do
          form_with(url: helpers.import_admin_card_sets_path, method: :post, class: "admin-search",
            data: { action: "submit->set-import#import" }) do |f|
            input(
              type: "text", name: "url",
              placeholder: "https://limitlesstcg.com/cards/POR",
              class: "form-input admin-search-input",
              data: { set_import_target: "url" }
            )
            input(
              type: "submit", value: "Import from Limitless",
              class: "btn btn-primary btn-sm",
              data: { set_import_target: "submit" }
            )
          end

          div(class: "importing-section", style: (@pending_set_imports.any? ? nil : "display: none;"), data: { controller: "importing-list" }) do
            h3 { "Importing..." }
            ul(data: { set_import_target: "list", importing_list_target: "list" }, class: "importing-list") do
              @pending_set_imports.each do |imp|
                li(id: "importing-set-#{imp.id}", class: "importing-item") do
                  span(class: "importing-spinner")
                  plain " #{imp.label}"
                end
              end
            end
          end
        end
      end
    end
  end
end
