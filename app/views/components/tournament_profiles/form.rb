module TournamentProfiles
  class Form < ApplicationComponent
    def initialize(profile:)
      @profile = profile
    end

    def view_template
      form_with(model: @profile, class: "deck-form") do |f|
        render Ui::FormErrors.new(resource: @profile)

        render Ui::FormGroup.new do
          f.label :player_name, class: "form-label"
          f.text_field :player_name, class: "form-input", autofocus: true, placeholder: "Ash Ketchum"
        end

        render Ui::FormGroup.new do
          f.label :player_id, "Player ID", class: "form-label"
          f.text_field :player_id, class: "form-input", placeholder: "1234567"
        end

        render Ui::FormGroup.new do
          f.label :date_of_birth, class: "form-label"
          f.date_field :date_of_birth, class: "form-input"
        end

        div(class: "form-actions deck-form-actions") do
          f.submit class: "btn btn-primary"
          link_to "Cancel", helpers.tournament_profiles_path, class: "btn btn-secondary"
        end
      end
    end
  end
end
