module Decks
  # One printing of a card on the owner's page: a sub-row of an expanded Decks::FingerprintRow, or
  # — `row_key` and `show_name` given — a row of its own in the set view, where each section is a
  # set and a printing is the natural unit.
  #
  # ⇄ moves one copy *into* this printing from the deck's printing holding the most proxies
  # (FingerprintStates.build has the rule), named in its tooltip, so splitting 3× MEG 114 into
  # 1× PAL 172 + 2× MEG 114 is one click.
  #
  # A set-view row is where its printing changes, as the printing picker was: it expands, like a
  # type-view row, onto the card's owned printings outside the deck, then "Other printings"
  # (`others`, as Decks::FingerprintRow draws it). Every ⇄ in that expansion moves from the row's
  # own printing (`source`), not by FingerprintStates' rule: the member opened this printing's row
  # to change this printing, and with two printings in the deck the rule could name the other one.
  class PrintingRow < OwnerRow
    def initialize(printing:, state:, deck:, group: :type, row_key: nil, show_name: false, source: nil,
                   others: :lazy)
      @printing = printing
      @state = state
      @deck = deck
      @group = group
      @row_key = row_key
      @show_name = show_name
      @source = source
      @others = others
    end

    # A sub-row carries no `data-row-key`: deck_rows_controller.js replaces the whole card's row
    # around it, and must not mistake it for a row of its own.
    def view_template
      li(class: "deck-printing-row", data: (@row_key ? { row_key: @row_key, fingerprint_key: @state.key } : nil)) do
        deck_line(card, item: in_deck?) do
          quantity_stepper(@printing)
          span(class: "deck-card-name") { card.name } if @show_name
          span(class: "deck-card-set") { set_label(card) }
          printings_toggle if expandable?
          owned_note if @printing.group == :owned
          move_button if move_source
          allocation_controls(@printing) if physical? && in_deck?
        end
        expansion if expandable?
      end
    end

    private

    def card = @printing.card

    def move_source = @source || @printing.move_from

    # A row of its own with somewhere to go: the in-deck printings are rows of their own already.
    def expandable? = @row_key && @state.printings.any? { |printing| printing.group != :deck }

    def printings_toggle
      disclosure_button(all_printings_label(@state.printings.size), controls: RowMarkup.printings_id(@row_key),
                        css_class: "deck-printings-toggle")
    end

    def expansion
      ul(class: "deck-printing-list", id: RowMarkup.printings_id(@row_key), hidden: true) do
        @state.printings.select { |printing| printing.group == :owned }.each do |printing|
          render PrintingRow.new(printing: printing, state: @state, deck: @deck, group: @group, source: card)
        end
        other_printings(@state, id_key: @row_key, card: card, lazy: @others == :lazy, source: card)
      end
    end

    # Only on a printing the member owns and the deck does not play: on an in-deck printing "free"
    # would count the copies this very deck holds (true, and unreadable — its real/proxy label says
    # it better), and on any other printing it would read "0 owned · 0 free".
    def owned_note
      span(class: "deck-printing-owned") { "#{@printing.owned} owned · #{@printing.available} free" }
    end

    def in_deck? = @printing.group == :deck

    def move_button
      source = move_source
      label = "Move one copy here from #{set_label(source)}"

      write_button("⇄", class: "deck-printing-move", title: label, aria: { label: label },
                   focus_key: "move-#{card.id}",
                   url: move_api_deck_card_path(@deck, card, group: group_param), method: "POST",
                   body: { move: { from_card_id: source.id } }, failure: "Couldn't move the copy")
    end
  end
end
