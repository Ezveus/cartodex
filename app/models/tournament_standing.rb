# One player's line in an event's public standings sheet.
#
# Not a TournamentEntry, and deliberately not merged into one: an entry is a *member's* private
# record of having been at an event, while a standing describes somebody who very likely has no
# account here — so it hangs off the Tournament, not off a User. Governance is wiki: any signed-in
# member may add, correct or delete any row, and `created_by` is the only trace of who typed it.
class TournamentStanding < ApplicationRecord
  # The same three values a TournamentProfile resolves to, as Strings because that is what the
  # column holds. Reused rather than re-declared: a second list would be free to drift from the
  # one that decides a real player's division.
  DIVISIONS = TournamentProfile::DIVISIONS.map(&:to_s).freeze

  belongs_to :tournament
  belongs_to :archetype
  # The event's field list: a Deck owned by nobody. Optional, because a row that names an
  # archetype and no list is the common case and still records something useful.
  belongs_to :deck, optional: true
  # The "this is me" link. Written only by Tournaments::StandingsController#claim/#unclaim and
  # never mass-assignable — see standing_params there for why.
  belongs_to :tournament_entry, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  # validate: true rejects nil as well as an unknown value, which is what makes "division is
  # present" a readable error rather than a NOT NULL violation.
  enum :division, DIVISIONS.index_by(&:itself), validate: true

  validates :player_name, presence: true
  validates :placement, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :wins, :losses, :ties,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :player_name_is_unique_in_division
  validate :placement_within_division_field
  validate :entry_belongs_to_same_tournament

  # before_validation as well as before_save, for the reason Tournament runs normalize_name
  # twice: the uniqueness validation has to compare the normalized value before the record is
  # saved, not once it already is. It squishes as well as downcasing — a player name arrives
  # copy-pasted off a standings sheet, with a trailing space or a double space where a column
  # wrapped, far more often than it arrives typed.
  #
  # NameNormalizable is not included: it normalizes `name`, and the column here is
  # `player_name`. Its `name_matching` scope is the point of that concern, and nothing searches
  # standings by player name.
  before_validation :normalize_player_name
  before_save :normalize_player_name

  # A destroyed standing takes its field list with it — but only a list nobody owns. Nothing
  # points a standing at an owned deck today; the guard is what keeps a future caller from
  # detonating a member's own deck through a standings delete.
  before_destroy :destroy_ownerless_deck

  # The sheet's order: ranked rows first, then the unplaced, then alphabetically. `placement IS
  # NULL` is what puts the unplaced last — SQLite sorts NULL *first* on a plain ASC. The index on
  # (tournament_id, division, placement) serves the equality and the division, not the computed
  # expression.
  scope :as_a_sheet, -> {
    order(:division, Arel.sql("placement IS NULL"), :placement, :player_name)
  }

  # The W-L-T as players write it, or nothing at all when no game was recorded. A missing half of
  # a partially typed record reads better as 0 than as a blank cell beside two numbers.
  def record_label
    return if wins.nil? && losses.nil? && ties.nil?

    [ wins, losses, ties ].map { |value| value || 0 }.join("-")
  end

  private

  def normalize_player_name
    self.player_name_normalized = player_name&.squish&.downcase
  end

  # The readable half of the (tournament_id, player_name_normalized, division) UNIQUE index — the
  # same division of labour as Tournament#name_and_date_are_unique. The error goes on
  # :player_name, a column the user has heard of, and the controller re-finds the offending row
  # from these three values so the form can link to it and offer to claim it.
  def player_name_is_unique_in_division
    return if tournament_id.blank? || player_name_normalized.blank? || division.blank?

    clash = TournamentStanding.where(
      tournament_id: tournament_id,
      player_name_normalized: player_name_normalized,
      division: division
    )
    clash = clash.where.not(id: id) if persisted?
    errors.add(:player_name, "already has a standing in this division") if clash.exists?
  end

  # A placement is ranked against the size of *this player's* age division, which is what the
  # three counters on Tournament hold. Silent when either half is unknown: placement is optional
  # by design, and an event whose field sizes nobody typed in must still accept rows.
  def placement_within_division_field
    return if placement.blank? || tournament.nil? || division.blank?

    field = tournament.participant_count_for(division)
    return if field.blank?
    return if placement <= field

    errors.add(:placement, "can't be greater than the #{division} field of #{field}")
  end

  # Whether the entry belongs to the *reader* is not a model concern — the model does not know
  # who is asking. The controller looks every entry up through current_user.tournament_entries,
  # so a stranger's entry is a RecordNotFound there rather than a policy question. What the model
  # can check is that the participation happened at this event.
  def entry_belongs_to_same_tournament
    return if tournament_entry.nil?
    return if tournament_entry.tournament_id == tournament_id

    errors.add(:tournament_entry, "must be a participation in this tournament")
  end

  def destroy_ownerless_deck
    deck&.destroy if deck && deck.user_id.nil?
  end
end
