module Devise
  class AuthLayout < ApplicationComponent
    def initialize(title:, resource:, resource_name:, controller_name:)
      @title = title
      @resource = resource
      @resource_name = resource_name
      @controller_name = controller_name
    end

    def view_template(&block)
      render Ui::Card.new(title: @title) do
        render Ui::FormErrors.new(resource: @resource)
        yield
        render Ui::AuthLinks.new(
          controller_name: @controller_name,
          resource_name: @resource_name
        )
      end
    end
  end
end
