module Decks
  # The deck page's Export menu, on the owner's page and on the public one. The four public
  # items are identical in both; two more are the owner's alone, and a visitor's request for
  # either 404s: the tournament PDF, which reads one of their tournament profiles
  # (DeckPolicy#tournament_pdf?), and the Cardmarket wishlist netted of the copies the deck
  # already backs (#208), which reads their collection (DeckPolicy#cardmarket_missing?).
  #
  # One keyword rather than two components, for the same reason as Decks::DeckCard's
  # `public_listing:`: what the visitor may not have is one decision, and the next caller
  # cannot get half of it wrong.
  #
  # The menu sits outside Decks::HeaderFrame, so toggling `physical` in place leaves it as it was
  # rendered. That is harmless because the server decides the count at request time: the
  # missing-copies style answers a deck that is no longer physical with its whole count.
  class ExportDropdown < ApplicationComponent
    def initialize(deck:, owner: false)
      @deck = deck
      @owner = owner
    end

    def view_template
      div(class: "dropdown", data: { controller: "dropdown" }) do
        button(class: "btn btn-secondary btn-sm", data: { action: "dropdown#toggle" }) { "Export ▾" }
        div(class: "dropdown-menu", data: { dropdown_target: "menu" }) do
          clipboard_item("Copy for TCG Live", export_deck_path(@deck))
          cardmarket_items
          image_item("Copy as image", "copy")
          image_item("Download as image", "download")
          # Opens Decks::TournamentPdfModal, which only the owner's page renders.
          item("Download as tournament PDF", action: "tournament-pdf#open") if @owner
        end
      end
    end

    private

    # Two items only where the two would differ: a non-physical deck backs no copy, so its
    # "missing copies" would be the whole deck under another name.
    def cardmarket_items
      whole = export_deck_path(@deck, style: "cardmarket")
      if @owner && @deck.physical?
        clipboard_item("Copy as Cardmarket wishlist (missing copies)", export_deck_path(@deck, style: "cardmarket_missing"))
        clipboard_item("Copy as Cardmarket wishlist (whole deck)", whole)
      else
        clipboard_item("Copy as Cardmarket wishlist", whole)
      end
    end

    def clipboard_item(label, url)
      item(label, controller: "clipboard", clipboard_url_value: url, action: "clipboard#copy")
    end

    def image_item(label, method)
      item(label, controller: "deck-image-export", action: "deck-image-export##{method}")
    end

    def item(label, **data)
      button(class: "dropdown-item", data: data) { label }
    end
  end
end
