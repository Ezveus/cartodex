module Admin
  module StandardPools
    class Form < ApplicationComponent
      def initialize(standard_pool:)
        @standard_pool = standard_pool
      end

      def view_template
        form_with(model: [ :admin, @standard_pool ], class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @standard_pool)

          render Ui::FormGroup.new(hint: "The oldest legal set — moved by the annual rotation") do
            f.label :first_card_set_id, "Lower bound", class: "form-label"
            f.collection_select :first_card_set_id, card_sets, :id, :code, {}, class: "form-input"
          end

          render Ui::FormGroup.new(hint: "The newest legal set — moved by every release") do
            f.label :last_card_set_id, "Upper bound", class: "form-label"
            f.collection_select :last_card_set_id, card_sets, :id, :code, {}, class: "form-input"
          end

          render Ui::FormGroup.new(hint: "Comma-separated, e.g. H, I, J") do
            f.label :regulation_marks, "Legal regulation marks", class: "form-label"
            f.text_field :regulation_marks, value: marks_value, class: "form-input"
          end

          render Ui::FormGroup.new(hint: "When the cards exist — decides the default for a new deck") do
            f.label :released_on, "Released on", class: "form-label"
            f.date_field :released_on, class: "form-input"
          end

          render Ui::FormGroup.new(hint: "Play! Pokémon legality, about two weeks after release") do
            f.label :legal_on, "Legal on", class: "form-label"
            f.date_field :legal_on, class: "form-input"
          end

          div(class: "form-actions deck-form-actions") do
            f.submit class: "btn btn-primary"
            link_to "Cancel", admin_standard_pools_path, class: "btn btn-secondary"
          end
        end
      end

      private

      def card_sets
        @card_sets ||= CardSet.by_release
      end

      # The column is json; the input is text. What comes back after a failed
      # validation is therefore the *parsed* value — split, stripped and upcased —
      # re-joined for the input, not the raw string the user typed.
      def marks_value
        Array(@standard_pool.regulation_marks).join(", ")
      end
    end
  end
end
