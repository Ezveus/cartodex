module Devise
  module Registrations
    class EditView < ApplicationComponent
      def initialize(resource:, resource_name:, devise_mapping:)
        @resource = resource
        @resource_name = resource_name
        @devise_mapping = devise_mapping
      end

      def view_template
        render AuthLayout.new(
          title: "Edit profile",
          resource: @resource,
          resource_name: @resource_name,
          controller_name: "registrations"
        ) do
          form_with(model: @resource, url: registration_path(@resource_name), method: :put, data: { turbo: true }) do |f|
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
              label: "New password",
              field_name: "password",
              hint: "Leave blank if you don\u2019t want to change it (#{min_length} characters minimum)"
            ) do
              render Ui::TextInput.new(
                name: "#{@resource_name}[password]",
                type: "password",
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

            render Ui::FormGroup.new(
              label: "Current password",
              field_name: "current_password",
              hint: "We need your current password to confirm changes"
            ) do
              render Ui::TextInput.new(
                name: "#{@resource_name}[current_password]",
                type: "password",
                autocomplete: "current-password",
                id: "current_password"
              )
            end

            div(class: "form-actions") do
              render Ui::Button.new(label: "Update", variant: :primary)
            end
          end

          h3(style: "margin-top: 2rem;") { "Cancel my account" }
          p { "Unhappy? " }
          button_to "Cancel my account", registration_path(@resource_name),
            method: :delete,
            class: "btn-danger",
            data: { turbo_confirm: "Are you sure?" }
        end
      end
    end
  end
end
