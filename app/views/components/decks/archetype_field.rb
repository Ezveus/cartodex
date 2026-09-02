module Decks
  # Archetype picker for the deck form: search and select an existing archetype,
  # create a new one inline, or let the "Suggest" button infer one from the
  # deck's line-up. Backed by the `archetype-picker` Stimulus controller and the
  # `/api/archetypes` + `/api/decks/:id/suggested_archetype` endpoints.
  class ArchetypeField < ApplicationComponent
    def initialize(form:, deck:)
      @form = form
      @deck = deck
    end

    def view_template
      div(
        class: "deck-archetype-field",
        data: { controller: "archetype-picker", archetype_picker_deck_id_value: @deck.key }
      ) do
        render Ui::FormGroup.new(label: "Archetype", field_name: "deck_archetype") do
          @form.hidden_field :archetype_id, data: { archetype_picker_target: "archetypeId" }
          search_row
          div(class: "archetype-search-results", data: { archetype_picker_target: "results" })
        end
        create_section
      end
    end

    private

    def search_row
      div(class: "archetype-field-search") do
        input(
          type: "text",
          id: "deck_archetype",
          class: "form-input",
          placeholder: "Search archetype…",
          value: @deck.archetype&.name,
          data: { archetype_picker_target: "input", action: "input->archetype-picker#search" }
        )
        if @deck.persisted?
          button(
            type: "button",
            class: "btn btn-secondary btn-sm",
            data: { action: "archetype-picker#suggest" }
          ) { "Suggest" }
        end
      end
    end

    def create_section
      div(class: "create-archetype-section", style: "display: none;", data: { archetype_picker_target: "createSection" }) do
        p(class: "form-label", style: "font-weight: 600; margin-bottom: 0.5rem;") { "New archetype" }
        card_search_group(label_text: "Primary card", target: "primary")
        card_search_group(label_text: "Secondary card (optional)", target: "secondary")
        div(class: "form-actions") do
          button(type: "button", class: "btn btn-primary btn-sm",
            data: { action: "archetype-picker#createArchetype", archetype_picker_target: "createButton" }) { "Create & select" }
          button(type: "button", class: "btn btn-secondary btn-sm", data: { action: "archetype-picker#cancelCreate" }) { "Cancel" }
        end
      end
    end

    def card_search_group(label_text:, target:)
      render Ui::CardSelect.new(
        label: label_text,
        hidden_data:  { archetype_picker_target: "#{target}Id" },
        input_data:   { archetype_picker_target: "#{target}Input", action: "input->archetype-picker#search#{target.capitalize}" },
        results_data: { archetype_picker_target: "#{target}Results" }
      )
    end
  end
end
