module Ui
  class AuthLinks < ApplicationComponent
    def initialize(controller_name:, resource_name:)
      @controller_name = controller_name
      @resource_name = resource_name
    end

    def view_template
      div(class: "auth-links") do
        unless @controller_name == "sessions"
          link_to "Log in", new_session_path(@resource_name)
        end

        unless @controller_name == "registrations"
          link_to "Sign up", new_registration_path(@resource_name)
        end

        unless @controller_name == "passwords"
          link_to "Forgot your password?", new_password_path(@resource_name)
        end
      end
    end
  end
end
