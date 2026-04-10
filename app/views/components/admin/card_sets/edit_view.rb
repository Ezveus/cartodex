module Admin
  module CardSets
    class EditView < ApplicationComponent
      def initialize(card_set:)
        @card_set = card_set
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Edit #{@card_set.name}" }
          render Admin::CardSets::Form.new(card_set: @card_set)
        end
      end
    end
  end
end
