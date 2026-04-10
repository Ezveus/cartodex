module Admin
  module CardSets
    class ShowView < ApplicationComponent
      def initialize(card_set:, cards:)
        @card_set = card_set
        @cards = cards
      end

      def view_template
        div(class: "admin-container") do
          div(class: "admin-header") do
            div do
              h1 { "#{@card_set.name} (#{@card_set.code})" }
              p do
                plain "Block: "
                strong { @card_set.block_name }
                plain " — Released: "
                strong { @card_set.release_date&.strftime("%Y-%m-%d") || "N/A" }
              end
            end
            link_to "Edit", helpers.edit_admin_card_set_path(@card_set), class: "btn btn-secondary"
          end

          h2 { "Cards (#{@cards.size})" }
          render Ui::AdminTable.new(columns: %w[# Name Type HP Rarity]) do
            @cards.each do |card|
              tr do
                td { card.set_number }
                td { link_to card.name, helpers.admin_card_path(card) }
                td { card.card_type }
                td { card.hp.to_s }
                td { card.rarity }
              end
            end
          end
        end
      end
    end
  end
end
