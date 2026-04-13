module Decks
  class ResultModal < ApplicationComponent
    RESULT_TYPES = %w[win loss draw timeout].freeze

    def view_template
      dialog(class: "result-modal", data: { result_modal_target: "dialog" }) do
        div(class: "result-modal-content") do
          h2 { "Log Result" }
          input(type: "hidden", data: { result_modal_target: "resultInput" })
          input(type: "hidden", data: { result_modal_target: "archetypeId" })

          result_type_buttons
          archetype_search_group
          create_archetype_section
          notes_group
          actions
        end
      end
    end

    private

    def result_type_buttons
      div(class: "result-type-buttons") do
        RESULT_TYPES.each do |r|
          button(
            type: "button",
            class: "result-type-btn result-#{r}",
            data: { result: r, action: "result-modal#selectResult", result_modal_target: "resultBtn" }
          ) { r.capitalize }
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
        pokemon_search_group(label_text: "Primary Pokémon", target: "primary")
        pokemon_search_group(label_text: "Secondary Pokémon (optional)", target: "secondary")
        button(type: "button", class: "btn btn-secondary btn-sm", data: { action: "result-modal#cancelCreate" }) { "Cancel new archetype" }
      end
    end

    def pokemon_search_group(label_text:, target:)
      render Ui::FormGroup.new(label: label_text) do
        input(type: "hidden", data: { result_modal_target: "#{target}Id" })
        input(
          type: "text",
          class: "form-input",
          placeholder: "Search Pokémon...",
          data: { result_modal_target: "#{target}Input", action: "input->result-modal#search#{target.capitalize}" }
        )
        div(class: "archetype-search-results", data: { result_modal_target: "#{target}Results" })
      end
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
