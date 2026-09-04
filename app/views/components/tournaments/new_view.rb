module Tournaments
  class NewView < ApplicationComponent
    def initialize(tournament:, existing: nil)
      @tournament = tournament
      @existing = existing
    end

    def view_template
      div(class: "deck-form-container") do
        h1 { "New Tournament" }
        render Tournaments::Form.new(tournament: @tournament, existing: @existing)
      end
    end
  end
end
