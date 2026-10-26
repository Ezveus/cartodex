module Decks
  # What the owner's two rows — a whole card (Decks::FingerprintRow) and one printing of it
  # (Decks::PrintingRow) — are built from: the quantity stepper, the real/proxy stepper and the
  # write buttons inside them.
  #
  # Every button carries the request it sends as Stimulus action params, and is disabled here when
  # the step is impossible: deck_rows_controller.js sends it and applies the answer, and computes
  # no quantity, no bound and no order of its own. A bound the browser kept is what left the real
  # + refusing silently after a quantity + until a reload.
  class OwnerRow < ApplicationComponent
    include RowMarkup

    # The component a row of Decks::Layout is drawn with: a type-view row is a whole card, a
    # set-view row one printing of it, named since no row above it names the card. `others` is
    # Decks::FingerprintRow's: the page leaves the other printings to be fetched, a write's answer
    # renders them.
    def self.for(row, deck:, group:, others: :lazy)
      if row.printing
        PrintingRow.new(printing: row.printing, state: row.state, deck: deck, group: group,
                        row_key: row.key, show_name: true, others: others)
      else
        FingerprintRow.new(state: row.state, deck: deck, group: group, others: others)
      end
    end

    private

    def physical? = @deck.physical?

    # The answer to a write carries rows in the view the page is showing, so every URL says which.
    def group_param = (@group == :set ? "set" : nil)

    def card_url(card) = api_deck_card_path(@deck, card, group: group_param)

    def write_button(text, focus_key:, url:, method:, failure:, body: nil, disabled: false, **attributes)
      data = {
        action: "deck-rows#write", focus_key: focus_key,
        deck_rows_url_param: url, deck_rows_method_param: method, deck_rows_failure_param: failure
      }
      data[:deck_rows_body_param] = body.to_json if body

      button(type: "button", disabled: disabled, data: data, **attributes) { text }
    end

    # The steppers send a step rather than the count the page shows, so a stale tab cannot send a
    # "−" that the server reads as an increase; the server resolves it against the stored row.
    def quantity_stepper(printing)
      card = printing.card
      quantity = printing.quantity

      div(class: "deck-card-qty-controls") do
        quantity_button("-", "qty-minus", card, -1, disabled: quantity.zero?)
        span(class: "deck-card-qty") { quantity.to_s }
        quantity_button("+", "qty-plus", card, 1)
      end
    end

    def quantity_button(text, focus, card, delta, disabled: false)
      write_button(text, class: "qty-btn", focus_key: "#{focus}-#{card.id}", url: card_url(card), method: "PATCH",
                   body: { deck_card: { quantity_delta: delta } }, failure: "Couldn't change the number of copies",
                   disabled: disabled)
    end

    # Real/proxy split and its stepper, bounded 0..max_owned, then the two things the split can
    # call for: a copy to add to the collection, and the over-allocation marker.
    def allocation_controls(printing)
      card = printing.card
      owned_copies = printing.owned_copies

      div(class: "deck-card-alloc") do
        real_button("−", "real-minus", card, -1, disabled: owned_copies.zero?)
        span(class: "deck-card-alloc-label") { alloc_label(owned_copies, printing.proxies) }
        real_button("+", "real-plus", card, 1, disabled: owned_copies >= printing.max_owned)
        collect_button(card) if printing.can_add_to_collection
        over_allocated_marker if printing.over_allocated
      end
    end

    def real_button(text, focus, card, delta, disabled:)
      write_button(text, class: "qty-btn", focus_key: "#{focus}-#{card.id}", url: card_url(card), method: "PATCH",
                   body: { deck_card: { owned_copies_delta: delta } }, failure: "Couldn't change the real copies",
                   disabled: disabled)
    end

    def collect_button(card)
      write_button("+ add to my collection and use it here", class: "deck-card-collect",
                   focus_key: "collect-#{card.id}",
                   url: collection_copy_api_deck_card_path(@deck, card, group: group_param), method: "POST",
                   failure: "Couldn't add the copy to your collection")
    end

    def over_allocated_marker
      span(class: "deck-card-warning badge badge-warning") { "⚠ over-allocated" }
    end

    def alloc_label(owned_copies, proxies) = "#{owned_copies} real · #{proxies} proxy"

    # "Other printings (N)": the card's printings neither played nor owned, at the end of an
    # expansion — `lazy`, its count and the request deck_rows_controller.js sends on its first open
    # (`data-deck-rows-pending` marks the list still to fetch); otherwise rendered whole. The count
    # needs no query of its own: FingerprintStates has read every printing already. `card` names
    # the list on the endpoint and, with `source`, is the printing every ⇄ in it moves from.
    def other_printings(state, id_key:, card:, lazy:, source: nil)
      count = OtherPrintingRows.printings(state).size
      return if count.zero?

      fetch = {
        action: "deck-rows#others",
        deck_rows_url_param: other_printings_api_deck_card_path(@deck, card, group: group_param),
        deck_rows_failure_param: "Couldn't load the other printings"
      }
      li(class: "deck-printing-others") do
        disclosure_button("Other printings (#{count})", controls: RowMarkup.others_id(id_key),
                          css_class: "deck-printings-others-toggle", fetch: (fetch if lazy))
        ul(class: "deck-printing-list", id: RowMarkup.others_id(id_key), hidden: true,
           data: (lazy ? { deck_rows_pending: true } : nil)) do
          render OtherPrintingRows.new(state: state, deck: @deck, group: @group, source: source) unless lazy
        end
      end
    end
  end
end
