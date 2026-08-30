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
            f.text_field :name, class: "form-input", placeholder: "Auto-generated from card names"
          end

          card_autocomplete(f, :primary_card_id, "Primary card", @archetype.primary_card)
          card_autocomplete(f, :secondary_card_id, "Secondary card (optional)", @archetype.secondary_card)

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

      def card_autocomplete(f, field, label_text, current_card)
        render Ui::CardSelect.new(
          label: label_text,
          current_value: current_card&.printing_label,
          wrapper_data: { controller: "card-select" },
          input_data:   { card_select_target: "input", action: "input->card-select#search" },
          results_data: { card_select_target: "results" }
        ) do
          f.hidden_field field, data: { card_select_target: "hiddenField" }
        end
      end
    end
  end
end
