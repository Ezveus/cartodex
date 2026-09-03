module Decks
  # A deck card, read-only. No quantity stepper, no printing picker, no allocation controls —
  # this component contains none of them, which is what makes the public page unable to leak
  # one.
  #
  # The class name, the preview URL and the `.deck-card-qty` element are not decoration:
  # deck_image_export_controller.js reads all three, and the image export is part of what a
  # shared deck offers.
  class PublicDeckCardItem < ApplicationComponent
    def initialize(deck_card:)
      @deck_card = deck_card
    end

    def view_template
      li(
        class: "deck-card-item",
        data: {
          card_preview_url: card.image_url.present? ? image_card_path(card) : nil,
          card_preview_card_id: card.id,
          action: "mouseenter->card-preview#show click->card-preview#open"
        }
      ) do
        div(class: "deck-card-qty-controls") do
          span(class: "deck-card-qty") { @deck_card.quantity.to_s }
        end
        span(class: "deck-card-name") { card.name }
        span(class: "deck-card-set") { "#{card.set_name} #{card.set_number}" }
      end
    end

    private

    def card = @deck_card.card
  end
end
