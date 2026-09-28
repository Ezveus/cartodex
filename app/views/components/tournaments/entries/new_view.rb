module Tournaments
  module Entries
    class NewView < ApplicationComponent
      def initialize(tournament:, entry:, decks:, tournament_profiles:, version_prompt: nil, versions: [])
        @tournament = tournament
        @entry = entry
        @decks = decks
        @tournament_profiles = tournament_profiles
        @version_prompt = version_prompt
        @versions = versions
      end

      def view_template
        div(class: "deck-form-container") do
          h1 { "Record your participation" }
          render Tournaments::Entries::Form.new(
            tournament: @tournament, entry: @entry, decks: @decks, tournament_profiles: @tournament_profiles,
            version_prompt: @version_prompt, versions: @versions
          )
        end
      end
    end
  end
end
