module Decks
  # One in-deck printing in the image view: its art and a copy count, nothing to click but the
  # preview. Read-only on both pages.
  #
  # The frame is a `.deck-card-item` with the preview URL and a `.deck-card-qty`, because that is
  # what deck_image_export_controller.js reads document-wide — with the grid on screen there are no
  # rows to read. The count is the bare number and the "×" is drawn by CSS: the export runs
  # `parseInt` on the text, and `parseInt("×4")` is NaN, which it drops.
  #
  # The art comes straight from `cards.image_url`, as /cards and the collection grid load it, not
  # through CardsController#image: that proxy is rate-limited per address for visitors, and a page
  # of 26 tiles would spend their budget. The preview it opens on click uses the proxy, as rows do.
  class CardTile < ApplicationComponent
    include RowMarkup

    def initialize(printing:, name:)
      @printing = printing
      @name = name
    end

    def view_template
      card = @printing.card
      li(class: "deck-card-tile") do
        deck_line(card, item: true, css_class: "deck-card-tile-frame") do
          if card.image_url.present?
            # The count is in the alt: the badge's bare number reads as nothing to a screen reader.
            img(src: card.image_url, alt: "#{@name} (#{set_label(card)}), #{copies}", loading: "lazy",
                class: "deck-card-tile-image")
          else
            div(class: "deck-card-tile-placeholder") do
              span(class: "deck-card-name") { @name }
              span(class: "deck-card-set") { set_label(card) }
            end
          end
          span(class: "deck-card-qty") { @printing.quantity.to_s }
        end
      end
    end

    private

    def copies = @printing.quantity == 1 ? "1 copy" : "#{@printing.quantity} copies"
  end
end
