module Ui
  class FormGroup < ApplicationComponent
    def initialize(label:, field_name: nil, errors: [], hint: nil)
      @label = label
      @field_name = field_name
      @errors = Array(errors)
      @hint = hint
    end

    def view_template(&block)
      div(class: "form-group") do
        label(class: "form-label", for: @field_name) { @label }
        yield if block
        em(class: "form-hint") { @hint } if @hint
        @errors.each do |error|
          span(class: "form-error") { error }
        end
      end
    end
  end
end
