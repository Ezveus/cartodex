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

          render Ui::DataTable.new(columns: [ "Code", "Name", "Block", "Release Date", "Cards", "Actions" ]) do |t|
            @card_sets.each do |card_set|
              t.row do
                t.cell { card_set.code }
                t.cell { link_to card_set.name, helpers.admin_card_set_path(card_set) }
                t.cell { card_set.block_name }
                t.cell { card_set.release_date&.strftime("%Y-%m-%d") }
                t.cell { card_set.cards.size.to_s }
                t.cell { render Ui::AdminActions.new(edit_path: helpers.edit_admin_card_set_path(card_set), delete_path: helpers.admin_card_set_path(card_set), confirm_message: "Delete #{card_set.name}?") }
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

          render Ui::ImportingList.new(
            pending_imports: @pending_set_imports,
            item_id_prefix: "importing-set",
            extra_data: { set_import_target: "list" }
          )
        end
      end
    end
  end
end
