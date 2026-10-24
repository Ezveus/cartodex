module Decks
  # Where each row of the deck page goes: its sections in page order, and the rows inside each one
  # in order. The page renders it and every write's answer places a row by it, so a row added in
  # place lands exactly where a reload would put it — one ordering, held here, rather than a second
  # copy of it in the browser.
  #
  # Reads the Decks::FingerprintStates it is handed and runs no query of its own; the set view needs
  # the in-deck cards' `card_set` preloaded by the caller.
  class Layout < ApplicationService
    # `cards.subtype` is a free scraped string: Cards::Fetcher#parse_subtype keeps whatever
    # follows "Trainer - " on the page, and that has been "Tool" for every one of the 76 tools in
    # the catalogue while this table only knew "Pokémon Tool" — so every Tool fell through to the
    # "Other" heading. Both spellings map to one label, and the grouping is done on the label
    # rather than on the raw subtype so a deck holding both spellings gets one section rather than
    # two identically titled ones.
    TRAINER_SUBTYPE_LABELS = {
      "Supporter" => "Supporter",
      "Item" => "Item",
      "Tool" => "Tool",
      "Pokémon Tool" => "Tool",
      "Stadium" => "Stadium"
    }.freeze

    OTHER_SUBTYPE = "Other".freeze
    TRAINER_KEY = "trainer".freeze

    # kind: :type (Pokémon, Energy), :group (the Trainer container, which holds no row and prints
    # no count of its own), :subtype (a Trainer subtype, under the group), :set.
    Section = Struct.new(:key, :parent_key, :kind, :label, :rows, keyword_init: true) do
      def total = (rows.sum(&:quantity) unless kind == :group)
      def unique = (rows.size unless kind == :group)

      # Only the set view's heading reads "· 3 cards"; the type view's prints "(N — U unique)".
      def noun
        return unless kind == :set

        total == 1 ? "card" : "cards"
      end
    end

    # A type-view row is a whole card (`printing` nil); a set-view row is one printing of it.
    Row = Struct.new(:key, :state, :printing, keyword_init: true) do
      def quantity = printing ? printing.quantity : state.quantity
    end

    def initialize(states:, group:)
      @states = states.is_a?(Hash) ? states.values : Array(states)
      @group = group
    end

    def call
      @group == :set ? set_sections : type_sections
    end

    private

    def type_sections
      by_type = @states.group_by(&:card_type)

      [
        *type_section("pokemon", "Pokémon", by_type["Pokémon"]),
        *trainer_sections(by_type["Trainer"]),
        *type_section("energy", "Energy", by_type["Energy"])
      ]
    end

    def type_section(key, label, states)
      return [] if states.blank?

      [ Section.new(key: key, parent_key: nil, kind: :type, label: label, rows: type_rows(states)) ]
    end

    # The group, then its subtypes in the table's own order — `uniq` collapsing the two keys that
    # share the Tool label — then whatever subtype the table does not know, as "Other".
    def trainer_sections(states)
      return [] if states.blank?

      by_label = states.group_by { |state| TRAINER_SUBTYPE_LABELS.fetch(state.subtype.to_s, OTHER_SUBTYPE) }
      subtypes = (TRAINER_SUBTYPE_LABELS.values.uniq + [ OTHER_SUBTYPE ]).filter_map do |label|
        next if by_label[label].blank?

        Section.new(key: "#{TRAINER_KEY}-#{label.parameterize}", parent_key: TRAINER_KEY, kind: :subtype,
                    label: label, rows: type_rows(by_label[label]))
      end

      [ Section.new(key: TRAINER_KEY, parent_key: nil, kind: :group, label: "Trainer", rows: []), *subtypes ]
    end

    # The key breaks a tie between two cards sharing a name, so the order never rests on the input.
    def type_rows(states)
      states.sort_by { |state| [ state.name.to_s, state.key ] }
            .map { |state| Row.new(key: state.key, state: state, printing: nil) }
    end

    # Decks::SetGroups orders the sections and the cards inside them; each of its deck cards is
    # mapped back to the printing state it came from, by identity since an unsaved row has no id.
    def set_sections
      owners = {}.compare_by_identity
      @states.each do |state|
        state.in_deck.each { |printing| owners[printing.deck_card] = [ state, printing ] }
      end

      SetGroups.call(owners.keys).map do |section|
        rows = section.deck_cards.map do |deck_card|
          state, printing = owners.fetch(deck_card)
          Row.new(key: "printing:#{printing.card.id}", state: state, printing: printing)
        end
        Section.new(key: set_key(section), parent_key: nil, kind: :set, label: section.label, rows: rows)
      end
    end

    def set_key(section)
      section.card_set ? "set-#{section.card_set.id}" : "set-code-#{section.code.parameterize}"
    end
  end
end
