module Decks
  # A shared deck, as anybody but its owner sees it: the decklist and the exports.
  #
  # A separate file rather than a flag on Decks::ShowView, which carries ten owner-only
  # affordances (inline editing, card search, result logging, quantity and allocation steppers,
  # ⇄, the tournament PDF, the actions dropdown…). Guarding each of them would put ten
  # conditions in the app's largest component, and one forgotten condition is a collection
  # leak to a stranger. This view cannot leak what it does not contain.
  class PublicShowView < ApplicationComponent
    # `can_duplicate` is passed by the ERB from DeckPolicy#duplicate?, the `can_record` pattern of
    # tournaments/show: this view stays unaware of sessions. A visitor gets no button — sign-in is
    # the navbar's to offer.
    #
    # `compare_candidates` are the reader's own decks, for "Compare with…": empty for a visitor,
    # who has none, and the menu is then not rendered at all.
    def initialize(deck:, can_duplicate: false, compare_candidates: [])
      @deck = deck
      @can_duplicate = can_duplicate
      @compare_candidates = compare_candidates
    end

    def view_template
      compare = Decks::CompareBar.controller_data
      div(class: "deck-show-container",
          data: compare.merge(controller: "card-preview disclosure #{compare[:controller]}")) do
        header_section
        stats_section
        div(class: "deck-show-content") do
          main_section
          preview_section
        end
        render Decks::CompareBar.new
      end
    end

    private

    # `.deck-show-header h1` is what the image export names the file from.
    def header_section
      div(class: "deck-show-header") do
        div do
          h1 { @deck.name }
          render Decks::PublicBadges.new(deck: @deck, linked: true)
          p(class: "deck-show-description") { @deck.description } if @deck.description.present?
        end
      end
      # Not `owner:`, so neither the tournament PDF (it reads one of the owner's tournament profiles)
      # nor the Cardmarket wishlist netted of the owner's backed copies. The odds are a function
      # of the decklist alone, which this page already renders in full, so they are offered here on
      # exactly the rule that let the reader in — DeckPolicy#show?.
      nav(class: "deck-actions-bar") do
        render Decks::ExportDropdown.new(deck: @deck)
        link_to "Odds", odds_deck_path(@deck), class: "btn btn-secondary btn-sm"
        compare_with_dropdown if @compare_candidates.any?
        compare_toggle
        copy_button if @can_duplicate
      end
    end

    # The one-click case: this deck against one of the reader's own. Plain links, so the address
    # is the same one the compare bar builds, with this deck in the first column.
    def compare_with_dropdown
      div(class: "dropdown", data: { controller: "dropdown" }) do
        button(type: "button", class: "btn btn-secondary btn-sm", data: { action: "dropdown#toggle" }) { "Compare with… ▾" }
        div(class: "dropdown-menu dropdown-menu--scroll", data: { dropdown_target: "menu" }) do
          @compare_candidates.each do |mine|
            link_to mine.name, compare_decks_path(ids: [ @deck.key, mine.key ]), class: "dropdown-item"
          end
        end
      end
    end

    # The many-decks case: adds this deck to the selection the listings' compare bar carries, for
    # a visitor as much as for a member. The controller writes its label on connect.
    def compare_toggle
      button(
        type: "button", class: "btn btn-secondary btn-sm deck-compare-toggle-deck", aria_pressed: "false",
        data: { deck_compare_target: "toggle", action: "deck-compare#toggleDeck", deck_key: @deck.key, deck_name: @deck.name }
      ) { "Add to comparison" }
    end

    # Lands on the reader's new deck, a full page — outside any frame, so no `_top` is needed.
    def copy_button
      button_to "Copy to my decks", duplicate_deck_path(@deck), method: :post, class: "btn btn-primary btn-sm"
    end

    # The card count only. No wins, losses, draws or timeouts: the record stays private.
    def stats_section
      div(class: "deck-show-stats") do
        render Ui::Stat.new(value: @deck.deck_cards.sum(&:quantity), label: "cards")
      end
    end

    # The same sections and the same row classes as Decks::ShowView — the stylesheet styles them
    # and the image export reads them — placed by the same Decks::Layout, so the public page reads
    # like the owner's, Trainers split by subtype and a card in two printings one row. The rows are
    # Decks::PublicFingerprintRow's, which hold no control, and the states are `deck_only`: built
    # from the deck's own cards, they read neither the collection nor `card_sets` and cost no query.
    def main_section
      div(class: "deck-show-main") do
        states = Decks::FingerprintStates.deck_only(@deck.deck_cards)
        render Decks::DeckSections.new(
          sections: Decks::Layout.call(states: states, group: :type),
          row: ->(row) { Decks::PublicFingerprintRow.new(state: row.state) }
        )
      end
    end

    # Copied verbatim from Decks::ShowView, targets included. Above the 768px breakpoint the
    # hover pane is what fills; below it, card_preview_controller.js checks
    # window.innerWidth <= 768 and uses the <dialog> instead — so both halves have to be here
    # or the mobile side of the preview silently does nothing.
    def preview_section
      render Ui::CardPreview.new(wrapper_class: "deck-show-preview")
      render Ui::CardPreviewModal.new
    end
  end
end
