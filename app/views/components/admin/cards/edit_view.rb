module Admin
  module Cards
    class EditView < ApplicationComponent
      def initialize(card:, attacks:, abilities:)
        @card = card
        @attacks = attacks
        @abilities = abilities
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Edit #{@card.name}" }
          render Admin::Cards::Form.new(card: @card, attacks: @attacks, abilities: @abilities,
                                        url: admin_card_path(@card), submit_label: "Update Card",
                                        cancel_path: admin_card_path(@card))
        end
      end
    end
  end
end
