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
          render Ui::DataTable.new(columns: %w[# Name Type HP Rarity]) do |t|
            @cards.each do |card|
              t.row do
                t.cell { card.set_number }
                t.cell { link_to card.name, helpers.admin_card_path(card) }
                t.cell { card.card_type }
                t.cell { card.hp.to_s }
                t.cell { card.rarity }
              end
            end
          end
        end
      end
    end
  end
end
