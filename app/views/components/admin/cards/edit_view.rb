module Admin
  module Cards
    class EditView < ApplicationComponent
      def initialize(card:)
        @card = card
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Edit #{@card.name}" }
          render Admin::Cards::Form.new(card: @card)
        end
      end
    end
  end
end
