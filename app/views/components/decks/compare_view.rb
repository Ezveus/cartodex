module Decks
  class CompareView < ApplicationComponent
    def initialize(comparison:)
      @decks = comparison[:decks]
      @groups = comparison[:groups]
      @totals = comparison[:totals]
    end

    def view_template
      div(class: "deck-compare-container") do
        div(class: "deck-compare-header") do
          h1 { "Compare Decks" }
          link_to "Back to Decks", decks_path, class: "btn btn-secondary"
        end

        div(class: "deck-compare-table-wrap") do
          table(class: "deck-compare-table") do
            head
            @groups.each { |group| group_body(group) }
            foot
          end
        end
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
      tr(class: row[:differ] ? "is-diff" : nil) do
        td(class: "deck-compare-card-col") { row[:name] }
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
  end
end
