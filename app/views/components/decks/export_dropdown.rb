module Decks
  # The deck page's Export menu, on the owner's page and on the public one. The four public
  # items were identical in both to the character; the fifth, the tournament PDF, is the
  # owner's alone because it reads one of their tournament profiles (DeckPolicy#tournament_pdf?
  # is owner-only, so a visitor's request for it 404s).
  #
  # One keyword rather than two components, for the same reason as Decks::DeckCard's
  # `public_listing:`: what the visitor may not have is one decision, and the next caller
  # cannot get half of it wrong.
  class ExportDropdown < ApplicationComponent
    def initialize(deck:, tournament_pdf: false)
      @deck = deck
      @tournament_pdf = tournament_pdf
    end

    def view_template
      div(class: "dropdown", data: { controller: "dropdown" }) do
        button(class: "btn btn-secondary btn-sm", data: { action: "dropdown#toggle" }) { "Export ▾" }
        div(class: "dropdown-menu", data: { dropdown_target: "menu" }) do
          clipboard_item("Copy for TCG Live", export_deck_path(@deck))
          clipboard_item("Copy as Cardmarket wishlist", export_deck_path(@deck, style: "cardmarket"))
          image_item("Copy as image", "copy")
          image_item("Download as image", "download")
          # Opens Decks::TournamentPdfModal, which only the owner's page renders.
          item("Download as tournament PDF", action: "tournament-pdf#open") if @tournament_pdf
        end
      end
    end

    private

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
