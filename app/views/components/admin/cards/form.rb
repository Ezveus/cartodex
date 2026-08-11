module Admin
  module Cards
    class Form < ApplicationComponent
      def initialize(card:)
        @card = card
      end

      def view_template
        form_with(model: [ :admin, @card ], class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @card)

          render Ui::FormGroup.new do
            f.label :name, class: "form-label"
            f.text_field :name, class: "form-input"
          end
          render Ui::FormGroup.new do
            f.label :card_type, class: "form-label"
            f.select :card_type, Card::CARD_TYPES, { include_blank: true }, class: "form-input"
          end
          render Ui::FormGroup.new do
            f.label :hp, class: "form-label"
            f.number_field :hp, class: "form-input"
          end
          render Ui::FormGroup.new do
            f.label :rarity, class: "form-label"
            f.text_field :rarity, class: "form-input"
          end
          render Ui::FormGroup.new do
            f.label :type_symbol, "Energy Type", class: "form-label"
            f.select :type_symbol, Card::ENERGY_TYPES, { include_blank: true }, class: "form-input"
          end
          # Pokémon-only, but presence-validated: without this field a card switched
          # to "Pokémon" could never be saved from here.
          render Ui::FormGroup.new do
            f.label :retreat_cost, class: "form-label"
            f.number_field :retreat_cost, min: 0, class: "form-input"
          end
          render Ui::FormGroup.new do
            f.label :set_name, "Set Code", class: "form-label"
            f.text_field :set_name, class: "form-input"
          end
          render Ui::FormGroup.new do
            f.label :set_number, class: "form-label"
            f.text_field :set_number, class: "form-input"
          end
          render Ui::FormGroup.new do
            f.label :card_set_id, "Card Set", class: "form-label"
            f.collection_select :card_set_id, CardSet.order(:name), :id, :name, { include_blank: "— None —" }, class: "form-input"
          end

          div(class: "form-actions deck-form-actions") do
            f.submit "Update Card", class: "btn btn-primary"
            link_to "Cancel", admin_card_path(@card), class: "btn btn-secondary"
          end
        end
      end
    end
  end
end
