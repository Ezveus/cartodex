module Admin
  module Archetypes
    class Form < ApplicationComponent
      def initialize(archetype:)
        @archetype = archetype
      end

      def view_template
        form_with(model: [ :admin, @archetype ], class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @archetype)

          render Ui::FormGroup.new do
            f.label :name, "Name (leave blank for auto-generated)", class: "form-label"
            f.text_field :name, class: "form-input", placeholder: "Auto-generated from Pokémon names"
          end

          pokemon_autocomplete(f, :primary_pokemon_id, "Primary Pokémon", @archetype.primary_pokemon)
          pokemon_autocomplete(f, :secondary_pokemon_id, "Secondary Pokémon (optional)", @archetype.secondary_pokemon)

          render Ui::FormGroup.new do
            f.label :parent_id, "Parent Archetype (optional)", class: "form-label"
            f.collection_select :parent_id, Archetype.roots.where.not(id: @archetype.id).order(:name), :id, :name,
              { include_blank: "— None (root) —" }, class: "form-input"
          end

          div(class: "form-actions deck-form-actions") do
            f.submit class: "btn btn-primary"
            link_to "Cancel", admin_archetypes_path, class: "btn btn-secondary"
          end
        end
      end
      private

      def pokemon_autocomplete(f, field, label_text, current_pokemon)
        render Ui::PokemonSelect.new(
          label: label_text,
          current_value: current_pokemon&.name,
          wrapper_data: { controller: "pokemon-select" },
          input_data:   { pokemon_select_target: "input", action: "input->pokemon-select#search" },
          results_data: { pokemon_select_target: "results" }
        ) do
          f.hidden_field field, data: { pokemon_select_target: "hiddenField" }
        end
      end
    end
  end
end
