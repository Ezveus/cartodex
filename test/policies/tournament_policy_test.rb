require "test_helper"

class TournamentPolicyTest < ActiveSupport::TestCase
  setup do
    @tournament = tournaments(:one) # created_by: one
    @creator = users(:one)
    @other = users(:two)
  end

  test "the catalog and an event page are readable by anybody, a visitor included" do
    [ nil, @creator, @other ].each do |user|
      assert TournamentPolicy.new(user, Tournament).index?, "index? must not depend on the reader"
      assert TournamentPolicy.new(user, @tournament).show?, "show? must not depend on the reader"
    end
  end

  test "a visitor cannot catalogue an event or list participations" do
    policy = TournamentPolicy.new(nil, Tournament)

    assert_not policy.create?
    assert_not policy.new?
    assert_not policy.mine?
  end

  test "any member can catalogue an event" do
    assert TournamentPolicy.new(@other, Tournament).create?
  end

  test "only the creator edits the fiche" do
    assert TournamentPolicy.new(@creator, @tournament).update?
    assert TournamentPolicy.new(@creator, @tournament).edit?
    assert_not TournamentPolicy.new(@other, @tournament).update?
    assert_not TournamentPolicy.new(@other, @tournament).edit?
    assert_not TournamentPolicy.new(nil, @tournament).update?
    assert_not TournamentPolicy.new(nil, @tournament).edit?
  end

  # The deliberate departure from "no query anywhere checks admin?": nothing about an event is
  # hidden, so moderating public factual data widens no confidentiality boundary.
  test "an admin edits and deletes any fiche" do
    admin = @other
    admin.update!(admin: true)

    assert TournamentPolicy.new(admin, @tournament).update?
    assert TournamentPolicy.new(admin, @tournament).destroy?
  end

  test "an event whose creator is gone is editable by admins only" do
    @tournament.update!(created_by: nil)

    assert_not TournamentPolicy.new(@creator, @tournament).update?
    @other.update!(admin: true)
    assert TournamentPolicy.new(@other, @tournament).update?
  end
end
