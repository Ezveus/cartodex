module Tournaments
  class IndexView < ApplicationComponent
    def initialize(tournaments:)
      @tournaments = tournaments
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "Tournaments") do
          link_to "New Tournament", new_tournament_path, class: "btn btn-primary"
        end

        if @tournaments.any?
          render Ui::DataTable.new(columns: %w[Name Date Tier Deck Placement CP Actions]) do |t|
            @tournaments.each do |tournament|
              t.row do
                t.cell { link_to tournament.name, tournament_path(tournament) }
                t.cell { localize(tournament.date, format: :long) }
                t.cell { tournament.tier_label }
                t.cell { tournament.deck.name }
                t.cell { placement_label(tournament) }
                t.cell { tournament.championship_points || "—" }
                t.cell do
                  render Ui::AdminActions.new(
                    edit_path: edit_tournament_path(tournament),
                    delete_path: tournament_path(tournament),
                    confirm_message: "Delete #{tournament.name}?"
                  )
                end
              end
            end
          end
        else
          p { "No tournaments yet." }
        end
      end
    end

    private

    def placement_label(tournament)
      return "—" if tournament.placement.blank?

      label = "##{tournament.placement}"
      label += " / #{tournament.participant_count}" if tournament.participant_count.present?
      label
    end
  end
end
