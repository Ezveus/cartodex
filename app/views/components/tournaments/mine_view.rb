module Tournaments
  # What the old /tournaments showed: my participations, with the figures that are mine.
  class MineView < ApplicationComponent
    def initialize(entries:)
      @entries = entries
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "My tournaments") do
          link_to "Browse the catalog", tournaments_path, class: "btn btn-secondary"
        end

        if @entries.any?
          render Ui::DataTable.new(columns: %w[Tournament Date Tier Deck Placement CP Actions]) do |t|
            @entries.each { |entry| row(t, entry) }
          end
        else
          p { "No participations recorded yet." }
        end
      end
    end

    private

    def row(table, entry)
      tournament = entry.tournament

      table.row do
        table.cell { link_to tournament.name, tournament_entry_path(tournament, entry) }
        table.cell { localize(tournament.date, format: :long) }
        table.cell { tournament.tier_label }
        table.cell { entry.deck.name }
        table.cell { placement_label(entry) }
        table.cell { entry.championship_points || "—" }
        table.cell do
          render Ui::AdminActions.new(
            edit_path: edit_tournament_entry_path(tournament, entry),
            delete_path: tournament_entry_path(tournament, entry),
            confirm_message: "Delete your participation in #{tournament.name}?"
          )
        end
      end
    end

    def placement_label(entry)
      return "—" if entry.placement.blank?

      label = "##{entry.placement}"
      label += " / #{entry.participant_count}" if entry.participant_count.present?
      label
    end
  end
end
