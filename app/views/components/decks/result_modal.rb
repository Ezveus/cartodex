module Decks
  class ResultModal < ApplicationComponent
    def initialize(deck:)
      @deck = deck
    end

    def view_template
      dialog(class: "result-modal", data: { result_modal_target: "dialog" }) do
        div(class: "result-modal-content") do
          h2 { "Log Result" }
          input(type: "hidden", data: { result_modal_target: "archetypeId" })

          render DeckResults::ResultFields.new
          archetype_search_group
          create_archetype_section
          tournament_group
          notes_group
          actions
        end
      end
    end

    private

    # The user picks a tournament; the value is their participation in it, which is what a
    # match hangs off. Ordered by the event's date, so the select reads the way the deck's
    # history does.
    def tournament_group
      # sort_by on the association itself, not on a fresh relation: DecksController preloads
      # tournament_entries with their event and profile, and `.includes(…)` here would build a
      # new relation that ignores all of it — an N+1 on the profile picker_label reads, hidden
      # from a plain query count because the entry SELECT it repeats is served by the query cache.
      entries = @deck.tournament_entries.sort_by { |e| e.tournament.date }.reverse
      return if entries.empty?

      render Ui::FormGroup.new(label: "Tournament (optional)") do
        select(class: "form-input", data: { result_modal_target: "tournamentEntrySelect" }) do
          option(value: "") { "— None —" }
          entries.each do |entry|
            option(value: entry.id) { entry.picker_label }
          end
        end
      end
    end

    def archetype_search_group
      render Ui::FormGroup.new(label: "Opponent archetype") do
        input(
          type: "text",
          class: "form-input",
          placeholder: "Search archetype...",
          data: { result_modal_target: "archetypeInput", action: "input->result-modal#searchArchetypes" }
        )
        div(class: "archetype-search-results", data: { result_modal_target: "archetypeResults" })
      end
    end

    def create_archetype_section
      div(class: "create-archetype-section", style: "display: none;", data: { result_modal_target: "createSection" }) do
        p(class: "form-label", style: "font-weight: 600; margin-bottom: 0.5rem;") { "New archetype" }
        card_search_group(label_text: "Primary card", target: "primary")
        card_search_group(label_text: "Secondary card (optional)", target: "secondary")
        button(type: "button", class: "btn btn-secondary btn-sm", data: { action: "result-modal#cancelCreate" }) { "Cancel new archetype" }
      end
    end

    def card_search_group(label_text:, target:)
      render Ui::CardSelect.new(
        label: label_text,
        hidden_data:  { result_modal_target: "#{target}Id" },
        input_data:   { result_modal_target: "#{target}Input", action: "input->result-modal#search#{target.capitalize}" },
        results_data: { result_modal_target: "#{target}Results" }
      )
    end

    def notes_group
      render Ui::FormGroup.new(label: "Notes (optional)") do
        textarea(class: "form-input", rows: "2", data: { result_modal_target: "notesInput" })
      end
    end

    def actions
      div(class: "form-actions result-modal-actions") do
        button(class: "btn btn-primary", data: { action: "result-modal#submit", result_modal_target: "submitButton" }) { "Save" }
        button(class: "btn btn-secondary", type: "button", data: { action: "result-modal#close" }) { "Cancel" }
      end
    end
  end
end
