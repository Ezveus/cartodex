require "test_helper"

module Decks
  # Unsaved records only: the service reads what it is handed and runs no query, so nothing here
  # needs the database — and four or more distinct sets per case is more than the fixtures hold.
  class SetGroupsTest < ActiveSupport::TestCase
    def set(code, name: "#{code} name", released: nil, id: nil)
      CardSet.new(id: id || code.sum, code: code, name: name, release_date: released)
    end

    def row(set_name, set_number, card_set: nil, quantity: 1)
      ::DeckCard.new(quantity: quantity, card: Card.new(name: "#{set_name} #{set_number}", set_name: set_name,
                                                      set_number: set_number, card_set: card_set))
    end

    def codes(sections) = sections.map(&:code)

    test "sections run newest release first, then undated sets, then unlinked codes alphabetically" do
      old = set("TWM", released: Date.new(2024, 5, 24))
      mid = set("ASC", released: Date.new(2025, 11, 7))
      new_set = set("POR", released: Date.new(2026, 1, 16))
      undated = set("ZZZ")

      # Fed in an order matching none of the expected ones, so a stable sort over the input cannot
      # pass for the rule.
      sections = SetGroups.call([
        row("SVI", "1"), row("TWM", "5", card_set: old), row("ZZZ", "1", card_set: undated),
        row("POR", "3", card_set: new_set), row("MEW", "2"), row("ASC", "9", card_set: mid)
      ])

      assert_equal %w[POR ASC TWM ZZZ MEW SVI], codes(sections)
    end

    test "two undated sets are ordered by code, and the order does not depend on the input" do
      a = set("AAA")
      b = set("BBB")

      assert_equal %w[AAA BBB], codes(SetGroups.call([ row("BBB", "1", card_set: b), row("AAA", "1", card_set: a) ]))
      assert_equal %w[AAA BBB], codes(SetGroups.call([ row("AAA", "1", card_set: a), row("BBB", "1", card_set: b) ]))
    end

    test "cards inside a section run by number, numerically, with GG-style numbers after and in their own numeric order" do
      por = set("POR", released: Date.new(2026, 1, 16))
      numbers = %w[GG10 100 2 GG2 10 1]

      section = SetGroups.call(numbers.map { |n| row("POR", n, card_set: por) }).sole

      assert_equal %w[1 2 10 100 GG2 GG10], section.deck_cards.map { |dc| dc.card.set_number }
    end

    test "unlinked cards are ordered by number too" do
      section = SetGroups.call(%w[10 9].map { |n| row("MEW", n) }).sole

      assert_equal %w[9 10], section.deck_cards.map { |dc| dc.card.set_number }
    end

    test "an unlinked card whose code is a set the deck shows joins that set's section" do
      por = set("POR", released: Date.new(2026, 1, 16))

      sections = SetGroups.call([ row("POR", "30"), row("POR", "4", card_set: por) ])

      assert_equal [ "POR" ], codes(sections)
      assert_same por, sections.sole.card_set
      assert_equal %w[4 30], sections.sole.deck_cards.map { |dc| dc.card.set_number }
    end

    test "the label names the set and its code, or the bare code when the card has no set" do
      sections = SetGroups.call([ row("POR", "1", card_set: set("POR", name: "Perfect Order")), row("MEW", "1") ])

      assert_equal [ "Perfect Order (POR)", "MEW" ], sections.map(&:label)
    end

    test "copies sums quantities, not rows" do
      por = set("POR")

      section = SetGroups.call([ row("POR", "1", card_set: por, quantity: 4), row("POR", "2", card_set: por, quantity: 2) ]).sole

      assert_equal 6, section.copies
    end

    test "a card with no set code at all lands in one trailing section" do
      # "ZZZ" sorts after "Unknown set" alphabetically: the trailing place is a rule, not the alphabet.
      sections = SetGroups.call([ row(nil, "1"), row("ZZZ", "1"), row("", "2") ])

      assert_equal [ "ZZZ", "Unknown set" ], codes(sections)
      assert_equal "Unknown set", sections.last.label
    end

    test "an undated linked set sorts after the dated ones and before every unlinked code, whatever its code" do
      dated = set("POR", released: Date.new(2026, 1, 16))
      undated = set("ZZU")

      sections = SetGroups.call([ row("AAA", "1"), row("ZZU", "1", card_set: undated), row("POR", "1", card_set: dated) ])

      assert_equal %w[POR ZZU AAA], codes(sections)
    end

    test "two sets released the same day are ordered by code, then by id" do
      day = Date.new(2025, 1, 1)
      zza = set("ZZA", released: day, id: 1)
      aab = set("AAB", released: day, id: 2)
      # Codes are unique per region only, so two sets may share one.
      intl = set("XYZ", released: day, id: 3)
      japan = set("XYZ", released: day, id: 4)

      sections = SetGroups.call([ row("ZZA", "1", card_set: zza), row("XYZ", "1", card_set: japan),
                                  row("AAB", "1", card_set: aab), row("XYZ", "2", card_set: intl) ])

      assert_equal %w[AAB XYZ XYZ ZZA], codes(sections)
      assert_equal [ 3, 4 ], sections.select { |s| s.code == "XYZ" }.map { |s| s.card_set.id }
    end

    test "an unlinked card is not folded into a set the deck does not show, even if that set exists" do
      # The twm fixture exists in the database; the service must not look it up.
      sections = nil
      queries = count_queries { sections = SetGroups.call([ row("TWM", "25"), row("POR", "1", card_set: set("POR")) ]) }

      assert_equal [ "POR", "TWM" ], codes(sections)
      assert_nil sections.last.card_set
      assert_equal 0, queries
    end

    test "an unlinked card is not folded when two shown sets of two regions share its code" do
      day = Date.new(2025, 1, 1)
      intl = set("XYZ", name: "Intl Set", released: day, id: 1)
      japan = set("XYZ", name: "Japan Set", released: day - 1, id: 2)

      sections = SetGroups.call([ row("XYZ", "1", card_set: intl), row("XYZ", "2", card_set: japan), row("XYZ", "3") ])

      assert_equal [ [ 1 ], [ 2 ], [ nil ] ], sections.map { |s| [ s.card_set&.id ] }
      assert_equal [ "3" ], sections.last.deck_cards.map { |dc| dc.card.set_number }
    end

    test "number_key orders numbers without digits after the numeric ones and never raises" do
      assert_equal %w[2 10 GG2 SV], %w[SV 10 GG2 2].sort_by { |n| SetGroups.number_key(n) }
      assert_nothing_raised { [ nil, "", "A", "1" ].sort_by { |n| SetGroups.number_key(n) } }
    end

    test "an empty deck has no section" do
      assert_empty SetGroups.call([])
    end
  end
end
