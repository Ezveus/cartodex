module Admin
  module Cards
    class EditView < ApplicationComponent
      def initialize(card:)
        @card = card
      end

      def view_template
        div(class: "admin-container") do
          h1 { "Edit #{@card.name}" }

          form_with(model: [ :admin, @card ], class: "deck-form") do |f|
            div(class: "form-group") do
              f.label :name, class: "form-label"
              f.text_field :name, class: "form-input"
            end
            div(class: "form-group") do
              f.label :card_type, class: "form-label"
              f.select :card_type, %w[Pokémon Trainer Energy], {}, class: "form-input"
            end
            div(class: "form-group") do
              f.label :hp, class: "form-label"
              f.number_field :hp, class: "form-input"
            end
            div(class: "form-group") do
              f.label :rarity, class: "form-label"
              f.text_field :rarity, class: "form-input"
            end
            div(class: "form-group") do
              f.label :type_symbol, "Energy Type", class: "form-label"
              f.text_field :type_symbol, class: "form-input"
            end
            div(class: "form-group") do
              f.label :card_set_id, "Card Set", class: "form-label"
              f.collection_select :card_set_id, CardSet.order(:name), :id, :name, { include_blank: "— None —" }, class: "form-input"
            end
            div(class: "form-actions deck-form-actions") do
              f.submit "Update Card", class: "btn btn-primary"
              link_to "Cancel", helpers.admin_card_path(@card), class: "btn btn-secondary"
            end
          end
        end
      end
    end
  end
end
