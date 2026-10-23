module Decks
  # The owner's deck page grouped by the set each card was printed in rather than by card type.
  # Sections come out already ordered, and so do the cards inside them, so the order is one
  # decision held here and the component only renders it. It reads the deck cards it is handed
  # (with `card: :card_set` preloaded) and runs no query of its own.
  #
  # Linked sets first, newest release first; an undated set after every dated one. Then the cards
  # with no `card_set` — imported before their set, or orphaned by `dependent: :nullify` — grouped
  # by `cards.set_name`, alphabetically. An unlinked card whose code is that of a set the deck
  # already shows joins that set, so one set never reads as two sections.
  class SetGroups < ApplicationService
    Section = Struct.new(:card_set, :code, :deck_cards) do
      def label = card_set ? "#{card_set.name} (#{code})" : code

      # Copies, the figure the type view's headings print first.
      def copies = deck_cards.sum(&:quantity)
    end

    UNKNOWN_CODE = "Unknown set".freeze

    # `2 < 10 < 100`, and a `GG1`-style number after the purely numeric ones of its set and in its
    # own numeric order (`GG2 < GG10`): (alphabetic prefix, integer part, rest). A number with no
    # digit at all sorts by its text, after everything with one.
    def self.number_key(set_number)
      number = set_number.to_s
      match = number.match(/\A(\D*)(\d+)(.*)\z/)
      match ? [ 0, match[1], match[2].to_i, match[3] ] : [ 1, number, 0, "" ]
    end

    def initialize(deck_cards)
      @deck_cards = deck_cards
    end

    def call
      linked, unlinked = @deck_cards.partition { |dc| dc.card.card_set }
      sets_by_code = linked.map { |dc| dc.card.card_set }.uniq.index_by(&:code)

      folded, orphans = unlinked.partition { |dc| sets_by_code.key?(dc.card.set_name) }
      by_set = (linked + folded).group_by { |dc| dc.card.card_set || sets_by_code.fetch(dc.card.set_name) }

      linked_sections = by_set.sort_by { |set, _| set_order(set) }.map do |set, group|
        Section.new(set, set.code, sorted(group))
      end
      orphan_sections = orphans.group_by { |dc| dc.card.set_name.presence || UNKNOWN_CODE }
                               .sort_by { |code, _| [ code == UNKNOWN_CODE ? 1 : 0, code ] }
                               .map { |code, group| Section.new(nil, code, sorted(group)) }

      linked_sections + orphan_sections
    end

    private

    # Descending release date by negating its Julian day; nil sorts after every date. The code and
    # then the id make the order total.
    def set_order(set)
      date = set.release_date
      [ date ? 0 : 1, date ? -date.jd : 0, set.code.to_s, set.id.to_i ]
    end

    def sorted(group) = group.sort_by { |dc| self.class.number_key(dc.card.set_number) }
  end
end
