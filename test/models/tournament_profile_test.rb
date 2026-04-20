require "test_helper"

class TournamentProfileTest < ActiveSupport::TestCase
  setup do
    @user = users(:one)
  end

  test "requires player_name, player_id, date_of_birth" do
    profile = TournamentProfile.new(user: @user)
    assert_not profile.valid?
    assert_includes profile.errors[:player_name], "can't be blank"
    assert_includes profile.errors[:player_id], "can't be blank"
    assert_includes profile.errors[:date_of_birth], "can't be blank"
  end

  test "player_id is unique globally" do
    duplicate = TournamentProfile.new(
      user: users(:two),
      player_name: "Copycat",
      player_id: tournament_profiles(:ash).player_id,
      date_of_birth: Date.new(2000, 1, 1)
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:player_id], "has already been taken"
  end

  test "rejects date_of_birth that gives an age below the junior minimum" do
    season = TournamentProfile.current_season_year
    too_recent_year = season - TournamentProfile::JUNIOR_MIN_AGE + 1

    profile = TournamentProfile.new(
      user: @user,
      player_name: "Too Young",
      player_id: "2000001",
      date_of_birth: Date.new(too_recent_year, 1, 1)
    )
    assert_not profile.valid?
    assert_match(/too recent/, profile.errors[:date_of_birth].first)
  end

  test "accepts date_of_birth that gives exactly the junior minimum age" do
    season = TournamentProfile.current_season_year
    boundary_year = season - TournamentProfile::JUNIOR_MIN_AGE

    profile = TournamentProfile.new(
      user: @user,
      player_name: "Exactly Six",
      player_id: "2000002",
      date_of_birth: Date.new(boundary_year, 12, 31)
    )
    assert profile.valid?, profile.errors.full_messages.to_sentence
  end

  test "rejects date_of_birth in the future" do
    profile = TournamentProfile.new(
      user: @user,
      player_name: "Future Kid",
      player_id: "9999999",
      date_of_birth: Date.current + 1
    )
    assert_not profile.valid?
    assert_includes profile.errors[:date_of_birth], "must be in the past"
  end

  test "current_season_year is the year the season ends in" do
    assert_equal 2026, TournamentProfile.current_season_year(Date.new(2026, 4, 20))
    assert_equal 2026, TournamentProfile.current_season_year(Date.new(2025, 9, 1))
    assert_equal 2025, TournamentProfile.current_season_year(Date.new(2025, 8, 31))
    assert_equal 2027, TournamentProfile.current_season_year(Date.new(2026, 9, 1))
  end

  test "division classifies masters (age >= 17 during season year)" do
    profile = build_profile(date_of_birth: Date.new(2009, 12, 31))
    assert_equal :masters, profile.division(on: Date.new(2026, 4, 20))
  end

  test "division classifies senior (age 13-16)" do
    profile = build_profile(date_of_birth: Date.new(2013, 1, 1))
    assert_equal :senior, profile.division(on: Date.new(2026, 4, 20))

    profile = build_profile(date_of_birth: Date.new(2010, 12, 31))
    assert_equal :senior, profile.division(on: Date.new(2026, 4, 20))
  end

  test "division classifies junior (age <= 12)" do
    profile = build_profile(date_of_birth: Date.new(2014, 1, 1))
    assert_equal :junior, profile.division(on: Date.new(2026, 4, 20))
  end

  test "division stays fixed across a season" do
    profile = build_profile(date_of_birth: Date.new(2013, 6, 1))
    assert_equal :senior, profile.division(on: Date.new(2025, 9, 1))
    assert_equal :senior, profile.division(on: Date.new(2026, 8, 31))
  end

  test "division flips when a new season starts on September 1" do
    profile = build_profile(date_of_birth: Date.new(2013, 6, 1))
    assert_equal :senior, profile.division(on: Date.new(2026, 8, 31))
    assert_equal :senior, profile.division(on: Date.new(2026, 9, 1))

    profile = build_profile(date_of_birth: Date.new(2010, 6, 1))
    assert_equal :senior, profile.division(on: Date.new(2026, 8, 31))
    assert_equal :masters, profile.division(on: Date.new(2026, 9, 1))
  end

  private

  def build_profile(date_of_birth:)
    TournamentProfile.new(
      user: @user,
      player_name: "Test",
      player_id: "test-#{SecureRandom.hex(4)}",
      date_of_birth: date_of_birth
    )
  end
end
