module Ui
  class DataTable < ApplicationComponent
    def initialize(columns:)
      @columns = columns
    end

    def view_template
      div(class: "data-table") do
        div(class: "data-table-header") do
          @columns.each { |col| div(class: "data-table-cell") { col } }
        end
        div(class: "data-table-body") { yield self }
      end
    end

    # `class:` is added to `data-table-row`, never replaces it; every other attribute passes through.
    def row(**attrs, &block)
      @col_index = 0
      extra = attrs.delete(:class)
      div(class: [ "data-table-row", extra ].compact.join(" "), **attrs, &block)
    end

    def cell(**attrs, &block)
      label = @columns[@col_index]
      @col_index = (@col_index || 0) + 1
      div(class: "data-table-cell", data: { label: label }, **attrs, &block)
    end
  end
end
