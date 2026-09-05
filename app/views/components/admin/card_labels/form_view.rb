module Admin
  module CardLabels
    # One component for both new and edit: the two pages differ only in heading text and in
    # whether family is still choosable, both of which read off @card_label.persisted?.
    class FormView < ApplicationComponent
      def initialize(card_label:)
        @card_label = card_label
      end

      def view_template
        div(class: "admin-container") do
          h1 { heading }

          form_with(model: [ :admin, @card_label ], class: "deck-form") do |f|
            render Ui::FormErrors.new(resource: @card_label)

            render Ui::FormGroup.new do
              f.label :slug, class: "form-label"
              f.text_field :slug, class: "form-input"
            end

            render Ui::FormGroup.new do
              f.label :name, class: "form-label"
              f.text_field :name, class: "form-input"
            end

            # Disabled on edit, not merely ignored: the select's own disabled state is what keeps
            # the browser from submitting a family at all on update, which is what the controller
            # relies on — family is permitted only when action_name == "create".
            render Ui::FormGroup.new(hint: family_hint) do
              f.label :family, class: "form-label"
              f.select :family, CardLabel::FAMILIES, {}, class: "form-input", disabled: @card_label.persisted?
            end

            render Ui::FormGroup.new do
              f.label :position, class: "form-label"
              f.number_field :position, min: 0, class: "form-input"
            end

            render Ui::FormGroup.new(hint: "Limitless search token, e.g. is:ace — leave blank if this label has nothing to import") do
              f.label :source_query, "Search token", class: "form-label"
              f.text_field :source_query, class: "form-input"
            end

            render Ui::FormGroup.new do
              f.label :description, class: "form-label"
              f.text_area :description, class: "form-input"
            end

            div(class: "form-actions deck-form-actions") do
              f.submit class: "btn btn-primary"
              link_to "Cancel", admin_card_labels_path, class: "btn btn-secondary"
            end
          end
        end
      end

      private

      def heading
        @card_label.persisted? ? "Edit #{@card_label.name}" : "New Card Label"
      end

      def family_hint
        return "Family cannot be changed once created." if @card_label.persisted?

        "Role labels are seeded from the application — pick type here."
      end
    end
  end
end
