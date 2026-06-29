require "test_helper"

module Decks
  class ComparatorTest < ActiveSupport::TestCase
    setup do
      @user = users(:one)
      @deck_a = @user.decks.create!(name: "A")
      @deck_b = @user.decks.create!(name: "B")
    end

    test "groups cards by type with per-deck quantities, subtotals and totals" do
      @deck_a.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)
      @deck_a.deck_cards.create!(card: cards(:trainer_card), quantity: 4)
      @deck_b.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 1)
      @deck_b.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 3)

      result = Decks::Comparator.call([ @deck_a.reload, @deck_b.reload ])

      assert_equal %w[Pokémon Trainer Energy], result[:groups].map { |g| g[:type] }

      pokemon = result[:groups].find { |g| g[:type] == "Pokémon" }
      row = pokemon[:rows].first
      assert_equal "Teal Mask Ogerpon ex", row[:name]
      assert_equal 2, row[:quantities][@deck_a.id]
      assert_equal 1, row[:quantities][@deck_b.id]
      assert row[:differ]
      assert_equal [ 2, 1 ], pokemon[:subtotals]

      assert_equal [ 6, 4 ], result[:totals]
    end

    test "merges prints that share a fingerprint into one row" do
      @deck_a.deck_cards.create!(card: cards(:budew_pre), quantity: 2)
      @deck_a.deck_cards.create!(card: cards(:budew_asc), quantity: 1)
      @deck_b.deck_cards.create!(card: cards(:budew_pre), quantity: 3)

      result = Decks::Comparator.call([ @deck_a.reload, @deck_b.reload ])
      pokemon = result[:groups].find { |g| g[:type] == "Pokémon" }

      assert_equal 1, pokemon[:rows].size
      row = pokemon[:rows].first
      assert_equal 3, row[:quantities][@deck_a.id]
      assert_equal 3, row[:quantities][@deck_b.id]
      assert_not row[:differ]
    end

    test "keeps prints with different fingerprints in separate rows" do
      @deck_a.deck_cards.create!(card: cards(:froakie_cri), quantity: 2)
      @deck_b.deck_cards.create!(card: cards(:froakie_twm), quantity: 3)

      result = Decks::Comparator.call([ @deck_a.reload, @deck_b.reload ])
      pokemon = result[:groups].find { |g| g[:type] == "Pokémon" }

      assert_equal 2, pokemon[:rows].size
      assert_equal %w[Froakie Froakie], pokemon[:rows].map { |row| row[:name] }

      cri_row = pokemon[:rows].find { |row| row[:card] == cards(:froakie_cri) }
      twm_row = pokemon[:rows].find { |row| row[:card] == cards(:froakie_twm) }

      assert_equal 2, cri_row[:quantities][@deck_a.id]
      assert_equal 0, cri_row[:quantities][@deck_b.id]
      assert_equal 3, twm_row[:quantities][@deck_b.id]
    end

    test "exposes a representative card on each row for linking" do
      @deck_a.deck_cards.create!(card: cards(:budew_pre), quantity: 1)
      @deck_b.deck_cards.create!(card: cards(:budew_asc), quantity: 1)

      result = Decks::Comparator.call([ @deck_a.reload, @deck_b.reload ])
      row = result[:groups].find { |g| g[:type] == "Pokémon" }[:rows].first

      assert_kind_of Card, row[:card]
      assert_equal "Budew", row[:card].name
    end
  end
end
