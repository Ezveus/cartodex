module Devise
  module Registrations
    class NewView < ApplicationComponent
      def initialize(resource:, resource_name:, devise_mapping:)
        @resource = resource
        @resource_name = resource_name
        @devise_mapping = devise_mapping
      end

      def view_template
        render AuthLayout.new(
          title: "Sign up",
          resource: @resource,
          resource_name: @resource_name,
          controller_name: "registrations"
        ) do
          form_with(model: @resource, url: registration_path(@resource_name), data: { turbo: true }) do |f|
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

            min_length = @resource.class.password_length.min
            render Ui::FormGroup.new(
              label: "Password",
              field_name: "password",
              hint: "#{min_length} characters minimum"
            ) do
              render Ui::TextInput.new(
                name: "#{@resource_name}[password]",
                type: "password",
                autocomplete: "new-password",
                id: "password"
              )
            end

            render Ui::FormGroup.new(label: "Password confirmation", field_name: "password_confirmation") do
              render Ui::TextInput.new(
                name: "#{@resource_name}[password_confirmation]",
                type: "password",
                autocomplete: "new-password",
                id: "password_confirmation"
              )
            end

            div(class: "form-actions") do
              render Ui::Button.new(label: "Sign up", variant: :primary)
            end
          end
        end
      end
    end
  end
end
