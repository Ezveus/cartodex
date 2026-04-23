module Admin
  module Decks
    class ShowView < ApplicationComponent
      def initialize(deck:)
        @deck = deck
      end

      def view_template
        div(class: "admin-container") do
          div(class: "admin-header") do
            div do
              h1 { @deck.name }
              p do
                plain "Owner: "
                strong { @deck.user.email }
                plain " — Cards: "
                strong { @deck.deck_cards.sum(&:quantity).to_s }
              end
            end
            link_to "Back", admin_decks_path, class: "btn btn-secondary"
          end

          card_groups = @deck.deck_cards.group_by { |dc| dc.card.card_type }
          %w[Pokémon Trainer Energy].each do |type|
            group = card_groups[type]
            next unless group.present?

            h2 { "#{type} (#{group.sum(&:quantity)})" }
            render Ui::DataTable.new(columns: %w[Qty Name Set]) do |t|
              group.sort_by { |dc| dc.card.name }.each do |dc|
                t.row do
                  t.cell { dc.quantity.to_s }
                  t.cell { link_to dc.card.name, admin_card_path(dc.card) }
                  t.cell { "#{dc.card.set_name} #{dc.card.set_number}" }
                end
              end
            end
          end
        end
      end
    end
  end
end
