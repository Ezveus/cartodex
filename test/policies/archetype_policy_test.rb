require "test_helper"

class ArchetypePolicyTest < ActiveSupport::TestCase
  setup do
    @archetype = archetypes(:ogerpon)
    @member = users(:one)
    @other = users(:two)
  end

  test "any member reads the catalog and an archetype's report" do
    [ @member, @other ].each do |user|
      assert ArchetypePolicy.new(user, Archetype).index?, "index? must answer any member"
      assert ArchetypePolicy.new(user, @archetype).show?, "show? must answer any member"
    end
  end

  # The case a request cannot currently produce — routes.rb's `authenticate :user` block bounces
  # a visitor before the policy is consulted — and therefore the only place the rule is actually
  # written down. It is also the one that changes the day the pages open to visitors.
  test "a visitor is refused both pages" do
    assert_not ArchetypePolicy.new(nil, Archetype).index?
    assert_not ArchetypePolicy.new(nil, @archetype).show?
  end

  # An archetype is public factual data with no owner, so being an admin buys nothing here and
  # neither does having tagged a deck with it. Pinned so a later reader does not add a rule.
  test "admin status makes no difference either way" do
    @other.update!(admin: true)

    assert ArchetypePolicy.new(@other, @archetype).show?
    assert_not ArchetypePolicy.new(nil, @archetype).show?
  end
end
