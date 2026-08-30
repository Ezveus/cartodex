require "test_helper"

class Archetypes::FingerprintSyncTest < ActiveSupport::TestCase
  test "rewrites a pair the member cards have drifted away from" do
    archetype = archetypes(:ogerpon)
    # update_column, not update!: this is precisely the drift a `force: true`
    # rescrape produces — the card moves, the archetype's copy does not.
    #
    # teal_mask_ogerpon_ex is also budew_ogerpon's secondary, so the drift is
    # visible from two rows: both are expected to resync.
    cards(:teal_mask_ogerpon_ex).update_column(:fingerprint, "ogerpon_v2")

    result = Archetypes::FingerprintSync.call

    assert_equal "ogerpon_v2", archetype.reload.primary_fingerprint
    assert_equal "ogerpon_v2", archetypes(:budew_ogerpon).reload.secondary_fingerprint
    assert_equal 2, result.updated
    assert_empty result.collisions
  end

  test "leaves a pair already in step alone" do
    result = Archetypes::FingerprintSync.call

    assert_equal 0, result.updated
  end

  test "reports the archetypes that drift has made duplicates instead of writing them" do
    # budew_ogerpon's primary moves onto ogerpon's fingerprint, so once resynced
    # both archetypes would claim (ogerpon_shared, ""). Neither may be written.
    archetypes(:budew_ogerpon).update_columns(secondary_card_id: nil, secondary_fingerprint: "")
    cards(:budew_pre).update_column(:fingerprint, "ogerpon_shared")

    result = Archetypes::FingerprintSync.call

    assert_equal 0, result.updated
    assert_equal [ archetypes(:budew_ogerpon), archetypes(:ogerpon) ].sort_by(&:id),
      result.collisions.sort_by(&:id)
    assert_equal "budew_shared", archetypes(:budew_ogerpon).reload.primary_fingerprint,
      "a colliding row must be reported, not written"
  end
  # `archetypes.primary_fingerprint` is NOT NULL, so writing a nil through would
  # not report anything — it would abort the run part-way, leaving the rows
  # already written written and the rest untouched. Only a write that bypasses
  # callbacks can produce a card with no fingerprint, and this service is the
  # designated repair tool for exactly that kind of out-of-band state.
  test "reports an archetype whose primary card has no fingerprint instead of dying on it" do
    cards(:budew_pre).update_column(:fingerprint, nil)
    cards(:teal_mask_ogerpon_ex).update_column(:fingerprint, "ogerpon_v2")

    result = Archetypes::FingerprintSync.call

    assert_equal [ archetypes(:budew_ogerpon) ], result.unfingerprinted
    assert_equal "budew_shared", archetypes(:budew_ogerpon).reload.primary_fingerprint,
      "an unfingerprinted row must be reported, not written"
    # The rest of the run still happens: one bad row must not cost the others.
    assert_equal "ogerpon_v2", archetypes(:ogerpon).reload.primary_fingerprint
    assert_equal 1, result.updated
  end
end
