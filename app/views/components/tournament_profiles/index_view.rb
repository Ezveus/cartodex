module TournamentProfiles
  class IndexView < ApplicationComponent
    def initialize(profiles:)
      @profiles = profiles
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "Tournament Profiles") do
          link_to "New Profile", new_tournament_profile_path, class: "btn btn-primary"
        end

        if @profiles.any?
          render Ui::DataTable.new(columns: %w[Name PlayerID DateOfBirth Division Actions]) do |t|
            @profiles.each do |profile|
              t.row do
                t.cell { profile.player_name }
                t.cell { profile.player_id }
                t.cell { localize(profile.date_of_birth, format: :long) }
                t.cell { profile.division.to_s.capitalize }
                t.cell do
                  render Ui::AdminActions.new(
                    edit_path: edit_tournament_profile_path(profile),
                    delete_path: tournament_profile_path(profile),
                    confirm_message: "Delete #{profile.player_name}?"
                  )
                end
              end
            end
          end
        else
          p { "No tournament profiles yet." }
        end
      end
    end
  end
end
