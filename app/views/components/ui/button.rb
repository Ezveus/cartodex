module Ui
  class Button < ApplicationComponent
    def initialize(label:, href: nil, variant: :primary, type: "submit", **attrs)
      @label = label
      @href = href
      @variant = variant
      @type = type
      @attrs = attrs
    end

    def view_template
      css_class = "btn btn-#{@variant}"

      if @href
        a(href: @href, class: css_class, **@attrs) { @label }
      else
        button(type: @type, class: css_class, **@attrs) { @label }
      end
    end
  end
end
