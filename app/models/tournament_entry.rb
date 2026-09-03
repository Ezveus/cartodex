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
