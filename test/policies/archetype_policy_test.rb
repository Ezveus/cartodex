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

  # The archetype catalog and one archetype's report are public, so a nil user answers yes to
  # both. This is the inversion of "a visitor is refused both pages", which stood here while
  # routes.rb's `authenticate :user` block made the case unreachable by request — and it is
  # still the only place the rule is written down in a form the policy object itself can be
  # asked, which is what a nil `current_user` on the public page produces.
  test "a visitor reads both pages" do
    assert ArchetypePolicy.new(nil, Archetype).index?
    assert ArchetypePolicy.new(nil, @archetype).show?
  end

  # An archetype is public factual data with no owner, so being an admin buys nothing here and
  # neither does having tagged a deck with it. Pinned so a later reader does not add a rule.
  test "admin status makes no difference either way" do
    @other.update!(admin: true)

    assert ArchetypePolicy.new(@other, @archetype).show?
    # And an admin gains nothing a visitor does not already have, which is the half of "makes no
    # difference" that survives the pages going public.
    assert ArchetypePolicy.new(nil, @archetype).show?
  end
end
