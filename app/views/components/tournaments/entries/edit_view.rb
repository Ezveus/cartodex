module Tournaments
  module Entries
    class EditView < ApplicationComponent
      def initialize(tournament:, entry:, decks:, tournament_profiles:)
        @tournament = tournament
        @entry = entry
        @decks = decks
        @tournament_profiles = tournament_profiles
      end

      def view_template
        div(class: "deck-form-container") do
          h1 { "Edit your participation" }
          render Tournaments::Entries::Form.new(
            tournament: @tournament, entry: @entry, decks: @decks, tournament_profiles: @tournament_profiles
          )
        end
      end
    end
  end
end
