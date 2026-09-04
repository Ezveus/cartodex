module Tournaments
  module Standings
    class EditView < ApplicationComponent
      def initialize(tournament:, standing:, existing: nil)
        @tournament = tournament
        @standing = standing
        @existing = existing
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Edit #{@standing.player_name}'s standing")
          render Tournaments::Standings::Form.new(
            tournament: @tournament, standing: @standing, existing: @existing
          )
        end
      end
    end
  end
end
