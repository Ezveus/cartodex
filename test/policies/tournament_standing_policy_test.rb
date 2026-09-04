require "test_helper"

class TournamentStandingPolicyTest < ActiveSupport::TestCase
  setup do
    @standing = tournament_standings(:ash_masters)
    @member = users(:two)   # did not create this row
    @author = users(:one)
    @admin = users(:one).tap { |u| u.update!(admin: true) }
  end

  # Wiki governance, decision 3 of the design: correcting a public record is not a property
  # question, so a member who typed nothing may still fix anything.
  test "any signed-in member may write any row" do
    policy = TournamentStandingPolicy.new(@member, @standing)

    assert_predicate policy, :create?
    assert_predicate policy, :new?
    assert_predicate policy, :update?
    assert_predicate policy, :edit?
    assert_predicate policy, :destroy?
    assert_predicate policy, :claim?
  end

  test "a visitor may write nothing" do
    policy = TournamentStandingPolicy.new(nil, @standing)

    refute_predicate policy, :create?
    refute_predicate policy, :update?
    refute_predicate policy, :destroy?
    refute_predicate policy, :claim?
    refute_predicate policy, :unclaim?
  end

  # The one owner-scoped rule: anybody may correct the public data on a row, but only the member
  # whose participation is linked may sever the link.
  test "only the member whose participation is linked may unclaim it" do
    @standing.update!(tournament_entry: tournament_entries(:one)) # users(:one)'s participation

    assert_predicate TournamentStandingPolicy.new(users(:one), @standing), :unclaim?
    refute_predicate TournamentStandingPolicy.new(users(:two), @standing), :unclaim?
  end

  test "an unlinked row cannot be unclaimed by anybody" do
    assert_nil @standing.tournament_entry_id

    refute_predicate TournamentStandingPolicy.new(users(:one), @standing), :unclaim?
    refute_predicate TournamentStandingPolicy.new(users(:two), @standing), :unclaim?
  end

  # Unlike TournamentPolicy, this policy reads no admin?: there is no moderation question here a
  # member cannot already answer, since every member can already edit every row. And a
  # participation stays its owner's, exactly as TournamentEntryPolicy has it.
  test "an admin gains nothing a member does not have" do
    @standing.update!(tournament_entry: tournament_entries(:shared_event)) # users(:two)'s participation
    admin = users(:one)
    admin.update!(admin: true)

    refute_predicate TournamentStandingPolicy.new(admin, @standing), :unclaim?
  end
end
