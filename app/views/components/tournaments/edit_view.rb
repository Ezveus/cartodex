module Tournaments
  class EditView < ApplicationComponent
    def initialize(tournament:, decks:, tournament_profiles:)
      @tournament = tournament
      @decks = decks
      @tournament_profiles = tournament_profiles
    end

    def view_template
      div(class: "deck-form-container") do
        h1 { "Edit Tournament" }
        render Tournaments::Form.new(tournament: @tournament, decks: @decks, tournament_profiles: @tournament_profiles)
      end
    end
  end
end
