# One real-world tournament, shared by everybody who attended it. Any member may catalogue an
# event; only its creator (or an admin) corrects it afterwards. What a given player did there
# is a TournamentEntry.
class Tournament < ApplicationRecord
  include NameNormalizable

  belongs_to :created_by, class_name: "User", optional: true
  # A tournament is played under the format legal on its date, which is not the same as "the
  # newest set exists" — a set is tournament-legal about two weeks after release. The form
  # pre-fills this from the date; it stays editable.
  belongs_to :standard_pool, optional: true
  # restrict_with_error, unlike Archetype's :nullify: another member's participation must not
  # vanish because the creator of the catalog entry decided to delete it.
  has_many :entries, class_name: "TournamentEntry", dependent: :restrict_with_error
  # :destroy, unlike :entries' restrict_with_error, and the difference is the whole point of the
  # split: an entry is somebody's private record of having been there, a standing is a line of the
  # event's own public sheet. Deleting the event takes the sheet with it — and still refuses while
  # any participation survives.
  has_many :standings, class_name: "TournamentStanding", dependent: :destroy
  # Which event a field-list import is for, so the event page can list the reader's imports in
  # flight *here* rather than everywhere. :nullify, not :destroy: an Import is the member's own
  # record of work they asked for, and it outlives its subject the way a deck import already
  # outlives the deck. Declared after :entries, whose restrict_with_error runs first and aborts
  # the whole destroy anyway.
  has_many :imports, dependent: :nullify

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
  #
  # Read by TournamentEntry#suggested_championship_points: the grid is keyed on the event's
  # tier, the placement it is looked up with belongs to the participation.
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

  # The event's field size per age division. On the event rather than on each standing, because
  # two players in one division at one event are ranked against the same number — unlike
  # TournamentEntry#participant_count, which survives beside these (see the note there).
  DIVISION_COUNT_COLUMNS = {
    "junior" => :junior_participant_count,
    "senior" => :senior_participant_count,
    "masters" => :masters_participant_count
  }.freeze

  # The catalog prints format_label, which for a Standard event names the pool, and
  # StandardPool#name reads both of its bounds — so preloading the pool alone still costs two
  # queries per distinct pool. Deliberately a twin of Deck.with_standard_pool rather than a
  # shared concern: two call sites do not justify one, and a third model would be the moment.
  scope :with_standard_pool, -> { includes(standard_pool: [ :first_card_set, :last_card_set ]) }

  validates :name, presence: true
  validates :date, presence: true
  validates :other_format_name, presence: true, if: :other?
  validates :standard_pool, presence: true, if: :standard?
  validates :junior_participant_count, :senior_participant_count, :masters_participant_count,
    numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validate :name_and_date_are_unique

  # NameNormalizable normalizes in a before_save, which is too late for the uniqueness check
  # below to see the value it must compare. Running it before_validation as well is idempotent,
  # and it is what makes the validation and the UNIQUE index agree byte for byte.
  before_validation :normalize_name
  before_validation :clear_inapplicable_classification

  # Human-readable format label. For the "other" format the user-supplied name
  # takes precedence when present; for Standard the pool is named, since
  # "Standard" alone does not identify a card pool.
  def format_label
    return other_format_name if other? && other_format_name.present?

    base = FORMAT_LABELS.fetch(format, format.to_s.humanize)
    return base unless standard? && standard_pool

    "#{base} (#{standard_pool.name})"
  end

  def tier_label
    TIER_LABELS.fetch(tier, tier.to_s.humanize)
  end

  # The size of one age division's field, or nil when nobody has typed it in. Keyed on the
  # division *name* so a standing can ask with its own column value whatever its type.
  def participant_count_for(division)
    column = DIVISION_COUNT_COLUMNS[division.to_s]
    column && public_send(column)
  end

  private

  def clear_inapplicable_classification
    self.other_format_name = nil unless other?
    self.standard_pool_id = nil unless standard?
  end

  # The readable half of the (name_normalized, date) UNIQUE index — the same division of
  # labour as (set_name, set_number) on Card. The error is added to :name rather than to
  # :name_normalized, which is a column no user has ever heard of, and TournamentsController
  # re-finds the offending event from these two values so the form can link to it.
  def name_and_date_are_unique
    return if name_normalized.blank? || date.blank?

    clash = Tournament.where(name_normalized: name_normalized, date: date)
    clash = clash.where.not(id: id) if persisted?
    errors.add(:name, "is already catalogued for this date") if clash.exists?
  end
end
