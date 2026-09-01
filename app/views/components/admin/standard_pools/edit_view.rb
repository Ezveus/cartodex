module Admin
  module StandardPools
    class EditView < ApplicationComponent
      def initialize(standard_pool:)
        @standard_pool = standard_pool
      end

      def view_template
        div(class: "admin-container") do
          h1 { heading }
          render Admin::StandardPools::Form.new(standard_pool: @standard_pool)
        end
      end

      private

      # StandardPool#name reads both bounds, and this view also renders the
      # re-submitted record after a failed update — where a bound cleared by a
      # hand-crafted request would be nil.
      def heading
        return "Edit Standard Pool" unless @standard_pool.first_card_set && @standard_pool.last_card_set

        "Edit #{@standard_pool.name}"
      end
    end
  end
end
