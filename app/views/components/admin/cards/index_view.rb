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

          form_with(url: helpers.admin_cards_path, method: :get, class: "admin-search") do
            helpers.text_field_tag :q, @query, placeholder: "Search by name...", class: "form-input admin-search-input"
            helpers.submit_tag "Search", class: "btn btn-secondary btn-sm"
          end

          render Ui::AdminTable.new(columns: %w[Name Set Type HP Rarity Actions]) do
            @cards.each do |card|
              tr do
                td { link_to card.name, helpers.admin_card_path(card) }
                td { "#{card.set_name} #{card.set_number}" }
                td { card.card_type }
                td { card.hp.to_s }
                td { card.rarity }
                td { link_to "Edit", helpers.edit_admin_card_path(card), class: "btn btn-secondary btn-sm" }
              end
            end
          end
        end
      end
    end
  end
end
