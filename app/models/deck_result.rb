class DeckResult < ApplicationRecord
  # touch: recording a result counts as working on the deck for /decks' "most recently updated"
  # order — see DeckCard.
  belongs_to :deck, touch: true
  belongs_to :archetype, optional: true
  belongs_to :tournament_entry, optional: true
  # Required, with no fallback: a result nobody placed on a version is refused rather than
  # quietly filed on the latest one. The only automatic assignment is the participation's, below.
  belongs_to :deck_version

  RESULTS       = %w[win loss draw timeout].freeze
  MATCH_FORMATS = %w[bo1 bo3].freeze
  GAME_OUTCOMES = %w[W L T D].freeze # per-game: win / loss / timeout / draw

  before_validation :normalize_score
  before_validation :derive_result_from_score
  before_validation :inherit_entry_version

  validates :result, presence: true, inclusion: { in: RESULTS }
  validates :match_format, presence: true, inclusion: { in: MATCH_FORMATS }
  validates :score, format: { with: /\A[WLTD]{1,3}\z/ }, allow_blank: true
  validate :score_only_for_bo3
  validate :entry_belongs_to_same_deck
  validate :version_belongs_to_same_deck
  validate :version_matches_entry

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

  # A participation says which list was played, so a match played there was played with it.
  # Every write path that attaches a result to an entry goes through here, except
  # Tournaments::EntriesController#attach_results, whose update_all writes both columns itself.
  #
  # Only a participation of this deck: another deck's is refused by entry_belongs_to_same_deck,
  # and inheriting its version would add a second error that only restates that one.
  def inherit_entry_version
    self.deck_version = tournament_entry.deck_version if own_entry?
  end

  def own_entry? = tournament_entry.present? && tournament_entry.deck_id == deck_id

  def version_belongs_to_same_deck
    return if deck_version.nil? || deck_id.nil?

    errors.add(:deck_version, "must belong to the same deck") if deck_version.deck_id != deck_id
  end

  # Cannot fail after inherit_entry_version has run. Kept so the invariant is a stated rule and
  # not only a side effect of a callback that a later edit might reorder or condition away.
  def version_matches_entry
    return if !own_entry? || deck_version_id.nil?

    errors.add(:deck_version, "must be its participation's version") if deck_version_id != tournament_entry.deck_version_id
  end

  # A match can only hang off a participation played with the same deck.
  def entry_belongs_to_same_deck
    return if tournament_entry.nil? || deck.nil?

    errors.add(:tournament_entry, "must belong to the same deck") if tournament_entry.deck_id != deck_id
  end
end
