module Decks
  class DeckCardItem < ApplicationComponent
    def initialize(deck_card:, deck_id:)
      @deck_card = deck_card
      @deck_id = deck_id
    end

    def view_template
      li(
        class: "deck-card-item",
        data: {
          card_preview_url: card.image_url,
          card_preview_card_id: card.id,
          action: "mouseenter->card-preview#show",
          controller: "deck-card-quantity",
          deck_card_quantity_deck_id_value: @deck_id,
          deck_card_quantity_card_id_value: card.id,
          deck_card_quantity_quantity_value: @deck_card.quantity
        }
      ) do
        div(class: "deck-card-qty-controls") do
          button(class: "qty-btn", data: { action: "deck-card-quantity#decrement" }) { "-" }
          span(class: "deck-card-qty") { @deck_card.quantity.to_s }
          button(class: "qty-btn", data: { action: "deck-card-quantity#increment" }) { "+" }
        end
        span(class: "deck-card-name") { card.name }
        span(class: "deck-card-set") { "#{card.set_name} #{card.set_number}" }
      end
    end

    private

    def card = @deck_card.card
  end
end
