# What one player did at one tournament: the deck they brought, the Play! Pokémon profile they
# played under, and how they finished. Private to its owner — the event it points at is public.
class TournamentEntry < ApplicationRecord
  belongs_to :user
  belongs_to :tournament
  belongs_to :deck
  belongs_to :tournament_profile, optional: true
  has_many :deck_results, dependent: :nullify

  validates :participant_count, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :placement, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :championship_points, numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :placement_within_participant_count
  validate :deck_belongs_to_user
  validate :tournament_profile_belongs_to_user
  validate :one_entry_per_player
  validate :deck_unchanged_while_results_attached

  # The label both tournament pickers print — Decks::ResultModal and DeckResults::EditView —
  # kept here rather than in either of them for the reason Card#printing_label is: two callers
  # that spell one label by hand eventually spell it two ways. The player name is part of the
  # label, not decoration: entry uniqueness is per Play! Pokémon profile, so one deck can carry
  # two participations in one event, and "Name (date)" alone prints them identically.
  def picker_label
    base = "#{tournament.name} (#{I18n.l(tournament.date)})"
    return base if tournament_profile.nil?

    "#{base} — #{tournament_profile.player_name}"
  end

  # Indicative CP for this placement at the event's tier, or nil if not computable. The grid
  # lives on Tournament, beside the tier that keys it; the placement that looks it up is here.
  def suggested_championship_points
    return if placement.blank? || tournament.nil?

    Tournament::CP_REFERENCE.fetch(tournament.tier, [])
      .find { |range, _points| range.cover?(placement) }&.last
  end

  # Indicative standard top cut size for this division's field, or nil if not computable or if
  # the field size doesn't warrant a cut. participant_count is the size of *this player's*
  # division, not the event's attendance — Play! Pokémon ranks by age division.
  def standard_top_cut
    return if participant_count.blank?

    Tournament::TOP_CUT_BANDS.find { |range, _cut| range.cover?(participant_count) }&.last
  end

  private

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

  # DeckResult#entry_belongs_to_same_deck is the other half of "a match hangs off a
  # participation played with the same deck", and it is checked when the *result* is saved —
  # nothing re-checks it when the entry moves the deck underneath. Without this the update
  # succeeds and leaves every attached match invalid, listed on a page that names a deck they
  # do not belong to. Refusing rather than detaching keeps the decision with the user, the same
  # call Tournament#entries and TournamentProfile#tournament_entries make with
  # restrict_with_error: detaching would empty a match history nobody asked to empty.
  def deck_unchanged_while_results_attached
    return unless persisted? && deck_id_changed?
    return unless deck_results.exists?

    errors.add(:deck, "can't be changed while matches are attached to this participation")
  end

  # One rule, one method, one message — mirroring both partial unique indexes rather than
  # splitting them across two conditional `validates` calls a reader has to reassemble. The
  # profile-less branch is the one an index alone could not enforce: SQLite treats NULLs as
  # distinct, so a single index on (tournament_id, tournament_profile_id) would not see it.
  def one_entry_per_player
    return if tournament_id.blank? || user_id.blank?

    clash =
      if tournament_profile_id.present?
        TournamentEntry.where(tournament_id: tournament_id, tournament_profile_id: tournament_profile_id)
      else
        TournamentEntry.where(tournament_id: tournament_id, user_id: user_id, tournament_profile_id: nil)
      end
    clash = clash.where.not(id: id) if persisted?
    return unless clash.exists?

    errors.add(:tournament, "already has a participation for this player")
  end
end
