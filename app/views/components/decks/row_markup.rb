module Decks
  # The markup the owner's rows and the public ones share: the line a row is drawn on, the
  # disclosure that expands it, and the ids that disclosure points at.
  #
  # The line is the contract deck_image_export_controller.js reads — `.deck-card-item` marks exactly
  # one printing in the deck and carries `data-card-preview-url` and a `.deck-card-qty`, so the
  # image lists each printing once. A line summing several printings is not an item.
  module RowMarkup
    PREVIEW_ACTION = "mouseenter->card-preview#show click->card-preview#open".freeze

    # A fingerprint is a SHA-256 hex digest or `card:<id>`; the colon is legal in an id but needs
    # escaping in every selector, so it is folded away.
    def self.printings_id(key) = "deck-printings-#{key.tr(':', '-')}"
    def self.others_id(key) = "deck-printings-others-#{key.tr(':', '-')}"

    private

    def deck_line(card, item:, &content)
      div(
        class: [ "deck-card-line", ("deck-card-item" if item) ].compact.join(" "),
        data: {
          card_preview_url: card.image_url.present? ? image_card_path(card) : nil,
          card_preview_card_id: card.id,
          action: PREVIEW_ACTION
        },
        &content
      )
    end

    # The state lives in the markup alone, for disclosure_controller.js and for
    # deck_rows_controller.js, which re-opens what was open after it swaps a row.
    def disclosure_button(text, controls:, css_class:, expanded: false)
      button(
        type: "button", class: css_class,
        aria: { expanded: expanded.to_s, controls: controls },
        data: { action: "disclosure#toggle" }
      ) { text }
    end

    def set_label(card) = "#{card.set_name} #{card.set_number}"

    def printings_label(count) = "#{count} printings"
  end
end
