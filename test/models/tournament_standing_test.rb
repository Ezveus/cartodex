require "test_helper"

class TournamentStandingTest < ActiveSupport::TestCase
  setup do
    @tournament = tournaments(:one)
    @archetype = archetypes(:ogerpon)
  end

  # Fixtures skip callbacks, so player_name_normalized is spelled out by hand — the same trap
  # every NameNormalizable model has a test for.
  test "the fixtures' normalized player names are in step with their player names" do
    TournamentStanding.find_each do |standing|
      assert_equal standing.player_name.squish.downcase, standing.player_name_normalized,
        "#{standing.player_name.inspect} and its normalized mirror have drifted apart"
    end
  end

  test "player_name, division and archetype are required" do
    standing = TournamentStanding.new(tournament: @tournament)

    refute_predicate standing, :valid?
    assert_includes standing.errors.attribute_names, :player_name
    assert_includes standing.errors.attribute_names, :division
    assert_includes standing.errors.attribute_names, :archetype
  end

  test "placement and the record are optional but must be sane when given" do
    standing = build_standing(placement: 0, wins: -1)

    refute_predicate standing, :valid?
    assert_includes standing.errors.attribute_names, :placement
    assert_includes standing.errors.attribute_names, :wins

    assert_predicate build_standing(placement: nil, wins: nil, losses: nil, ties: nil), :valid?
  end

  test "an unknown division is refused" do
    standing = build_standing
    standing.division = "seniors"

    refute_predicate standing, :valid?
    assert_includes standing.errors.attribute_names, :division
  end

  # The readable half of the UNIQUE index, and it must fold case and squish: a player name
  # arrives copy-pasted off a standings sheet far more often than it arrives typed.
  test "one player gets one row per division, whatever the spacing or the case" do
    build_standing(player_name: "Brock").save!

    %w[Brock brock BROCK].each do |spelling|
      clash = build_standing(player_name: spelling)
      refute_predicate clash, :valid?, "#{spelling.inspect} should collide with Brock"
      assert_includes clash.errors[:player_name], "already has a standing in this division"
    end

    doubled = build_standing(player_name: "  Brock  ")
    refute_predicate doubled, :valid?
    assert_includes doubled.errors[:player_name], "already has a standing in this division"
  end

  test "the same player may hold a row in another division" do
    build_standing(player_name: "Brock", division: "masters").save!

    assert_predicate build_standing(player_name: "Brock", division: "senior"), :valid?
  end

  test "a placement may not exceed the field of its own division" do
    @tournament.update!(masters_participant_count: 8, junior_participant_count: 64)

    refute_predicate build_standing(division: "masters", placement: 9), :valid?
    # The junior field is larger, so the same placement is fine there — which is the whole
    # reason the counts are per division.
    assert_predicate build_standing(division: "junior", placement: 9), :valid?
  end

  test "a placement is accepted when the division's field size is unknown" do
    @tournament.update!(masters_participant_count: nil)

    assert_predicate build_standing(division: "masters", placement: 999), :valid?
  end

  test "a participation from another event cannot be linked" do
    standing = build_standing(tournament_entry: tournament_entries(:two))

    refute_predicate standing, :valid?
    assert_includes standing.errors[:tournament_entry], "must be a participation in this tournament"
  end

  test "a participation in this event may be linked" do
    assert_predicate build_standing(tournament_entry: tournament_entries(:one)), :valid?
  end

  test "record_label prints the W-L-T, and nothing at all when none is recorded" do
    assert_equal "3-1-0", build_standing(wins: 3, losses: 1, ties: 0).record_label
    # A partially recorded row still prints: a zero the user did not type reads better than a
    # blank cell beside two numbers they did.
    assert_equal "3-0-0", build_standing(wins: 3, losses: nil, ties: nil).record_label
    assert_nil build_standing(wins: nil, losses: nil, ties: nil).record_label
  end

  test "the sheet reads by placement with the unplaced last" do
    build_standing(player_name: "Unplaced", placement: nil).save!
    build_standing(player_name: "Second", placement: 2).save!
    build_standing(player_name: "First", placement: 1).save!

    names = @tournament.standings.as_a_sheet.where.not(id: tournament_standings(:ash_masters).id)
      .where.not(id: tournament_standings(:giovanni_masters).id).map(&:player_name)

    assert_equal %w[First Second Unplaced], names
  end

  test "destroying a standing destroys its ownerless field list" do
    standing = build_standing(deck: decks(:field_list))
    standing.save!

    assert_difference -> { Deck.count }, -1 do
      standing.destroy
    end
  end

  test "destroying a standing never destroys a member's own deck" do
    # Nothing points a standing at an owned deck today. The guard is what stops a future caller
    # detonating a member's deck through a standings delete.
    owned = decks(:one)
    standing = build_standing(deck: owned)
    standing.save!(validate: false)

    assert_no_difference -> { Deck.count } do
      standing.destroy
    end
    assert Deck.exists?(owned.id)
  end

  private

  def build_standing(**attrs)
    @tournament.standings.build(
      { player_name: "Brock", division: "masters", archetype: @archetype }.merge(attrs)
    )
  end
end
