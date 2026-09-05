require "test_helper"

# The seed is a bootstrap, not the source of truth — bin/docker-entrypoint runs db:seed on every
# boot, so a seed that reasserted its values would revert an admin's correction on each deploy.
# That is the rule db/seeds/standard_pools.rb already follows, and this test is what holds it.
class CardLabelSeedTest < ActiveSupport::TestCase
  def load_seed = load Rails.root.join("db/seeds/card_labels.rb")

  test "it creates the ace-spec label with the token it is imported by" do
    assert_difference "CardLabel.count", 1 do
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
end
