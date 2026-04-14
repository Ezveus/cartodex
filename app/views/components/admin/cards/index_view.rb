module Admin
  module Cards
    class IndexView < ApplicationComponent
      def initialize(cards:, query:)
        @cards = cards
        @query = query
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Cards" }

          form_with(url: helpers.admin_cards_path, method: :get, class: "admin-search") do |f|
            input(type: "text", name: "q", value: @query, placeholder: "Search by name...", class: "form-input admin-search-input")
            input(type: "submit", value: "Search", class: "btn btn-secondary btn-sm")
          end

          render Ui::DataTable.new(columns: %w[Name Set Type HP Rarity Actions]) do |t|
            @cards.each do |card|
              t.row do
                t.cell { link_to card.name, helpers.admin_card_path(card) }
                t.cell { "#{card.set_name} #{card.set_number}" }
                t.cell { card.card_type }
                t.cell { card.hp.to_s }
                t.cell { card.rarity }
                t.cell { link_to "Edit", helpers.edit_admin_card_path(card), class: "btn btn-secondary btn-sm" }
              end
            end
          end
        end
      end
    end
  end
end
