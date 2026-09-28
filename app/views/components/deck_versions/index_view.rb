module DeckVersions
  class IndexView < ApplicationComponent
    COLUMNS = [ "Version", "Period", "Format", "W / L / D / T", "Participations", "" ].freeze

    def initialize(deck:, versions:, drift:, result_counts:, entry_counts:)
      @deck = deck
      @versions = versions
      @drift = drift
      @result_counts = result_counts
      @entry_counts = entry_counts
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "#{@deck.name} — Versions") do
          div(class: "admin-header-actions") do
            link_to "Add an earlier version", new_deck_version_path(@deck), class: "btn btn-secondary"
            link_to "Back to Deck", deck_path(@deck), class: "btn btn-secondary"
          end
        end

        status_line
        versions_table if @versions.any?
      end
    end

    private

    # The snapshot button exists only where the server would accept it: with no version at all,
    # or while the live list has moved away from the latest one. Offering it otherwise would
    # only ever earn a refusal.
    def status_line
      div(class: "deck-versions-status") do
        if @versions.empty?
          p { "No version yet. The first result logged with this deck records one." }
          snapshot_button("Record version 1 now")
        elsif @drift.drift?
          p { "The list has changed since #{latest.label}." }
          snapshot_button("Record version #{latest.number + 1} from the current list")
        else
          p { "The list is #{latest.label}, unchanged." }
        end
      end
    end

    # The numbered array's own last element, not `@drift.latest`: the drift result's copy was
    # read without a number, and asking it for one costs a COUNT.
    def latest
      @versions.last
    end

    def snapshot_button(label)
      button_to label, snapshot_deck_versions_path(@deck), method: :post, class: "btn btn-primary btn-sm"
    end

    def versions_table
      render Ui::DataTable.new(columns: COLUMNS) do |t|
        @versions.each_with_index do |version, i|
          t.row do
            t.cell { link_to version.label, deck_version_path(@deck, version) }
            t.cell { DeckVersions::Labels.period(version, @versions[i + 1]) }
            t.cell { version.format_label }
            t.cell { record(version) }
            t.cell { @entry_counts.fetch(version.id, 0).to_s }
            t.cell(class: "data-table-cell deck-versions-actions") { row_actions(version) }
          end
        end
      end
    end

    def record(version)
      counts = @result_counts.fetch(version.id, {})
      DeckResult::RESULTS.map { |r| counts.fetch(r, 0) }.join(" / ")
    end

    # Delete is offered on every row and refused by the server while anything is attached: the
    # refusal names what is in the way, which a missing button could not.
    def row_actions(version)
      link_to "Edit date", edit_deck_version_path(@deck, version), class: "btn btn-secondary btn-sm"
      button_to "Delete", deck_version_path(@deck, version),
        method: :delete,
        class: "btn btn-danger btn-sm",
        form: { class: "deck-versions-delete", data: { turbo_confirm: "Delete #{version.label}?" } }
    end
  end
end
