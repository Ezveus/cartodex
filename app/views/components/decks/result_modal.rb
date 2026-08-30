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

    def tournament_group
      return if @deck.tournaments.empty?

      render Ui::FormGroup.new(label: "Tournament (optional)") do
        select(class: "form-input", data: { result_modal_target: "tournamentSelect" }) do
          option(value: "") { "— None —" }
          @deck.tournaments.order(date: :desc).each do |tournament|
            option(value: tournament.id) { "#{tournament.name} (#{localize(tournament.date)})" }
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
        button(class: "btn btn-primary", data: { action: "result-modal#submit" }) { "Save" }
        button(class: "btn btn-secondary", type: "button", data: { action: "result-modal#close" }) { "Cancel" }
      end
    end
  end
end
