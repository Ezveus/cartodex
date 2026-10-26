module Decks
  # One section of a deck page (a Decks::Layout::Section), its rows drawn by the block. Rendered
  # without a block it is the section's empty shell, which is what a write's answer hands the page
  # when the row it places needs a section the page does not hold yet.
  #
  # The counts sit in `[data-section-total]`, `[data-section-unique]` and `[data-section-noun]`,
  # which deck_rows_controller.js rewrites after every write; a group's children follow its h2 and
  # a section's rows are its direct `ul.deck-card-list`, which is how that controller finds them.
  class DeckSection < ApplicationComponent
    def initialize(section:)
      @section = section
    end

    def view_template(&rows)
      case @section.kind
      when :group
        div(class: "deck-section-group", data: { section_key: @section.key }) do
          h2 { @section.label }
          rows&.call
        end
      when :subtype
        div(class: "deck-section deck-subsection", data: { section_key: @section.key }) do
          h3 { counts_heading }
          ul(class: "deck-card-list") { rows&.call }
        end
      when :set
        div(class: "deck-section deck-set-section", data: { section_key: @section.key, set_code: set_code }) do
          h2 do
            plain "#{@section.label} · "
            span(data: { section_total: true }) { @section.total.to_s }
            plain " "
            span(data: { section_noun: true }) { @section.noun }
          end
          ul(class: "deck-card-list") { rows&.call }
        end
      else
        div(class: "deck-section", data: { section_key: @section.key }) do
          h2 { counts_heading }
          ul(class: "deck-card-list") { rows&.call }
        end
      end
    end

    private

    def counts_heading
      plain "#{@section.label} ("
      span(data: { section_total: true }) { @section.total.to_s }
      plain " — "
      span(data: { section_unique: true }) { @section.unique.to_s }
      plain " unique)"
    end

    # The code Decks::SetGroups grouped the section on, read back off its first printing: a linked
    # set's own code, else the code the cards carry — the same for every card of the section,
    # since an unlinked card joins a linked set only under that set's code.
    #
    # Through the deck card, whose card the caller preloaded with its set: the printing state's
    # own card comes from Decks::FingerprintStates' catalogue read, which does not preload it, so
    # reading `card_set` there costs a query per section.
    def set_code
      printing = @section.rows.first&.printing
      return unless printing

      card = printing.deck_card&.card || printing.card

      card.card_set&.code || card.set_name.presence || Decks::SetGroups::UNKNOWN_CODE
    end
  end
end
