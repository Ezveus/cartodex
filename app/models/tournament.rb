class Tournament < ApplicationRecord
  include NameNormalizable

  belongs_to :user
  belongs_to :deck
  belongs_to :tournament_profile, optional: true
  has_many :deck_results, dependent: :nullify

  enum :format, { standard: "standard", glc: "glc", expanded: "expanded", other: "other" }, validate: true
  enum :tier, {
    league_challenge: "league_challenge",
    league_cup: "league_cup",
    regional: "regional",
    international: "international",
    worlds: "worlds",
    other: "other"
  }, validate: true, prefix: true

  FORMAT_LABELS = Deck::FORMAT_LABELS

  TIER_LABELS = {
    "league_challenge" => "League Challenge",
    "league_cup" => "League Cup",
    "regional" => "Regional / Special Championship",
    "international" => "International Championship",
    "worlds" => "World Championship",
    "other" => "Other"
  }.freeze

  # Indicative Championship Point payouts by placement, per tournament tier.
  # These are approximate reference values (official grids vary by season,
  # exact attendance and age division) meant to pre-fill the CP field — the
  # user can always override them. League Challenges and informal events
  # award no CP; League Cups, Regionals/Specials, Internationals and Worlds do.
  CP_REFERENCE = {
    "league_challenge" => [ [ 1..Float::INFINITY, 0 ] ],
    "league_cup" => [
      [ 1..1, 50 ], [ 2..2, 40 ], [ 3..4, 30 ], [ 5..8, 20 ], [ 9..16, 10 ], [ 17..Float::INFINITY, 0 ]
    ],
    "regional" => [
      [ 1..1, 350 ], [ 2..2, 325 ], [ 3..4, 300 ], [ 5..8, 280 ], [ 9..16, 200 ],
      [ 17..32, 160 ], [ 33..64, 120 ], [ 65..128, 100 ], [ 129..256, 60 ], [ 257..Float::INFINITY, 0 ]
    ],
    "international" => [
      [ 1..1, 500 ], [ 2..2, 460 ], [ 3..4, 420 ], [ 5..8, 380 ], [ 9..16, 300 ],
      [ 17..32, 220 ], [ 33..64, 160 ], [ 65..128, 120 ], [ 129..256, 80 ], [ 257..Float::INFINITY, 40 ]
    ],
    "worlds" => [
      [ 1..1, 600 ], [ 2..2, 550 ], [ 3..4, 500 ], [ 5..8, 450 ], [ 9..16, 350 ],
      [ 17..32, 250 ], [ 33..64, 180 ], [ 65..Float::INFINITY, 100 ]
    ],
    "other" => [ [ 1..Float::INFINITY, 0 ] ]
  }.freeze

  # Standard Play! Pokémon top cut size by attendance (indicative only).
  TOP_CUT_BANDS = [
    [ 1..8, nil ],
    [ 9..16, 4 ],
    [ 17..64, 8 ],
    [ 65..226, 16 ],
    [ 227..1024, 32 ],
    [ 1025..Float::INFINITY, 64 ]
  ].freeze

  validates :name, presence: true
  validates :date, presence: true
  validates :other_format_name, presence: true, if: :other?
  validates :participant_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :placement, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :championship_points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :placement_within_participant_count
  validate :deck_belongs_to_user
  validate :tournament_profile_belongs_to_user

  before_validation :clear_inapplicable_classification

  # Human-readable format label. For the "other" format the user-supplied
  # name takes precedence when present.
  def format_label
    return other_format_name if other? && other_format_name.present?

    FORMAT_LABELS.fetch(format, format.to_s.humanize)
  end

  def tier_label
    TIER_LABELS.fetch(tier, tier.to_s.humanize)
  end

  # Indicative CP for the current tier/placement, or nil if not computable.
  def suggested_championship_points
    return if placement.blank?

    CP_REFERENCE.fetch(tier, []).find { |range, _points| range.cover?(placement) }&.last
  end

  # Indicative standard top cut size for the current participant count, or
  # nil if not computable or if the field size doesn't warrant a cut.
  def standard_top_cut
    return if participant_count.blank?

    TOP_CUT_BANDS.find { |range, _cut| range.cover?(participant_count) }&.last
  end

  private

  def clear_inapplicable_classification
    self.other_format_name = nil unless other?
  end

  def placement_within_participant_count
    return if placement.blank? || participant_count.blank?

    errors.add(:placement, "can't be greater than the number of participants") if placement > participant_count
  end

  def deck_belongs_to_user
    return if deck.nil? || user.nil?

    errors.add(:deck, "must belong to the same user") if deck.user_id != user_id
  end

  def tournament_profile_belongs_to_user
    return if tournament_profile.nil? || user.nil?

    errors.add(:tournament_profile, "must belong to the same user") if tournament_profile.user_id != user_id
  end
end
