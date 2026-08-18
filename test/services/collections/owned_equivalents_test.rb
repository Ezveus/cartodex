require "test_helper"

module Collections
  class OwnedEquivalentsTest < ActiveSupport::TestCase
    setup do
      # budew_pre and budew_asc share fingerprint "budew_shared" in fixtures.
      @user = users(:one)
      @asc = cards(:budew_asc)
      @pre = cards(:budew_pre)
      @user.collections.find_or_create_by!(card: @pre).update!(quantity: 2)
    end

    test "lists owned printings sharing the fingerprint" do
      result = Collections::OwnedEquivalents.call(user: @user, card: @asc)
      card_ids = result.map { |e| e[:card_id] }

      assert_includes card_ids, @pre.id
      pre_entry = result.find { |e| e[:card_id] == @pre.id }
      assert_equal 2, pre_entry[:owned]
      assert_equal 2, pre_entry[:available]
    end

    test "excludes the queried card when excluding_card: true" do
      @user.collections.find_or_create_by!(card: @asc).update!(quantity: 1)

      result = Collections::OwnedEquivalents.call(user: @user, card: @asc, excluding_card: true)

      assert_not_includes result.map { |e| e[:card_id] }, @asc.id
      assert_includes result.map { |e| e[:card_id] }, @pre.id
    end

    test "is empty when no equivalent is owned" do
      other_user = users(:two)
      assert_empty Collections::OwnedEquivalents.call(user: other_user, card: @asc)
    end

    test "excludes printings owned at quantity zero" do
      # Setup bumps budew_pre to quantity 2 for every test; reset it back to the
      # fixture-defined 0 (matching budew_asc_one) to prove zero-quantity rows
      # are excluded, not just unbumped ones.
      @user.collections.find_by!(card: @pre).update!(quantity: 0)

      result = Collections::OwnedEquivalents.call(user: @user, card: @asc)

      assert_empty result
    end

    # One Availability lookup per equivalent printing — an N+1 over however many
    # printings of the card the user owns.
    test "issues a constant number of queries regardless of how many printings are owned" do
      one = count_queries { Collections::OwnedEquivalents.call(user: @user, card: @pre) }

      # Equivalence is Card#fingerprint. The fixtures carry a literal value
      # ("budew_shared") because fixtures bypass the before_save callback that
      # normally computes it, so a created reprint gets a real digest instead and
      # would not match. Force it: this test is about query counts, not about how
      # fingerprints are derived.
      3.times do |i|
        reprint = Card.create!(
          name: @pre.name, card_type: "Pokémon", hp: @pre.hp, type_symbol: @pre.type_symbol,
          retreat_cost: @pre.retreat_cost, stage: @pre.stage,
          set_name: "RPR", set_number: "#{100 + i}", rarity: "Common"
        )
        reprint.update_column(:fingerprint, @pre.fingerprint)
        @user.collections.create!(card: reprint, quantity: 1)
      end

      many = count_queries { Collections::OwnedEquivalents.call(user: @user, card: @pre) }

      assert_equal 4, Collections::OwnedEquivalents.call(user: @user, card: @pre).size,
        "sanity: the service must now see four owned printings"
      assert_equal one, many, "query count grew with the number of owned printings: #{one} -> #{many}"
    end
    # One row stopped meaning one printing the moment a printing could be owned
    # in several variants. Listing it twice, each entry claiming a fraction of
    # the total, is the failure #89 asks this service to stop having.
    test "reports one entry per printing, summing its variants" do
      # setup leaves budew_pre at quantity 2 in the unknown variant.
      @user.collections.create!(card: @pre, quantity: 3, language: "fr", finish: "reverse_holo")

      result = Collections::OwnedEquivalents.call(user: @user, card: @asc)
      entries = result.select { |e| e[:card_id] == @pre.id }

      assert_equal 1, entries.size, "a printing owned in two variants must be listed once"
      assert_equal 5, entries.first[:owned], "owned is the printing's total across its variants"
      assert_equal 5, entries.first[:available]
    end

    test "a printing owned only in a non-default variant is still listed" do
      @user.collections.find_by!(card: @pre).update!(quantity: 0)
      @user.collections.create!(card: @pre, quantity: 2, language: "fr")

      result = Collections::OwnedEquivalents.call(user: @user, card: @asc)

      entry = result.find { |e| e[:card_id] == @pre.id }
      assert_not_nil entry
      assert_equal 2, entry[:owned]
    end
  end
end
