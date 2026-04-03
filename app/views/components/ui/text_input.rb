module Ui
  class TextInput < ApplicationComponent
    def initialize(name:, type: "text", value: nil, **attrs)
      @name = name
      @type = type
      @value = value
      @attrs = attrs
    end

    def view_template
      input(
        type: @type,
        name: @name,
        value: @value,
        class: "form-input",
        id: @attrs.delete(:id) || @name,
        **@attrs
      )
    end
  end
end
