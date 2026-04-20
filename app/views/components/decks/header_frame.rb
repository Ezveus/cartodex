module Decks
  class HeaderFrame < ApplicationComponent
    include Phlex::Rails::Helpers::TurboFrameTag

    FRAME_ID = "deck-header".freeze

    def initialize(deck:, editing: false)
      @deck = deck
      @editing = editing
    end

    def view_template
      turbo_frame_tag(FRAME_ID) do
        if @editing
          edit_form
        else
          display
        end
      end
    end

    private

    def display
      div do
        h1 { @deck.name }
        p(class: "deck-show-description") { @deck.description } if @deck.description.present?
      end
    end

    def edit_form
      form_with(model: @deck, class: "deck-header-form") do |f|
        render Ui::FormErrors.new(resource: @deck)

        f.text_field :name, class: "form-input deck-header-name-input", autofocus: true, placeholder: "Deck name"
        f.text_area :description, class: "form-input deck-header-description-input", rows: 2, placeholder: "Description (optional)"

        div(class: "deck-header-form-actions") do
          f.submit "Save", class: "btn btn-primary btn-sm"
          link_to "Cancel", helpers.deck_path(@deck), class: "btn btn-secondary btn-sm", data: { turbo_frame: FRAME_ID }
        end
      end
    end
  end
end
