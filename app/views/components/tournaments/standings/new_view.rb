module Tournaments
  module Standings
    class NewView < ApplicationComponent
      def initialize(tournament:, standing:, existing: nil, entry: nil)
        @tournament = tournament
        @standing = standing
        @existing = existing
        @entry = entry
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Add a standing")
          render Tournaments::Standings::Form.new(
            tournament: @tournament, standing: @standing, existing: @existing, entry: @entry
          )
        end
      end
    end
  end
end
