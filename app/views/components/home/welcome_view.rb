module Home
  class WelcomeView < ApplicationComponent
    def view_template
      div(class: "welcome-container") do
        h1 { "Cartodex" }
        p { "Your Pokémon Trading Card Game Manager" }
        div(class: "auth-buttons") do
          link_to "Sign In", new_user_session_path, class: "btn btn-primary"
          link_to "Sign Up", new_user_registration_path, class: "btn btn-secondary"
        end
      end
    end
  end
end
