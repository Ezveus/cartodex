module Ui
  class Card < ApplicationComponent
    def initialize(title: nil)
      @title = title
    end

    def view_template(&block)
      div(class: "auth-container") do
        h1 { @title } if @title
        yield
      end
    end
  end
end
