module Decks
  class TournamentPdfModal < ApplicationComponent
    def initialize(deck:, tournament_profiles:)
      @deck = deck
      @tournament_profiles = tournament_profiles
    end

    def view_template
      dialog(
        class: "result-modal",
        data: {
          tournament_pdf_target: "dialog",
          action: "click->tournament-pdf#backdropClose"
        }
      ) do
        div(class: "result-modal-content") do
          h2 { "Tournament PDF" }

          if @tournament_profiles.any?
            profile_form
          else
            empty_state
          end
        end
      end
    end

    private

    def profile_form
      p { "Select the profile to print on the decklist." }

      render Ui::FormGroup.new(label: "Profile") do
        select(class: "form-input", data: { tournament_pdf_target: "profileSelect" }) do
          @tournament_profiles.each do |profile|
            option(value: profile.id) { "#{profile.player_name} (#{profile.player_id})" }
          end
        end
      end

      div(class: "form-actions result-modal-actions") do
        button(
          class: "btn btn-primary",
          data: { action: "tournament-pdf#download", tournament_pdf_deck_id_value: @deck.id }
        ) { "Download PDF" }
        button(
          class: "btn btn-secondary",
          type: "button",
          data: { action: "tournament-pdf#close" }
        ) { "Cancel" }
      end
    end

    def empty_state
      p { "You don't have any tournament profiles yet." }
      div(class: "form-actions result-modal-actions") do
        link_to "Create a profile", helpers.new_tournament_profile_path, class: "btn btn-primary"
        button(
          class: "btn btn-secondary",
          type: "button",
          data: { action: "tournament-pdf#close" }
        ) { "Cancel" }
      end
    end
  end
end
