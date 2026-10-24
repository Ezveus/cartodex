require "test_helper"

module Decks
  class FingerprintStatesTest < ActiveSupport::TestCase
    setup do
      # budew_pre (PRE 4, no imported set) and budew_asc (ASC, 2025-11-07) share "budew_shared".
      @user = users(:one)
      @pre = cards(:budew_pre)
      @asc = cards(:budew_asc)
      @deck = @user.decks.create!(name: "Physical", physical: true, standard_pool: standard_pools(:twm_por))
    end

    # Catalogue order for this fingerprint: POR (2026-01-16), ASC, TWM (2024-05-24), PRE (undated).
    def reprint(set:, set_name:, set_number:)
      card = Card.create!(
        name: @pre.name, card_type: "Pokémon", hp: @pre.hp, type_symbol: @pre.type_symbol,
        retreat_cost: @pre.retreat_cost, stage: @pre.stage,
        card_set: set, set_name: set_name, set_number: set_number, rarity: "Common"
      )
      card.update_column(:fingerprint, @pre.fingerprint)
      card
    end

    def states(deck = @deck)
      FingerprintStates.call(user: @user, deck: Deck.includes(deck_cards: :card).find(deck.id))
    end

    def budew(deck = @deck) = states(deck).fetch("budew_shared")

    def printing(state, card) = state.printings.find { |p| p.card.id == card.id }

    test "one state per fingerprint the deck holds, keyed on Card#fingerprint_key" do
      @deck.deck_cards.create!(card: @pre, quantity: 1)
      @deck.deck_cards.create!(card: @asc, quantity: 2)
      @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)
      @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 1)

      result = states

      assert_equal [ "budew_shared", "honedge_fp", "card:#{cards(:trainer_card).id}" ].sort, result.keys.sort
      unfingerprinted = result.fetch("card:#{cards(:trainer_card).id}")
      assert_equal [ cards(:trainer_card) ], unfingerprinted.printings.map(&:card)
      assert unfingerprinted.single?
      assert_not unfingerprinted.reprinted?
    end

    test "printings run in the deck, then owned, then the rest, each in catalogue order" do
      por = reprint(set: card_sets(:por), set_name: "POR", set_number: "12")
      twm = reprint(set: card_sets(:twm), set_name: "TWM", set_number: "9")
      @deck.deck_cards.create!(card: @pre, quantity: 1)
      @deck.deck_cards.create!(card: @asc, quantity: 2)
      @user.collections.create!(card: twm, quantity: 1)

      state = budew

      assert_equal [ @asc, @pre, twm, por ].map(&:id), state.printings.map { |p| p.card.id }
      assert_equal %i[deck deck owned other], state.printings.map(&:group)
      assert_equal [ @asc, @pre ].map(&:id), state.in_deck.map { |p| p.card.id }
      assert_equal 3, state.quantity
      assert_not state.single?
      assert state.reprinted?
    end

    test "a printing owned at 0 copies is not in the owned group" do
      reprint(set: card_sets(:por), set_name: "POR", set_number: "12")
      @deck.deck_cards.create!(card: @asc, quantity: 1)

      assert_equal :other, printing(budew, @pre).group, "budew_pre_one holds 0 copies"
    end

    test "a tie on copies moves from the newer set" do
      por = reprint(set: card_sets(:por), set_name: "POR", set_number: "12")
      @deck.deck_cards.create!(card: @pre, quantity: 2)
      @deck.deck_cards.create!(card: @asc, quantity: 2)

      state = budew

      assert_equal @asc, printing(state, por).move_from
      assert_equal @pre, printing(state, @asc).move_from, "a printing never moves from itself"
      assert_equal @asc, printing(state, @pre).move_from
      assert_equal @asc, state.display_card
    end

    test "move_from is the in-deck printing with the most copies, and nil when there is none" do
      @deck.deck_cards.create!(card: @pre, quantity: 3)

      state = budew

      assert_equal @pre, printing(state, @asc).move_from
      assert_nil printing(state, @pre).move_from
      assert_equal @pre, state.display_card
    end

    test "allocation fields on a physical deck" do
      # ASC: 3 owned, 1 backed by another deck, so 2 are this deck's to claim and it backs 1.
      @user.collections.find_by!(card: @asc).update!(quantity: 3)
      @deck.deck_cards.create!(card: @asc, quantity: 3, owned_copies: 1)
      other = @user.decks.create!(name: "Other", physical: true, standard_pool: standard_pools(:twm_por))
      other.deck_cards.create!(card: @asc, quantity: 1, owned_copies: 1)
      # PRE: 1 owned, backed here; one proxy and nothing free.
      @user.collections.find_by!(card: @pre).update!(quantity: 1)
      @deck.deck_cards.create!(card: @pre, quantity: 2, owned_copies: 1)

      state = budew
      asc = printing(state, @asc)
      pre = printing(state, @pre)

      assert_equal [ 3, 1, 2 ], [ asc.quantity, asc.owned_copies, asc.proxies ]
      assert_equal [ 3, 2 ], [ asc.owned, asc.available ]
      assert_equal 2, asc.max_owned
      assert_not asc.over_allocated
      assert_not asc.can_add_to_collection, "a free copy remains, so the real + is the way"

      assert_equal [ 1, 1 ], [ pre.owned, pre.available ]
      assert_equal 1, pre.max_owned
      assert pre.can_add_to_collection, "a proxy and no free copy"

      assert_equal [ 5, 2, 3 ], [ state.quantity, state.owned_copies, state.proxies ]
      assert_not state.over_allocated?
    end

    test "over_allocated when the printing's committed reals exceed what is owned" do
      @user.collections.find_by!(card: @asc).update!(quantity: 1)
      @deck.deck_cards.create!(card: @asc, quantity: 1, owned_copies: 1)
      other = @user.decks.create!(name: "Other", physical: true, standard_pool: standard_pools(:twm_por))
      other.deck_cards.create!(card: @asc, quantity: 1, owned_copies: 1)

      state = budew

      assert printing(state, @asc).over_allocated
      assert state.over_allocated?
    end

    # One more copy only brings the collection back towards what other decks already back, so
    # Decks::CollectionCopyAdder refuses it: the button must not be offered.
    test "an over-allocated printing with a proxy and no free copy does not offer the collection add" do
      @user.collections.find_by!(card: @asc).update!(quantity: 1)
      other = @user.decks.create!(name: "Other", physical: true, standard_pool: standard_pools(:twm_por))
      other.deck_cards.create!(card: @asc, quantity: 2, owned_copies: 2)
      @deck.deck_cards.create!(card: @asc, quantity: 2, owned_copies: 0)

      asc = printing(budew, @asc)

      assert asc.over_allocated
      assert_equal 0, asc.available
      assert_not asc.can_add_to_collection
      assert_raises(ArgumentError) { CollectionCopyAdder.call(deck: @deck, card: @asc) }
    end

    test "a non-physical deck carries owned but nothing that would allocate" do
      deck = @user.decks.create!(name: "Live", physical: false, standard_pool: standard_pools(:twm_por))
      deck.deck_cards.create!(card: @asc, quantity: 2)
      @user.collections.find_by!(card: @pre).update!(quantity: 3)

      state = budew(deck)
      asc = printing(state, @asc)
      pre = printing(state, @pre)

      assert_equal :owned, pre.group
      assert_equal 3, pre.owned
      assert_equal [ 0, 2 ], [ asc.owned_copies, asc.proxies ]
      assert_equal 0, asc.max_owned
      assert_not asc.can_add_to_collection
      assert_not asc.over_allocated
    end

    test "as_json carries the payload's fingerprint shape" do
      @deck.deck_cards.create!(card: @asc, quantity: 2)

      json = budew.as_json

      assert_equal %w[key name quantity owned_copies proxies printings].sort, json.keys.map(&:to_s).sort
      entry = json[:printings].find { |p| p[:card_id] == @pre.id }
      assert_equal %w[card_id set_name set_number group quantity owned_copies proxies owned available max_owned
                      over_allocated move_from_card_id can_add_to_collection].sort, entry.keys.map(&:to_s).sort
      assert_equal "other", entry[:group]
      assert_equal @asc.id, entry[:move_from_card_id]
      assert_equal "budew_shared", json[:key]
    end

    # The owner's page renders every fingerprint of the deck from this, so its cost must not grow
    # with the deck: one read of every printing, then Availability's grouped three.
    test "costs four queries whatever the deck holds" do
      reprint(set: card_sets(:por), set_name: "POR", set_number: "12")
      @deck.deck_cards.create!(card: @asc, quantity: 2)
      small = Deck.includes(deck_cards: :card).find(@deck.id)
      small_count = count_queries { FingerprintStates.call(user: @user, deck: small) }

      [ cards(:honedge), cards(:doublade), cards(:trainer_card), cards(:froakie_cri) ].each do |card|
        @deck.deck_cards.create!(card: card, quantity: 1)
      end
      large = Deck.includes(deck_cards: :card).find(@deck.id)
      large_count = count_queries { FingerprintStates.call(user: @user, deck: large) }

      assert_equal 4, small_count
      assert_equal small_count, large_count
    end

    # The public page may not read the collection nor card_sets: deck_only works off the deck's own
    # rows alone, so it runs no query and orders by what the rows carry.
    test "deck_only orders by set code then number and runs no query" do
      rows = [
        [ "CRZ", "GG10", 1 ], [ "CRZ", "3", 1 ], [ "ASC", "5", 2 ], [ "CRZ", "GG2", 2 ]
      ].each_with_index.map do |(code, number, quantity), i|
        ::DeckCard.new(quantity: quantity, owned_copies: 0,
                       card: Card.new(id: 1000 + i, name: "Lucario", card_type: "Pokémon",
                                      set_name: code, set_number: number, fingerprint: "lucario"))
      end

      result = nil
      assert_equal 0, count_queries { result = FingerprintStates.deck_only(rows) }

      state = result.fetch("lucario")
      assert_equal [ "ASC 5", "CRZ 3", "CRZ GG2", "CRZ GG10" ],
                   state.printings.map { |p| "#{p.card.set_name} #{p.card.set_number}" }
      assert_equal 6, state.quantity
      assert state.printings.all? { |p| p.group == :deck }
      assert state.printings.all? { |p| p.owned.zero? && p.available.zero? && p.max_owned.zero? }
      assert state.printings.none? { |p| p.over_allocated || p.can_add_to_collection || p.move_from }
      assert_equal "ASC", state.display_card.set_name, "ASC 5 and CRZ GG2 tie at 2; ASC comes first"
      assert state.reprinted?
    end
  end
end
