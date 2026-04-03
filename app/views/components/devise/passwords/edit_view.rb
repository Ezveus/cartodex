module Devise
  module Passwords
    class EditView < ApplicationComponent
      def initialize(resource:, resource_name:, devise_mapping:, reset_password_token:)
        @resource = resource
        @resource_name = resource_name
        @devise_mapping = devise_mapping
        @reset_password_token = reset_password_token
      end

      def view_template
        render AuthLayout.new(
          title: "Change your password",
          resource: @resource,
          resource_name: @resource_name,
          controller_name: "passwords"
        ) do
          form_with(model: @resource, url: password_path(@resource_name), method: :put, data: { turbo: true }) do |f|
            input(
              type: "hidden",
              name: "#{@resource_name}[reset_password_token]",
              value: @reset_password_token
            )

            min_length = @resource.class.password_length.min
            render Ui::FormGroup.new(
              label: "New password",
              field_name: "password",
              hint: "#{min_length} characters minimum"
            ) do
              render Ui::TextInput.new(
                name: "#{@resource_name}[password]",
                type: "password",
                autofocus: true,
                autocomplete: "new-password",
                id: "password"
              )
            end

            render Ui::FormGroup.new(label: "Confirm new password", field_name: "password_confirmation") do
              render Ui::TextInput.new(
                name: "#{@resource_name}[password_confirmation]",
                type: "password",
                autocomplete: "new-password",
                id: "password_confirmation"
              )
            end

            div(class: "form-actions") do
              render Ui::Button.new(label: "Change my password", variant: :primary)
            end
          end
        end
      end
    end
  end
end
