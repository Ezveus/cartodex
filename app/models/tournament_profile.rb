class TournamentProfile < ApplicationRecord
  DIVISIONS = %i[junior senior masters].freeze
  JUNIOR_MIN_AGE = 6

  belongs_to :user

  validates :player_name, presence: true
  validates :player_id, presence: true, uniqueness: true
  validates :date_of_birth, presence: true
  validate :date_of_birth_in_the_past
  validate :age_meets_junior_minimum

  # Play! Pokémon seasons run September 1 to August 31 and are named after the
  # year they end in. The 2026 season therefore starts on 2025-09-01 and ends
  # on 2026-08-31.
  def self.current_season_year(on = Date.current)
    on.month >= 9 ? on.year + 1 : on.year
  end

  # Division follows the official Play! Pokémon birth-year rule and is fixed
  # for the whole season:
  #   - Masters: age ≥ 17 during the season year (born in or before season_year - 17)
  #   - Senior:  age 13–16
  #   - Junior:  age ≤ 12
  def division(on: Date.current)
    return nil if date_of_birth.blank?

    age_during_season = self.class.current_season_year(on) - date_of_birth.year
    case age_during_season
    when ..12 then :junior
    when 13..16 then :senior
    else :masters
    end
  end

  private

  def date_of_birth_in_the_past
    return if date_of_birth.blank?
    errors.add(:date_of_birth, "must be in the past") if date_of_birth >= Date.current
  end

  def age_meets_junior_minimum
    return if date_of_birth.blank?
    age_during_season = self.class.current_season_year - date_of_birth.year
    return if age_during_season >= JUNIOR_MIN_AGE
    errors.add(:date_of_birth, "is too recent — player must turn at least #{JUNIOR_MIN_AGE} during the current season")
  end
end
