module Decks
  class CompareView < ApplicationComponent
    def initialize(comparison:)
      @decks = comparison[:decks]
      @groups = comparison[:groups]
      @totals = comparison[:totals]
    end

    def view_template
      div(class: "deck-compare-container", data: { controller: "card-preview" }) do
        div(class: "deck-compare-header") do
          h1 { "Compare Decks" }
          link_to "Back to Decks", decks_path, class: "btn btn-secondary"
        end

        div(class: "deck-compare-content") do
          div(class: "deck-compare-table-wrap") do
            table(class: "deck-compare-table") do
              head
              @groups.each { |group| group_body(group) }
              foot
            end
          end

          preview_section
        end

        card_preview_modal
      end
    end

    private

    def head
      thead do
        tr do
          th(class: "deck-compare-card-col") { "Card" }
          @decks.each do |deck|
            th { link_to deck.name, deck_path(deck) }
          end
        end
      end
    end

    def group_body(group)
      tbody do
        tr(class: "deck-compare-group-header") do
          th(colspan: @decks.size + 1) { group[:type] }
        end

        group[:rows].each { |row| card_row(row) }

        tr(class: "deck-compare-subtotal") do
          td { "Subtotal" }
          group[:subtotals].each { |value| td { value.to_s } }
        end
      end
    end

    def card_row(row)
      card = row[:card]
      tr(
        class: [ "deck-compare-card-row", ("is-diff" if row[:differ]) ].compact,
        data: {
          card_preview_url: card.image_url.present? ? image_card_path(card) : nil,
          card_preview_card_id: card.id,
          action: "mouseenter->card-preview#show click->card-preview#open"
        }
      ) do
        td(class: "deck-compare-card-col") do
          link_to(card_path(card), class: "deck-compare-card-link") do
            span(class: "deck-compare-card-name") { card.name }
            span(class: "deck-compare-card-set") { "#{card.set_name} #{card.set_number}" }
          end
        end
        @decks.each { |deck| quantity_cell(row[:quantities][deck.id]) }
      end
    end

    def quantity_cell(quantity)
      if quantity.to_i.positive?
        td { quantity.to_s }
      else
        td(class: "is-absent") { "—" }
      end
    end

    def foot
      tfoot do
        tr(class: "deck-compare-total") do
          td { "Total" }
          @totals.each { |value| td { value.to_s } }
        end
      end
    end

    # The pane sits inside .deck-compare-content and the dialog outside it — hence two
    # render calls from two places, and two components rather than one.
    def preview_section
      render Ui::CardPreview.new(wrapper_class: "deck-compare-preview")
    end

    def card_preview_modal
      render Ui::CardPreviewModal.new
    end
  end
end
