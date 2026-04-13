module Ui
  class FormGroup < ApplicationComponent
    def initialize(label: nil, field_name: nil, errors: [], hint: nil, **html_attrs)
      @label = label
      @field_name = field_name
      @errors = Array(errors)
      @hint = hint
      @html_attrs = html_attrs
    end

    def view_template(&block)
      div(class: "form-group", **@html_attrs) do
        label(class: "form-label", for: @field_name) { @label } if @label
        yield if block
        em(class: "form-hint") { @hint } if @hint
        @errors.each do |error|
          span(class: "form-error") { error }
        end
      end
    end
  end
end
