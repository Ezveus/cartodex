require "test_helper"

class TournamentEntryPolicyTest < ActiveSupport::TestCase
  setup do
    @entry = tournament_entries(:one) # user: one
    @owner = users(:one)
    @other = users(:two)
  end

  test "everything about a participation belongs to its owner" do
    %i[show? create? new? update? edit? destroy? attach_results? detach_result?].each do |query|
      assert TournamentEntryPolicy.new(@owner, @entry).public_send(query), "owner must be allowed #{query}"
      assert_not TournamentEntryPolicy.new(@other, @entry).public_send(query), "a stranger must be refused #{query}"
      assert_not TournamentEntryPolicy.new(nil, @entry).public_send(query), "a visitor must be refused #{query}"
    end
  end

  # An admin has no business here: unlike a catalog entry, a participation is private data, and
  # this is where the repository-wide rule about admin? still holds.
  test "an admin has no special access to somebody's participation" do
    @other.update!(admin: true)

    assert_not TournamentEntryPolicy.new(@other, @entry).show?
  end
end
