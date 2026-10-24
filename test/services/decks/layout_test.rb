require "test_helper"

module Decks
  # Unsaved records only, as in SetGroupsTest: Layout reads the states it is handed and runs no
  # query, and the cases need more subtypes and sets than the fixtures hold.
  class LayoutTest < ActiveSupport::TestCase
    def row(name, type: "Pokémon", subtype: nil, fingerprint: name.parameterize, set_name: "POR",
            set_number: "1", card_set: nil, quantity: 1)
      @next_id = (@next_id || 0) + 1
      ::DeckCard.new(quantity: quantity, owned_copies: 0,
                     card: Card.new(id: @next_id, name: name, card_type: type, subtype: subtype,
                                    fingerprint: fingerprint, set_name: set_name, set_number: set_number,
                                    card_set: card_set))
    end

    def states(rows) = FingerprintStates.deck_only(rows)

    test "the type view runs Pokémon, the Trainer group and its subtypes, then Energy" do
      rows = [
        row("Psychic Energy", type: "Energy", subtype: "Basic Energy"),
        row("Mystery Trainer", type: "Trainer", subtype: "Technical Machine"),
        row("Artazon", type: "Trainer", subtype: "Stadium"),
        row("Bravery Charm", type: "Trainer", subtype: "Pokémon Tool"),
        row("Maximum Belt", type: "Trainer", subtype: "Tool"),
        row("Ultra Ball", type: "Trainer", subtype: "Item"),
        row("Boss's Orders", type: "Trainer", subtype: "Supporter"),
        row("Budew")
      ]

      sections = Layout.call(states: states(rows), group: :type)

      assert_equal %w[pokemon trainer trainer-supporter trainer-item trainer-tool trainer-stadium trainer-other energy],
                   sections.map(&:key)
      assert_equal %i[type group subtype subtype subtype subtype subtype type], sections.map(&:kind)
      assert_equal [ "Pokémon", "Trainer", "Supporter", "Item", "Tool", "Stadium", "Other", "Energy" ],
                   sections.map(&:label)
      assert_equal [ nil, nil, "trainer", "trainer", "trainer", "trainer", "trainer", nil ], sections.map(&:parent_key)

      group = sections.find { |s| s.key == "trainer" }
      assert_empty group.rows
      assert_nil group.total
      assert_nil group.unique

      tools = sections.find { |s| s.key == "trainer-tool" }
      assert_equal [ "Bravery Charm", "Maximum Belt" ], tools.rows.map { |r| r.state.name },
                   "both spellings of Tool share one section"
    end

    test "only non-empty sections are listed, and no Trainer group without a Trainer" do
      sections = Layout.call(states: states([ row("Budew"), row("Psychic Energy", type: "Energy") ]), group: :type)

      assert_equal %w[pokemon energy], sections.map(&:key)
    end

    test "a type row is one fingerprint, keyed on it, and counts toward unique once" do
      rows = [
        row("Budew", fingerprint: "budew", set_name: "PRE", set_number: "4"),
        row("Budew", fingerprint: "budew", set_name: "ASC", set_number: "16", quantity: 2),
        row("Honedge", fingerprint: "honedge")
      ]

      pokemon = Layout.call(states: states(rows).values, group: :type).first

      assert_equal %w[budew honedge], pokemon.rows.map(&:key)
      assert pokemon.rows.all? { |r| r.printing.nil? }
      assert_equal [ 3, 1 ], pokemon.rows.map(&:quantity)
      assert_equal 4, pokemon.total
      assert_equal 2, pokemon.unique
      assert_nil pokemon.noun
    end

    test "type rows sort by name, then key" do
      rows = [
        row("Zacian", fingerprint: "zz"), row("Budew", fingerprint: "b2"), row("Budew", fingerprint: "b1")
      ]

      pokemon = Layout.call(states: states(rows), group: :type).first

      assert_equal %w[b1 b2 zz], pokemon.rows.map(&:key)
    end

    test "the set view is one row per in-deck printing, keyed on the set or its code" do
      por = CardSet.new(id: 41, code: "POR", name: "Perfect Order", release_date: Date.new(2026, 1, 16))
      rows = [
        row("Budew", fingerprint: "budew", set_name: "PAL", set_number: "4"),
        row("Budew", fingerprint: "budew", set_name: "POR", set_number: "16", card_set: por, quantity: 2),
        row("Honedge", fingerprint: "honedge", set_name: "POR", set_number: "56", card_set: por)
      ]

      sections = Layout.call(states: states(rows), group: :set)

      assert_equal %w[set-41 set-code-pal], sections.map(&:key)
      assert sections.all? { |s| s.kind == :set && s.parent_key.nil? }
      assert_equal [ "Perfect Order (POR)", "PAL" ], sections.map(&:label)

      por_section = sections.first
      assert_equal [ "printing:#{rows[1].card.id}", "printing:#{rows[2].card.id}" ], por_section.rows.map(&:key)
      assert_equal [ 2, 1 ], por_section.rows.map(&:quantity)
      assert_equal rows[1].card, por_section.rows.first.printing.card
      assert_equal "budew", por_section.rows.first.state.key
      assert_equal [ 3, 2, "cards" ], [ por_section.total, por_section.unique, por_section.noun ]
      assert_equal [ 1, "card" ], [ sections.last.total, sections.last.noun ]
    end
  end
end
