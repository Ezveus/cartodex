module Decks
  class DeckCardItem < ApplicationComponent
    def initialize(deck_card:, deck_key:, physical: false, max_owned: 0, over_allocated: false, swappable: false)
      @deck_card = deck_card
      @deck_key = deck_key
      @physical = physical
      @max_owned = max_owned
      @over_allocated = over_allocated
      @swappable = swappable
    end

    def view_template
      li(
        class: "deck-card-item",
        data: {
          card_preview_url: card.image_url.present? ? image_card_path(card) : nil,
          card_preview_card_id: card.id,
          action: "mouseenter->card-preview#show click->card-preview#open",
          controller: "deck-card-quantity",
          deck_card_quantity_deck_key_value: @deck_key,
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
        printing_line
        allocation_controls if @physical
      end
    end

    private

    def card = @deck_card.card

    def set_label = "#{card.set_name} #{card.set_number}"

    # A card appears at most once per deck, so its id is unique on the page. The picker rewrites
    # this id along with the rest of the row when the swap lands.
    def menu_id = "printing-picker-menu-#{card.id}"

    # The set/number line doubles as the printing picker's trigger — but only where there is
    # another printing to switch to, so a card the database holds once reads as plain text.
    # The menu is filled in by the controller from the API, since what it lists depends on the
    # user's collection and on this deck.
    def printing_line
      return span(class: "deck-card-set") { set_label } unless @swappable

      div(
        class: "deck-card-printing",
        data: {
          controller: "printing-picker",
          printing_picker_deck_key_value: @deck_key,
          printing_picker_card_id_value: card.id,
          action: "click@document->printing-picker#closeOnOutsideClick keydown->printing-picker#navigate"
        }
      ) do
        button(
          type: "button",
          class: "deck-card-set deck-card-set-swap",
          aria: { label: "Change printing", expanded: "false", haspopup: "true", controls: menu_id },
          data: { action: "printing-picker#toggle", printing_picker_target: "trigger" }
        ) { "#{set_label} ▾" }
        ul(
          id: menu_id, class: "printing-picker-menu", hidden: true, role: "menu",
          data: { printing_picker_target: "menu" }
        )
      end
    end

    # Real/proxy split, a stepper to adjust owned_copies (bounded 0..max_owned),
    # and an over-allocation marker. Physical decks only.
    def allocation_controls
      div(
        class: "deck-card-alloc",
        data: {
          controller: "deck-card-owned-copies",
          deck_card_owned_copies_deck_key_value: @deck_key,
          deck_card_owned_copies_card_id_value: card.id,
          deck_card_owned_copies_owned_value: @deck_card.owned_copies,
          deck_card_owned_copies_max_value: @max_owned
        }
      ) do
        button(class: "qty-btn", data: { action: "deck-card-owned-copies#decrement" }) { "−" }
        span(class: "deck-card-alloc-label", data: { deck_card_owned_copies_target: "label" }) { alloc_label }
        button(class: "qty-btn", data: { action: "deck-card-owned-copies#increment" }) { "+" }
        # Always rendered: a printing swap moves the marker on or off this row without a reload,
        # so the picker needs something to toggle rather than something to invent.
        span(class: "deck-card-warning badge badge-warning", hidden: !@over_allocated) { "⚠ over-allocated" }
      end
    end

    def alloc_label
      "#{@deck_card.owned_copies} real · #{@deck_card.proxies} proxy"
    end
  end
end
