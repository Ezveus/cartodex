require "test_helper"

class TournamentTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
    @deck = decks(:one)
  end

  test "requires name and date" do
    tournament = Tournament.new(user: @user, deck: @deck)
    assert_not tournament.valid?
    assert_includes tournament.errors[:name], "can't be blank"
    assert_includes tournament.errors[:date], "can't be blank"
  end

  test "requires other_format_name when format is other" do
    tournament = build_tournament(format: "other")
    assert_not tournament.valid?
    assert_includes tournament.errors[:other_format_name], "can't be blank"
  end

  test "clears other_format_name when format is not other" do
    tournament = build_tournament(format: "standard", other_format_name: "Pocket")
    tournament.valid?
    assert_nil tournament.other_format_name
  end

  test "rejects a placement greater than the participant count" do
    tournament = build_tournament(participant_count: 8, placement: 9)
    assert_not tournament.valid?
    assert_includes tournament.errors[:placement], "can't be greater than the number of participants"
  end

  test "rejects a deck belonging to another user" do
    tournament = build_tournament(deck: decks(:two))
    assert_not tournament.valid?
    assert_includes tournament.errors[:deck], "must belong to the same user"
  end

  test "rejects a tournament profile belonging to another user" do
    tournament = build_tournament(tournament_profile: tournament_profiles(:giovanni))
    assert_not tournament.valid?
    assert_includes tournament.errors[:tournament_profile], "must belong to the same user"
  end

  test "suggested_championship_points looks up the reference table by tier and placement" do
    tournament = build_tournament(tier: "regional", placement: 3)
    assert_equal 300, tournament.suggested_championship_points

    tournament = build_tournament(tier: "league_challenge", placement: 1)
    assert_equal 0, tournament.suggested_championship_points
  end

  test "suggested_championship_points is nil without a placement" do
    tournament = build_tournament(tier: "regional", placement: nil)
    assert_nil tournament.suggested_championship_points
  end

  test "standard_top_cut looks up the indicative band by participant count" do
    assert_nil build_tournament(participant_count: 8).standard_top_cut
    assert_equal 4, build_tournament(participant_count: 16).standard_top_cut
    assert_equal 8, build_tournament(participant_count: 64).standard_top_cut
    assert_equal 16, build_tournament(participant_count: 226).standard_top_cut
    assert_equal 32, build_tournament(participant_count: 1024).standard_top_cut
    assert_equal 64, build_tournament(participant_count: 2000).standard_top_cut
  end

  test "standard_top_cut is nil without a participant count" do
    assert_nil build_tournament(participant_count: nil).standard_top_cut
  end

  test "requires a standard pool when the format is standard" do
    tournament = build_tournament(format: "standard", standard_pool: nil)

    assert_not tournament.valid?
    assert_includes tournament.errors[:standard_pool], "can't be blank"
  end

  test "clears the standard pool when the format is not standard" do
    tournament = build_tournament(format: "expanded", standard_pool: standard_pools(:twm_por))

    tournament.validate

    assert_nil tournament.standard_pool_id
  end

  # Distinct from the clearing test above: that one only checks the field gets nilled out, not
  # that the record ends up valid. An unconditional presence validation would clear the field and
  # still fail — this is what actually proves the "if: :standard?" guard is doing its job.
  test "does not require a standard pool when the format is not standard" do
    tournament = build_tournament(format: "expanded", standard_pool: nil)

    assert tournament.valid?
  end

  # Uppercase accented letter in the stored name on purpose — see the note in DeckTest: only
  # name_normalized can match a lowercase query against it.
  test "name_matching ignores case on accented letters" do
    tournament = tournaments(:one)
    tournament.update!(name: "RÉGIONALE de Lyon")

    %w[RÉGIONALE Régionale régionale].each do |query|
      assert_includes Tournament.name_matching(query), tournament, "#{query.inspect} must match"
    end
  end

  test "name_matching treats LIKE metacharacters in the query as literals" do
    assert_includes Tournament.name_matching("regional"), tournaments(:one), "sanity: the plain spelling matches"
    assert_empty Tournament.name_matching("reg_onal"), "_ must not act as a wildcard"
    assert_empty Tournament.name_matching("regi%nal"), "% must not act as a wildcard"
  end

  test "every tournament fixture carries the normalization its name implies" do
    Tournament.find_each do |tournament|
      assert_equal tournament.name.downcase, tournament.name_normalized,
        "#{tournament.name.inspect} fixture is out of step"
    end
  end

  private

  def build_tournament(attrs = {})
    Tournament.new({
      user: @user,
      deck: @deck,
      name: "Test Tournament",
      date: Date.current,
      tier: "regional"
    }.merge(attrs))
  end
end
