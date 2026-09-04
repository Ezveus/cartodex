class DeckResult < ApplicationRecord
  belongs_to :deck
  belongs_to :archetype, optional: true
  belongs_to :tournament_entry, optional: true

  RESULTS       = %w[win loss draw timeout].freeze
  MATCH_FORMATS = %w[bo1 bo3].freeze
  GAME_OUTCOMES = %w[W L T D].freeze # per-game: win / loss / timeout / draw

  before_validation :normalize_score
  before_validation :derive_result_from_score

  validates :result, presence: true, inclusion: { in: RESULTS }
  validates :match_format, presence: true, inclusion: { in: MATCH_FORMATS }
  validates :score, format: { with: /\A[WLTD]{1,3}\z/ }, allow_blank: true
  validate :score_only_for_bo3
  validate :entry_belongs_to_same_deck

  # Maps a per-game score string (e.g. "WW", "WLT") to the overall match result,
  # or nil when the score does not yet determine a winner.
  def self.result_from_score(score)
    games = score.to_s.chars
    return "draw"    if games.include?("D")
    return "timeout" if games.include?("T")
    return "win"     if games.count("W") >= 2
    return "loss"    if games.count("L") >= 2
    nil
  end

  private

  def normalize_score
    self.score = score.to_s.strip.upcase.presence
  end

  def derive_result_from_score
    return if score.blank? || match_format != "bo3"

    derived = self.class.result_from_score(score)
    self.result = derived if derived
  end

  def score_only_for_bo3
    errors.add(:score, "is only valid for best-of-three matches") if score.present? && match_format != "bo3"
  end

  # A match can only hang off a participation played with the same deck.
  def entry_belongs_to_same_deck
    return if tournament_entry.nil? || deck.nil?

    errors.add(:tournament_entry, "must belong to the same deck") if tournament_entry.deck_id != deck_id
  end
end
