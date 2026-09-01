require "test_helper"

module Cards
  class PrintingsTest < ActiveSupport::TestCase
    setup do
      # budew_pre and budew_asc share fingerprint "budew_shared" in fixtures.
      @user = users(:one)
      @asc = cards(:budew_asc)
      @pre = cards(:budew_pre)
    end

    test "lists every printing sharing the fingerprint, owned or not" do
      result = Cards::Printings.call(user: @user, card: @asc)

      assert_equal [ @asc.id, @pre.id ].sort, result.map { |p| p[:card_id] }.sort
      assert result.all? { |p| p[:owned].zero? }, "the user owns none of them"
    end

    test "annotates each printing with owned and available counts" do
      @user.collections.find_by!(card: @pre).update!(quantity: 2)
      other = @user.decks.create!(name: "Other", physical: true, standard_pool: standard_pools(:twm_por))
      other.deck_cards.create!(card: @pre, quantity: 1, owned_copies: 1)

      entry = Cards::Printings.call(user: @user, card: @asc).find { |p| p[:card_id] == @pre.id }

      assert_equal 2, entry[:owned]
      assert_equal 1, entry[:available]
      assert_equal "PRE", entry[:set_name]
      assert_equal "4", entry[:set_number]
    end

    test "marks the queried printing as the current one" do
      result = Cards::Printings.call(user: @user, card: @asc)

      assert result.find { |p| p[:card_id] == @asc.id }[:current]
      assert_not result.find { |p| p[:card_id] == @pre.id }[:current]
    end

    test "orders by set release date, newest first, undated printings last" do
      por = reprint(set: card_sets(:por), set_name: "POR", set_number: "12")

      result = Cards::Printings.call(user: @user, card: @asc)

      # POR 2026-01-16, then ASC 2025-11-07, then budew_pre, whose set is not imported.
      assert_equal [ por.id, @asc.id, @pre.id ], result.map { |p| p[:card_id] }
    end

    test "returns the card alone when it has no fingerprint" do
      trainer = cards(:trainer_card)
      assert_nil trainer.fingerprint

      result = Cards::Printings.call(user: @user, card: trainer)

      assert_equal [ trainer.id ], result.map { |p| p[:card_id] }
    end

    test "reports how many copies of each printing the deck already holds" do
      deck = @user.decks.create!(name: "Physical", physical: true, standard_pool: standard_pools(:twm_por))
      deck.deck_cards.create!(card: @asc, quantity: 3)
      deck.deck_cards.create!(card: @pre, quantity: 1)

      result = Cards::Printings.call(user: @user, card: @asc, deck: deck)

      assert_equal 3, result.find { |p| p[:card_id] == @asc.id }[:in_deck]
      assert_equal 1, result.find { |p| p[:card_id] == @pre.id }[:in_deck]
    end

    test "projects the real/proxy split a swap to each printing would produce" do
      @user.collections.find_by!(card: @asc).update!(quantity: 2)
      deck = @user.decks.create!(name: "Physical", physical: true, standard_pool: standard_pools(:twm_por))
      deck.deck_cards.create!(card: @asc, quantity: 3, owned_copies: 2)

      result = Cards::Printings.call(user: @user, card: @asc, deck: deck)

      # Nothing is owned of the PRE printing, so the whole row would become proxies.
      pre = result.find { |p| p[:card_id] == @pre.id }
      assert_equal 0, pre[:real_after]
      assert_equal 3, pre[:proxies_after]

      # The current printing reports today's split, not a re-derivation of it.
      asc = result.find { |p| p[:card_id] == @asc.id }
      assert_equal 2, asc[:real_after]
      assert_equal 1, asc[:proxies_after]
    end

    test "folds an existing row for the target printing into the projection" do
      @user.collections.find_by!(card: @pre).update!(quantity: 4)
      deck = @user.decks.create!(name: "Physical", physical: true, standard_pool: standard_pools(:twm_por))
      deck.deck_cards.create!(card: @asc, quantity: 2)
      deck.deck_cards.create!(card: @pre, quantity: 1, owned_copies: 1)

      pre = Cards::Printings.call(user: @user, card: @asc, deck: deck).find { |p| p[:card_id] == @pre.id }

      # The merged row totals 3, and the collection can back all three.
      assert_equal 3, pre[:real_after]
      assert_equal 0, pre[:proxies_after]
    end

    test "caps the projection at what the collection leaves available to this deck" do
      @user.collections.find_by!(card: @pre).update!(quantity: 3)
      other = @user.decks.create!(name: "Other", physical: true, standard_pool: standard_pools(:twm_por))
      other.deck_cards.create!(card: @pre, quantity: 2, owned_copies: 2)
      deck = @user.decks.create!(name: "Physical", physical: true, standard_pool: standard_pools(:twm_por))
      deck.deck_cards.create!(card: @asc, quantity: 4)

      pre = Cards::Printings.call(user: @user, card: @asc, deck: deck).find { |p| p[:card_id] == @pre.id }

      assert_equal 1, pre[:real_after]
      assert_equal 3, pre[:proxies_after]
    end

    test "leaves the projection out for a non-physical deck" do
      deck = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))
      deck.deck_cards.create!(card: @asc, quantity: 2)

      result = Cards::Printings.call(user: @user, card: @asc, deck: deck)

      assert result.all? { |p| p[:real_after].nil? && p[:proxies_after].nil? },
        "a deck that consumes no collection has no real/proxy split to project"
    end

    test "leaves the projection out when no deck is given" do
      result = Cards::Printings.call(user: @user, card: @asc)

      assert result.all? { |p| p[:real_after].nil? && p[:in_deck].zero? }
    end

    test "issues a constant number of queries regardless of how many printings exist" do
      deck = @user.decks.create!(name: "Physical", physical: true, standard_pool: standard_pools(:twm_por))
      deck.deck_cards.create!(card: @asc, quantity: 2)

      few = count_queries { Cards::Printings.call(user: @user, card: @asc, deck: deck) }
      3.times { |i| reprint(set: card_sets(:twm), set_name: "TWM", set_number: "#{100 + i}") }
      many = count_queries { Cards::Printings.call(user: @user, card: @asc, deck: deck) }

      assert_equal 5, Cards::Printings.call(user: @user, card: @asc, deck: deck).size,
        "sanity: the service must now see five printings"
      assert_equal few, many, "query count grew with the number of printings: #{few} -> #{many}"
    end

    test "swappable_card_ids keeps only the cards that have another printing" do
      ids = Cards::Printings.swappable_card_ids([ @asc, cards(:froakie_cri), cards(:trainer_card) ])

      assert_equal [ @asc.id ].to_set, ids
    end

    test "swappable_card_ids costs one query whatever the card count" do
      cards = [ @asc, @pre, cards(:froakie_cri), cards(:froakie_twm) ]

      assert_equal 1, count_queries { Cards::Printings.swappable_card_ids(cards) }
    end

    private

    # Another printing of Budew. Fixtures bypass the callback that computes a
    # fingerprint, so their literal "budew_shared" has to be forced onto a real
    # record — a created card gets a genuine digest, which would not match.
    def reprint(set:, set_name:, set_number:)
      card = Card.create!(
        name: @pre.name, card_type: "Pokémon", hp: @pre.hp, type_symbol: @pre.type_symbol,
        retreat_cost: @pre.retreat_cost, stage: @pre.stage,
        card_set: set, set_name: set_name, set_number: set_number, rarity: "Common"
      )
      card.update_column(:fingerprint, @pre.fingerprint)
      card
    end
  end
end
