require "test_helper"

# The seed is a bootstrap, not the source of truth — bin/docker-entrypoint runs db:seed on every
# boot, so a seed that reasserted its values would revert an admin's correction on each deploy.
# That is the rule db/seeds/standard_pools.rb already follows, and this test is what holds it.
class CardLabelSeedTest < ActiveSupport::TestCase
  def load_seed = load Rails.root.join("db/seeds/card_labels.rb")

  # Counted on the type family rather than on CardLabel.count: this file seeds both families now,
  # and a total would have to be edited every time the role vocabulary grows — which is exactly the
  # edit that would stop this test being about the ace-spec row at all.
  test "it creates the ace-spec label with the token it is imported by" do
    assert_difference "CardLabel.types.count", 1 do
      load_seed
    end

    label = CardLabel.find_by(slug: "ace-spec")

    assert_equal "type", label.family
    assert_equal "is:ace", label.source_query
  end

  test "running it twice creates nothing and rewrites nothing" do
    load_seed
    CardLabel.find_by(slug: "ace-spec").update!(name: "Ace Spec (corrected)", source_query: "is:ace-spec")

    assert_no_difference "CardLabel.count" do
      load_seed
    end

    label = CardLabel.find_by(slug: "ace-spec")

    assert_equal "Ace Spec (corrected)", label.name
    assert_equal "is:ace-spec", label.source_query
  end

  # The role family is seeded, not admin-created — Admin::CardLabelsController refuses `create`
  # on it — so this loop is the only thing that ever writes a role row. A slug present in ROLES
  # and absent from the seed is a role no rule can ever propose.
  test "it seeds one row per role in the vocabulary" do
    load_seed

    assert_equal CardLabel::ROLES.map { |role| role[:slug] }, CardLabel.roles.pluck(:slug)
    assert_equal CardLabel::ROLES.map { |role| role[:name] }, CardLabel.roles.pluck(:name)
  end

  # Same bootstrap rule as the type family above, on the family an admin may edit but not create:
  # db:seed runs on every boot, and a role whose wording an admin corrected must not come back.
  test "an admin's correction to a role survives a re-seed" do
    load_seed
    CardLabel.roles.first.update!(name: "Draw support", description: "Corrected by hand.")

    assert_no_difference "CardLabel.count" do
      load_seed
    end

    assert_equal "Draw support", CardLabel.roles.first.name
    assert_equal "Corrected by hand.", CardLabel.roles.first.description
  end
end
