module Decks
  class NewView < ApplicationComponent
    def initialize(deck:)
      @deck = deck
    end

    def view_template
      div(class: "deck-form-container") do
        h1 { "New Deck" }
        form_with(model: @deck, class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @deck)

          render Ui::FormGroup.new do
            f.label :name, class: "form-label"
            f.text_field :name, class: "form-input", autofocus: true, placeholder: "My Deck"
          end

          render Ui::FormGroup.new do
            f.label :description, class: "form-label"
            f.text_area :description, class: "form-input", rows: 3, placeholder: "Optional description\u2026"
          end

          div(class: "form-actions deck-form-actions") do
            f.submit "Create Deck", class: "btn btn-primary"
            link_to "Cancel", helpers.decks_path, class: "btn btn-secondary"
          end
        end
      end
    end
  end
end
