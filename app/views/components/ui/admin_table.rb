module Ui
  class AdminTable < ApplicationComponent
    def initialize(columns:)
      @columns = columns
    end

    def view_template(&block)
      table(class: "admin-table") do
        thead do
          tr do
            @columns.each { |col| th { col } }
          end
        end
        tbody(&block)
      end
    end
  end
end
