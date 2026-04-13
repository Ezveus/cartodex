module Ui
  class Modal < ApplicationComponent
    def initialize(id:, title:, **data_attrs)
      @id = id
      @title = title
      @data_attrs = data_attrs
    end

    def view_template(&block)
      div(id: @id, class: "modal", data: @data_attrs.presence) do
        div(class: "modal-content") do
          h2 { @title }
          yield if block
        end
      end
    end
  end
end
