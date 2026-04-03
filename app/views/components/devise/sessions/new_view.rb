module Devise
  module Sessions
    class NewView < ApplicationComponent
      def initialize(resource:, resource_name:, devise_mapping:)
        @resource = resource
        @resource_name = resource_name
        @devise_mapping = devise_mapping
      end

      def view_template
        render AuthLayout.new(
          title: "Log in",
          resource: @resource,
          resource_name: @resource_name,
          controller_name: "sessions"
        ) do
          form_with(model: @resource, url: session_path(@resource_name), data: { turbo: true }) do |f|
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

            render Ui::FormGroup.new(label: "Password", field_name: "password") do
              render Ui::TextInput.new(
                name: "#{@resource_name}[password]",
                type: "password",
                autocomplete: "current-password",
                id: "password"
              )
            end

            if @devise_mapping.rememberable?
              div(class: "form-check") do
                input(
                  type: "checkbox",
                  name: "#{@resource_name}[remember_me]",
                  value: "1",
                  id: "remember_me"
                )
                label(for: "remember_me") { "Remember me" }
              end
            end

            div(class: "form-actions") do
              render Ui::Button.new(label: "Log in", variant: :primary)
            end
          end
        end
      end
    end
  end
end
