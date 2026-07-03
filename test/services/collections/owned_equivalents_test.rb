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
  end
end
