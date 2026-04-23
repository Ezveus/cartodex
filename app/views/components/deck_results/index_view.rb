module DeckResults
  class IndexView < ApplicationComponent
    def initialize(deck:, results:)
      @deck = deck
      @results = results
    end

    def view_template
      div(class: "admin-container") do
        render Ui::PageHeader.new(title: "#{@deck.name} — Results") do
          div(class: "decks-header-actions") do
            link_to "Stats", stats_deck_path(@deck), class: "btn btn-primary"
            link_to "Back to Deck", deck_path(@deck), class: "btn btn-secondary"
          end
        end

        if @results.any?
          render Ui::DataTable.new(columns: %w[Date Result Archetype Notes Actions]) do |t|
            @results.each do |r|
              t.row do
                t.cell { r.played_at&.strftime("%Y-%m-%d %H:%M") || "\u2014" }
                t.cell { result_badge(r.result) }
                t.cell { r.archetype&.name || "\u2014" }
                t.cell { r.notes.present? ? r.notes.truncate(40) : "\u2014" }
                t.cell { render Ui::AdminActions.new(edit_path: edit_deck_deck_result_path(@deck, r), delete_path: deck_deck_result_path(@deck, r), confirm_message: "Delete this result?") }
              end
            end
          end
        else
          p { "No results yet. Log your first result from the deck page." }
        end
      end
    end

    private

    def result_badge(result)
      render Ui::StatusBadge.new(status: result, label: result.capitalize)
    end
  end
end
