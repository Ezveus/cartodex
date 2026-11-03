module Admin
  module Cards
    class NewView < ApplicationComponent
      def initialize(card:, card_set:, attacks:, abilities:)
        @card = card
        @card_set = card_set
        @attacks = attacks
        @abilities = abilities
      end

      def view_template
        div(class: "admin-container") do
          h1 { "New card in #{@card_set.name}" }
          render Admin::Cards::Form.new(card: @card, attacks: @attacks, abilities: @abilities,
                                        url: admin_card_set_cards_path(@card_set), submit_label: "Create Card",
                                        cancel_path: admin_card_set_path(@card_set))
        end
      end
    end
  end
end
