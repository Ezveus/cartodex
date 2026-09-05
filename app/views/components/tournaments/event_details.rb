module Tournaments
  # The event's own facts, read-only. Rendered by both the public event page and a
  # participation's page — extracted rather than copied, for the reason Ui::CardPreview was:
  # two views showing the same facts, one place describing them.
  class EventDetails < ApplicationComponent
    # Why the venue is a detail row here and not a badge in ShowView's header: it is a fact about
    # the event, like its date and its tier, and it belongs beside them on *both* pages that print
    # those facts — a header badge would say it on the event page and stay silent on a
    # participation's, which reads the same event. It also needs a sentence rather than a word,
    # and the sentence is the point: an online event withholds "Record your participation", "This
    # is me" and "Publish my participation", and is absent from a catalog its own page links back
    # to, so with nothing saying why, four missing things read as four bugs.
    ONLINE_NOTE = "Imported from online play, so it is not in the tournament catalog and " \
                  "participation is not recorded against it."

    def initialize(tournament:)
      @tournament = tournament
    end

    def view_template
      div(class: "tournament-details") do
        detail_row("Date") { localize(@tournament.date, format: :long) }
        venue_row if @tournament.online?
        detail_row("Tier") { @tournament.tier_label }
        detail_row("Format") { @tournament.format_label }
      end
    end

    private

    # Printed only for an online event, and there is deliberately nowhere to change it: `online`
    # is written by the online importer and by nothing else, so there is no form control for it
    # and tournament_params does not permit it. The parallel with open_participant_count — which
    # *is* hand-correctable — does not carry: that is a scraped number that can be wrong and that
    # caps every placement above it, whereas this is a fact about which importer wrote the row.
    # A member typing an event into the catalog by hand cannot produce an online one, and a
    # checkbox here would let any member move an event in and out of the public catalog, which is
    # the one thing decision §3 uses this column for.
    def venue_row
      detail_row("Venue") do
        plain "Online play"
        div(class: "text-muted") { ONLINE_NOTE }
      end
    end

    def detail_row(label, &block)
      div(class: "data-table-row") do
        div(class: "data-table-cell") { label }
        div(class: "data-table-cell", &block)
      end
    end
  end
end
