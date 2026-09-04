module Ui
  # The archetype picker: search an existing archetype, create one inline, or — given a deck —
  # let "Suggest" infer one from its line-up. Backed by the `archetype-picker` Stimulus controller
  # and the `/api/archetypes` + `/api/decks/:key/suggested_archetype` endpoints.
  #
  # Lives under Ui:: because both the deck form and the tournament standings form render it. It
  # used to be Decks::ArchetypeField, soldered to a deck: it read @deck.key for the Suggest button
  # and @deck.archetype&.name for the input's value. A standings row has an archetype and no deck,
  # and a degraded copy of this picker was the alternative.
  #
  # `deck_key:` nil renders no Suggest button — the only thing here a deck is needed for. The
  # controller still connects: deckKey is a String value, so Stimulus defaults it to "", and
  # #suggest returns early on it.
  class ArchetypePicker < ApplicationComponent
    def initialize(form:, selected: nil, deck_key: nil, field_id: "deck_archetype")
      @form = form
      @selected = selected
      @deck_key = deck_key
      @field_id = field_id
    end

    def view_template
      div(
        class: "deck-archetype-field",
        data: { controller: "archetype-picker", archetype_picker_deck_key_value: @deck_key }
      ) do
        render Ui::FormGroup.new(label: "Archetype", field_name: @field_id) do
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
          id: @field_id,
          class: "form-input",
          placeholder: "Search archetype…",
          value: @selected&.name,
          data: { archetype_picker_target: "input", action: "input->archetype-picker#search" }
        )
        suggest_button if @deck_key
      end
    end

    # Only reachable with a deck: it asks /api/decks/:key/suggested_archetype what the deck's
    # line-up looks like, and a standings row has no line-up to ask about. This replaces the old
    # component's `if @deck.persisted?`, which asked the same question about the wrong object.
    def suggest_button
      button(type: "button", class: "btn btn-secondary btn-sm",
             data: { action: "archetype-picker#suggest" }) { "Suggest" }
    end

    def create_section
      div(class: "create-archetype-section", style: "display: none;",
          data: { archetype_picker_target: "createSection" }) do
        p(class: "form-label", style: "font-weight: 600; margin-bottom: 0.5rem;") { "New archetype" }
        card_search_group(label_text: "Primary card", target: "primary")
        card_search_group(label_text: "Secondary card (optional)", target: "secondary")
        div(class: "form-actions") do
          button(type: "button", class: "btn btn-primary btn-sm",
            data: { action: "archetype-picker#createArchetype",
                    archetype_picker_target: "createButton" }) { "Create & select" }
          button(type: "button", class: "btn btn-secondary btn-sm",
            data: { action: "archetype-picker#cancelCreate" }) { "Cancel" }
        end
      end
    end

    def card_search_group(label_text:, target:)
      render Ui::CardSelect.new(
        label: label_text,
        hidden_data:  { archetype_picker_target: "#{target}Id" },
        input_data:   { archetype_picker_target: "#{target}Input",
                        action: "input->archetype-picker#search#{target.capitalize}" },
        results_data: { archetype_picker_target: "#{target}Results" }
      )
    end
  end
end
