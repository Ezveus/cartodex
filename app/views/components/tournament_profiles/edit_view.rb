module TournamentProfiles
  class EditView < ApplicationComponent
    def initialize(profile:)
      @profile = profile
    end

    def view_template
      div(class: "deck-form-container") do
        h1 { "Edit Tournament Profile" }
        render TournamentProfiles::Form.new(profile: @profile)
      end
    end
  end
end
