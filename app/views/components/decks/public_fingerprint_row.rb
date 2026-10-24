module Decks
  # One card of a shared deck, read-only: its total and, when the deck plays it in several
  # printings, each printing's count behind a disclosure. No stepper, no real/proxy, no collection
  # figure — this component contains none of them, which is what makes the public page unable to
  # leak one. Built from Decks::FingerprintStates.deck_only, whose printings are the deck's own.
  class PublicFingerprintRow < ApplicationComponent
    include RowMarkup

    def initialize(state:)
      @state = state
    end

    def view_template
      li(class: "deck-fingerprint") do
        @state.single? ? single_line : summary_line
      end
    end

    private

    def single_line
      printing = @state.printings.first

      deck_line(printing.card, item: true) do
        count(printing.quantity)
        span(class: "deck-card-name") { @state.name }
        span(class: "deck-card-set") { set_label(printing.card) }
      end
    end

    def summary_line
      deck_line(@state.display_card, item: false) do
        div(class: "deck-card-qty-controls") { span(class: "deck-card-total") { @state.quantity.to_s } }
        span(class: "deck-card-name") { @state.name }
        disclosure_button(printings_label(@state.printings.size), controls: RowMarkup.printings_id(@state.key),
                          css_class: "deck-printings-toggle")
      end

      ul(class: "deck-printing-list", id: RowMarkup.printings_id(@state.key), hidden: true) do
        @state.printings.each do |printing|
          li(class: "deck-printing-row") do
            deck_line(printing.card, item: true) do
              count(printing.quantity)
              span(class: "deck-card-set") { set_label(printing.card) }
            end
          end
        end
      end
    end

    def count(quantity)
      div(class: "deck-card-qty-controls") { span(class: "deck-card-qty") { quantity.to_s } }
    end
  end
end
