module Tournaments
  # The event's own facts, read-only. Rendered by both the public event page and a
  # participation's page — extracted rather than copied, for the reason Ui::CardPreview was:
  # two views showing the same facts, one place describing them.
  class EventDetails < ApplicationComponent
    def initialize(tournament:)
      @tournament = tournament
    end

    def view_template
      div(class: "tournament-details") do
        detail_row("Date") { localize(@tournament.date, format: :long) }
        detail_row("Tier") { @tournament.tier_label }
        detail_row("Format") { @tournament.format_label }
      end
    end

    private

    def detail_row(label, &block)
      div(class: "data-table-row") do
        div(class: "data-table-cell") { label }
        div(class: "data-table-cell", &block)
      end
    end
  end
end
