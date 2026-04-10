module Ui
  class PageHeader < ApplicationComponent
    def initialize(title:)
      @title = title
    end

    def view_template(&block)
      div(class: "admin-header") do
        h1 { @title }
        yield if block
      end
    end
  end
end
