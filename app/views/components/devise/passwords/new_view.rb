module Devise
  module Passwords
    class NewView < ApplicationComponent
      def initialize(resource:, resource_name:, devise_mapping:)
        @resource = resource
        @resource_name = resource_name
        @devise_mapping = devise_mapping
      end

      def view_template
        render AuthLayout.new(
          title: "Forgot your password?",
          resource: @resource,
          resource_name: @resource_name,
          controller_name: "passwords"
        ) do
          form_with(model: @resource, url: password_path(@resource_name), method: :post, data: { turbo: true }) do |f|
            render Ui::FormGroup.new(label: "Email", field_name: "email") do
              render Ui::TextInput.new(
                name: "#{@resource_name}[email]",
                type: "email",
                value: @resource.email,
                autofocus: true,
                autocomplete: "email",
                id: "email"
              )
            end

            div(class: "form-actions") do
              render Ui::Button.new(label: "Send reset instructions", variant: :primary)
            end
          end
        end
      end
    end
  end
end
