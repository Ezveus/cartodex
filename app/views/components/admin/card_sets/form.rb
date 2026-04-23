module Admin
  module CardSets
    class Form < ApplicationComponent
      def initialize(card_set:)
        @card_set = card_set
      end

      def view_template
        form_with(model: [ :admin, @card_set ], class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @card_set)

          render Ui::FormGroup.new do
            f.label :code, class: "form-label"
            f.text_field :code, class: "form-input"
          end

          render Ui::FormGroup.new do
            f.label :name, class: "form-label"
            f.text_field :name, class: "form-input"
          end

          render Ui::FormGroup.new do
            f.label :block_name, "Block", class: "form-label"
            f.text_field :block_name, class: "form-input"
          end

          render Ui::FormGroup.new do
            f.label :release_date, class: "form-label"
            f.date_field :release_date, class: "form-input"
          end

          render Ui::FormGroup.new do
            f.label :logo_url, "Logo URL", class: "form-label"
            f.text_field :logo_url, class: "form-input"
          end

          div(class: "form-actions deck-form-actions") do
            f.submit class: "btn btn-primary"
            link_to "Cancel", admin_card_sets_path, class: "btn btn-secondary"
          end
        end
      end
    end
  end
end
