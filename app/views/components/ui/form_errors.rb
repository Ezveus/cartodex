module Ui
  class FormErrors < ApplicationComponent
    def initialize(resource:)
      @resource = resource
    end

    def view_template
      return if @resource.errors.empty?

      div(class: "form-errors") do
        h3 do
          count = @resource.errors.count
          "#{count} #{count == 1 ? 'error' : 'errors'} prohibited this action:"
        end
        ul do
          @resource.errors.full_messages.each do |message|
            li { message }
          end
        end
      end
    end
  end
end
