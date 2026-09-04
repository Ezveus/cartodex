module Tournaments
  module Standings
    # The event's field, grouped by age division and read in the order Play! Pokémon lists them —
    # junior, senior, masters. That is TournamentStanding::DIVISIONS' own order, and it is not the
    # alphabetical one a plain SQL sort on the column gives.
    class Table < ApplicationComponent
      def initialize(standings:, viewer: nil, can_edit: false, claimable_entries: [])
        @standings = standings
        @viewer = viewer
        @can_edit = can_edit
        @claimable_entries = claimable_entries
      end

      def view_template
        grouped = @standings.group_by(&:division)

        TournamentStanding::DIVISIONS.each do |division|
          rows = grouped[division]
          next if rows.blank?

          h3 { division.capitalize }
          division_table(rows)
        end
      end

      private

      # The wrapper is spelled out rather than delegated to Ui::DataTable because each row is its
      # own component — see Row's comment. The two halves of that component are four lines, and
      # this is the price of a broadcastable row.
      def division_table(rows)
        div(class: "data-table") do
          div(class: "data-table-header") do
            Row::COLUMNS.each { |column| div(class: "data-table-cell") { column } }
          end
          div(class: "data-table-body") do
            rows.each do |standing|
              render Row.new(
                standing: standing, viewer: @viewer,
                can_edit: @can_edit, claimable_entries: @claimable_entries
              )
            end
          end
        end
      end
    end
  end
end
