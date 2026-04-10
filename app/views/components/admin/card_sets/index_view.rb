module Admin
  module CardSets
    class IndexView < ApplicationComponent
      def initialize(card_sets:)
        @card_sets = card_sets
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
                td do
                  link_to "Edit", helpers.edit_admin_card_set_path(card_set), class: "btn btn-secondary btn-sm"
                  plain " "
                  link_to "Delete", helpers.admin_card_set_path(card_set),
                    data: { turbo_method: :delete, turbo_confirm: "Delete #{card_set.name}?" },
                    class: "btn-danger"
                end
              end
            end
          end
        end
      end

      private

      def import_section
        div(data: { controller: "set-import" }) do
          form_with(url: helpers.import_admin_card_sets_path, method: :post, class: "admin-search",
            data: { action: "submit->set-import#import" }) do
            helpers.text_field_tag :url, nil,
              placeholder: "https://limitlesstcg.com/cards/POR",
              class: "form-input admin-search-input",
              data: { set_import_target: "url" }
            helpers.submit_tag "Import from Limitless",
              class: "btn btn-primary btn-sm",
              data: { set_import_target: "submit" }
          end

          div(class: "importing-section", style: "display: none;", data: { controller: "importing-list" }) do
            h3 { "Importing..." }
            ul(data: { set_import_target: "list", importing_list_target: "list" }, class: "importing-list")
          end
        end
      end
    end
  end
end
