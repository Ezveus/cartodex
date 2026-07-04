module Decks
  class DeckCardItem < ApplicationComponent
    def initialize(deck_card:, deck_id:, physical: false, max_owned: 0, over_allocated: false)
      @deck_card = deck_card
      @deck_id = deck_id
      @physical = physical
      @max_owned = max_owned
      @over_allocated = over_allocated
    end

    def view_template
      li(
        class: "deck-card-item",
        data: {
          card_preview_url: card.image_url.present? ? image_card_path(card) : nil,
          card_preview_card_id: card.id,
          action: "mouseenter->card-preview#show click->card-preview#open",
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
        allocation_controls if @physical
      end
    end

    private

    def card = @deck_card.card

    # Real/proxy split, a stepper to adjust owned_copies (bounded 0..max_owned),
    # and an over-allocation marker. Physical decks only.
    def allocation_controls
      div(
        class: "deck-card-alloc",
        data: {
          controller: "deck-card-owned-copies",
          deck_card_owned_copies_deck_id_value: @deck_id,
          deck_card_owned_copies_card_id_value: card.id,
          deck_card_owned_copies_owned_value: @deck_card.owned_copies,
          deck_card_owned_copies_max_value: @max_owned
        }
      ) do
        button(class: "qty-btn", data: { action: "deck-card-owned-copies#decrement" }) { "−" }
        span(class: "deck-card-alloc-label", data: { deck_card_owned_copies_target: "label" }) { alloc_label }
        button(class: "qty-btn", data: { action: "deck-card-owned-copies#increment" }) { "+" }
        span(class: "deck-card-warning badge badge-warning") { "⚠ over-allocated" } if @over_allocated
      end
    end

    def alloc_label
      "#{@deck_card.owned_copies} real · #{@deck_card.proxies} proxy"
    end
  end
end
