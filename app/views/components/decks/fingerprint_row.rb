module Decks
  # One card of the owner's deck in the type view, whatever the number of printings it is played
  # in (a Decks::FingerprintStates::State).
  #
  # Held in one printing, the line is that printing, steppers included. Held in several, the line
  # sums them — the total and "N real · M proxy" — and the steppers live in the sub-rows. Either
  # way the row expands, when the catalogue holds another printing, into the printings in the deck,
  # then those the member owns at 0 copies, then "Other printings (N)" for the rest; a single
  # printing is not repeated there, since the line already is it.
  #
  # Every printing is rendered with the page, the others hidden, rather than fetched when opened:
  # one render path and no endpoint of its own, for a few hundred bytes a printing.
  class FingerprintRow < OwnerRow
    # `expanded` is the styleguide's: the page always renders a row closed.
    def initialize(state:, deck:, group: :type, expanded: false)
      @state = state
      @deck = deck
      @group = group
      @expanded = expanded
    end

    def view_template
      li(class: "deck-fingerprint", data: { row_key: @state.key, fingerprint_key: @state.key }) do
        @state.single? ? single_line : summary_line
        printing_list if @state.reprinted?
      end
    end

    private

    def single_line
      printing = @state.in_deck.first

      deck_line(printing.card, item: true) do
        quantity_stepper(printing)
        span(class: "deck-card-name") { @state.name }
        span(class: "deck-card-set") { set_label(printing.card) }
        printings_toggle if @state.reprinted?
        allocation_controls(printing) if physical?
      end
    end

    # Previews the printing with the most copies (State#display_card). The total is
    # `.deck-card-total`, never `.deck-card-qty`, so the image export does not count it again. Where
    # a single line names its printing, this one says how many the deck plays.
    def summary_line
      deck_line(@state.display_card, item: false) do
        div(class: "deck-card-qty-controls") { span(class: "deck-card-total") { @state.quantity.to_s } }
        span(class: "deck-card-name") { @state.name }
        span(class: "deck-card-set") { deck_printings_label(@state.in_deck.size) }
        printings_toggle
        allocation_summary if physical?
      end
    end

    def printings_toggle
      disclosure_button(all_printings_label(@state.printings.size), controls: RowMarkup.printings_id(@state.key),
                        css_class: "deck-printings-toggle", expanded: @expanded)
    end

    def allocation_summary
      div(class: "deck-card-alloc deck-card-alloc--summary") do
        span(class: "deck-card-alloc-label") { alloc_label(@state.owned_copies, @state.proxies) }
        over_allocated_marker if @state.over_allocated?
      end
    end

    def printing_list
      by_group = @state.printings.group_by(&:group)
      in_deck = @state.single? ? [] : by_group.fetch(:deck, [])

      ul(class: "deck-printing-list", id: RowMarkup.printings_id(@state.key), hidden: !@expanded) do
        (in_deck + by_group.fetch(:owned, [])).each { |printing| sub_row(printing) }
        others(by_group.fetch(:other, []))
      end
    end

    def others(printings)
      return if printings.empty?

      li(class: "deck-printing-others") do
        disclosure_button("Other printings (#{printings.size})", controls: RowMarkup.others_id(@state.key),
                          css_class: "deck-printings-others-toggle")
        ul(class: "deck-printing-list", id: RowMarkup.others_id(@state.key), hidden: true) do
          printings.each { |printing| sub_row(printing) }
        end
      end
    end

    def sub_row(printing)
      render PrintingRow.new(printing: printing, state: @state, deck: @deck, group: @group)
    end
  end
end
