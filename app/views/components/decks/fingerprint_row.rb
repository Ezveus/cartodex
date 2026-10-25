module Decks
  # One card of the owner's deck in the type view, whatever the number of printings it is played
  # in (a Decks::FingerprintStates::State).
  #
  # Held in one printing, the line is that printing, steppers included. Held in several, the line
  # sums them — the total and "N real · M proxy" — and the steppers live in the sub-rows. Either
  # way the row expands, when the catalogue holds another printing, into the printings in the deck,
  # then those the member owns at 0 copies, then "Other printings (N)" for the rest — neither played
  # nor owned; a single printing is not repeated there, since the line already is it.
  #
  # `others` says how that last list is drawn. The page renders it `:lazy` — its count and the
  # request that fetches it, which deck_rows_controller.js sends the first time it is opened — so a
  # card held in a dozen printings does not cost a dozen hidden sub-rows on every row of the page.
  # The owned ones are rendered with the page either way: they are the printings the member can
  # actually move a real copy to, so the expansion shows them without a second click.
  # A write's answer renders it `:rendered`: that row replaces one whose list the member may have
  # opened, and deck_rows_controller.js re-opens it, so it has to come back whole and current rather
  # than empty or as the stale copy the first fetch returned.
  class FingerprintRow < OwnerRow
    # `expanded` is the styleguide's: the page always renders a row closed.
    def initialize(state:, deck:, group: :type, expanded: false, others: :lazy)
      @state = state
      @deck = deck
      @group = group
      @expanded = expanded
      @others = others
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
        others
      end
    end

    # The count needs no query of its own: FingerprintStates has read every printing already, for
    # ⇄ and "All printings (M)". `data-deck-rows-pending` marks a list still to be fetched.
    def others
      count = OtherPrintingRows.printings(@state).size
      return if count.zero?

      lazy = @others == :lazy
      li(class: "deck-printing-others") do
        disclosure_button("Other printings (#{count})", controls: RowMarkup.others_id(@state.key),
                          css_class: "deck-printings-others-toggle", fetch: (fetch_params if lazy))
        ul(class: "deck-printing-list", id: RowMarkup.others_id(@state.key), hidden: true,
           data: (lazy ? { deck_rows_pending: true } : nil)) do
          render OtherPrintingRows.new(state: @state, deck: @deck) unless lazy
        end
      end
    end

    # Any printing of the card names its list; the display card is one the deck plays.
    def fetch_params
      {
        action: "deck-rows#others",
        deck_rows_url_param: other_printings_api_deck_card_path(@deck, @state.display_card),
        deck_rows_failure_param: "Couldn't load the other printings"
      }
    end

    def sub_row(printing)
      render PrintingRow.new(printing: printing, state: @state, deck: @deck, group: @group)
    end
  end
end
