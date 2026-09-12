module Decks
  class CompareView < ApplicationComponent
    def initialize(comparison:, diff_only: false)
      @decks = comparison[:decks]
      @groups = comparison[:groups]
      @totals = comparison[:totals]
      @diff_totals = comparison[:diff_totals]
      @diff_only = diff_only
    end

    def view_template
      # `is-diff-only` is the whole filter: the rows and the groups the decks agree on are
      # hidden in CSS from this one class, so the Stimulus controller only ever moves it —
      # nothing has to be re-queried, and the server can render the filtered state directly.
      div(
        class: [ "deck-compare-container", ("is-diff-only" if @diff_only) ].compact,
        data: {
          controller: "card-preview deck-diff-filter",
          action: "turbo:before-cache@document->deck-diff-filter#reset"
        }
      ) do
        div(class: "deck-compare-header") do
          h1 { "Compare Decks" }
          diff_toggle
          link_to "Back to Decks", decks_path, class: "btn btn-secondary"
        end

        div(class: "deck-compare-content") do
          div(class: "deck-compare-table-wrap") do
            table(class: "deck-compare-table") do
              head
              @groups.each { |group| group_body(group) }
              no_diff_body unless any_difference?
              foot
            end
          end

          preview_section
        end

        card_preview_modal
      end
    end

    private

    # The label wraps the box rather than pointing at it: an id would have to be unique on a
    # page that already renders two card-preview surfaces, and Capybara reads a wrapping label
    # just as well.
    #
    # The hint travels with the box because the parenthesised figure has nowhere else to be
    # explained: the cells carry a `title`, which reaches neither touch nor keyboard, and the
    # header row of the table is deck names.
    def diff_toggle
      div(class: "deck-compare-toggle-group") do
        label(class: "deck-compare-toggle") do
          input(
            type: "checkbox", checked: @diff_only,
            data: {
              action: "change->deck-diff-filter#toggle",
              deck_diff_filter_target: "box"
            }
          )
          span { "Differences only" }
        end

        span(class: "deck-compare-toggle-hint") do
          "In parentheses: copies on rows the decks disagree about."
        end
      end
    end

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
      tbody(class: ("is-uniform" unless group[:differing])) do
        tr(class: "deck-compare-group-header") do
          th(colspan: @decks.size + 1) { group[:type] }
        end

        group[:rows].each { |row| card_row(row) }

        tr(class: "deck-compare-subtotal") do
          td { "Subtotal" }
          group[:subtotals].each_with_index do |value, i|
            count_cell(value, group[:diff_subtotals][i])
          end
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

    # Two numbers, and the second is not a share of the first: the deck's own count, then how
    # many of those copies sit on a row the decks disagree about. Printed whether or not the
    # filter is on, since hiding rows is what the filter does and this is what it cannot say —
    # but dropped at zero, where it repeats what the first number already implies and leaves a
    # column of "(0)" down a page of two close decks.
    def count_cell(total, differing)
      td do
        plain total.to_s

        if differing.positive?
          whitespace
          span(class: "deck-compare-diff-count", title: "Copies on differing rows") { "(#{differing})" }
        end
      end
    end

    def foot
      tfoot do
        tr(class: "deck-compare-total") do
          td { "Total" }
          @totals.each_with_index { |value, i| count_cell(value, @diff_totals[i]) }
        end
      end
    end

    # Filtered, decks that agree on everything leave a table with a head and a foot and nothing
    # between them. Rendered only in that case and shown only while the filter is on, so the
    # unfiltered page never carries it.
    def no_diff_body
      tbody(class: "deck-compare-no-diff") do
        tr do
          td(colspan: @decks.size + 1) { "These decks play the same cards in the same counts." }
        end
      end
    end

    def any_difference?
      @groups.any? { |group| group[:differing] }
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
