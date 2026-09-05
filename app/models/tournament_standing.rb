# One player's line in an event's public standings sheet.
#
# Not a TournamentEntry, and deliberately not merged into one: an entry is a *member's* private
# record of having been at an event, while a standing describes somebody who very likely has no
# account here — so it hangs off the Tournament, not off a User. Governance is wiki: any signed-in
# member may add, correct or delete any row, and `created_by` is the only trace of who typed it.
class TournamentStanding < ApplicationRecord
  # The three Play! Pokémon age divisions, as Strings because that is what the column holds.
  # Still derived from TournamentProfile rather than re-declared: this list has to keep agreeing
  # with the one that decides a real player's division, and a second copy would be free to drift.
  AGE_DIVISIONS = TournamentProfile::DIVISIONS.map(&:to_s).freeze

  # Every value the column may hold. "open" is not an age division and has no TournamentProfile
  # behind it: it is what an online event's standing carries, because online play has no age
  # divisions at all and `division` is NOT NULL behind a validating enum. Writing "masters" there
  # instead would be a lie that Archetypes::Performance#by_division then reports as fact.
  #
  # The two lists are separate because four readers want different halves of them, and the split
  # is the only thing keeping each honest: the enum, `division_order`, Standings::Table and
  # Performance#by_division must see all four or an online row is silently dropped from a report
  # that still looks complete — while Standings::Form's select and StandingsController's prefill
  # must see only AGE_DIVISIONS, or a member typing a paper event's sheet is offered "Open".
  DIVISIONS = (AGE_DIVISIONS + [ "open" ]).freeze

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
  validate :entry_is_not_already_linked

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

  # Play! Pokémon reads the divisions junior, senior, masters — DIVISIONS' own order, and not the
  # alphabetical one a plain `ORDER BY division` gives, which is why Standings::Table has always
  # regrouped them for display. Ordering them the same way in SQL is what makes the sheet
  # paginable at all: with the two orders disagreeing, a page boundary drawn in SQL falls
  # somewhere the reader never sees, and page 2 of a Worlds sheet would open in the middle of a
  # division that page 1 appeared to have finished.
  #
  # "open" sorts last, after masters, which is where a reader looking for the age divisions
  # expects anything that is not one.
  #
  # An Arel CASE rather than an interpolated Arel.sql string. The values come from a frozen
  # constant, so neither form can carry user input — but the interpolated one
  # is indistinguishable from one that could, and Brakeman (a CI check, clean until now) says so.
  # Arel quotes them itself and leaves nothing to read as a warning.
  def self.division_order
    DIVISIONS.each_with_index
      .inject(Arel::Nodes::Case.new(arel_table[:division])) { |node, (division, index)|
        node.when(division).then(index)
      }.else(DIVISIONS.size)
  end

  # The sheet's page size. It lives on the model rather than on either controller because it is a
  # fact about the sheet and two copies would drift: TournamentsController renders a page with it
  # and Tournaments::StandingsController works out which page to send an editor back to, and the
  # day one changed, a member who added a row would land on a page that does not hold it.
  SHEET_PER_PAGE = 50

  # The sheet's order: divisions as players read them, then ranked rows, then the unplaced, then
  # alphabetically. `placement IS NULL` is what puts the unplaced last — SQLite sorts NULL *first*
  # on a plain ASC. The index on (tournament_id, division, placement) still serves the equality,
  # but the CASE costs its `division` term: measured on a 3000-row event, the old order sorted
  # only the trailing terms ("USE TEMP B-TREE FOR LAST 3 TERMS OF ORDER BY") while this one sorts
  # all of them. Paid knowingly — it is one event's field, and page_of over 3000 rows measures
  # 0.4 ms — and it buys a page boundary the reader can see.
  scope :as_a_sheet, -> {
    order(division_order.asc, Arel.sql("placement IS NULL"), :placement, :player_name)
  }

  # Which page of its own event's sheet this row falls on. One pluck of ids over a bounded set —
  # one event's field — rather than a COUNT of the rows that sort before it: that predicate would
  # have to spell out the division CASE and `placement IS NULL` a second time, and the two copies
  # would disagree the first time as_a_sheet changed.
  def self.page_of(standing)
    position = where(tournament_id: standing.tournament_id).as_a_sheet.pluck(:id).index(standing.id)
    return 1 if position.nil?

    (position / SHEET_PER_PAGE) + 1
  end

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

  # The readable half of the partial UNIQUE index on tournament_entry_id (WHERE … IS NOT NULL) —
  # the same division of labour as player_name_is_unique_in_division above and
  # Tournament#name_and_date_are_unique. Without it, re-opening the still-bookmarkable
  # new?tournament_entry_id=E under a different player name, or claiming from two tabs, hits the
  # index directly and raises ActiveRecord::RecordNotUnique. The error goes on :tournament_entry,
  # which #claim's rescue reads to build its alert.
  def entry_is_not_already_linked
    return if tournament_entry_id.blank?

    clash = TournamentStanding.where(tournament_entry_id: tournament_entry_id)
    clash = clash.where.not(id: id) if persisted?
    errors.add(:tournament_entry, "is already linked to another standing") if clash.exists?
  end

  def destroy_ownerless_deck
    deck&.destroy_if_ownerless
  end
end
