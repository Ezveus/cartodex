module Admin
  module StandardPools
    class NewView < ApplicationComponent
      def initialize(standard_pool:)
        @standard_pool = standard_pool
      end

      def view_template
        div(class: "admin-container") do
          h1 { "New Standard Pool" }
          render Admin::StandardPools::Form.new(standard_pool: @standard_pool)
        end
      end
    end
  end
end
