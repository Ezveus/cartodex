class Deck < ApplicationRecord
  include NameNormalizable

  belongs_to :user
  belongs_to :archetype, optional: true
  has_many :deck_cards, dependent: :destroy
  has_many :cards, through: :deck_cards
  has_many :deck_results, dependent: :destroy
  has_many :tournaments, dependent: :destroy

  enum :format, { standard: "standard", glc: "glc", expanded: "expanded", other: "other" }, validate: true

  FORMAT_LABELS = {
    "standard" => "Standard",
    "glc"      => "GLC",
    "expanded" => "Expanded",
    "other"    => "Other"
  }.freeze

  validates :name, presence: true
  validates :other_format_name, presence: true, if: :other?

  before_validation :clear_inapplicable_classification
  after_update :release_owned_copies_if_not_physical

  # Matches the deck's own name or its archetype's (which itself spans the archetype name and its
  # member Pokémon). The archetype side goes in as a subquery rather than a join: Archetype.search
  # carries its own left_joins and distinct, which #or refuses to merge, and a subquery keeps the
  # deck rows unduplicated.
  scope :search, ->(query) {
    name_matching(query).or(where(archetype_id: Archetype.search(query).select(:id)))
  }

  # SQL counterpart of #has_proxies?, for the deck-list filter. The `physical` half is not
  # decoration: a non-physical deck's cards all sit at owned_copies 0, so the bare per-card test
  # would sweep every TCG Live deck in.
  scope :with_proxies, -> { where(physical: true, id: DeckCard.with_proxies.select(:deck_id)) }
  scope :without_proxies, -> { where.not(id: Deck.with_proxies.select(:id)) }

  # Human-readable format label. For the "other" format the user-supplied
  # name takes precedence when present.
  def format_label
    return other_format_name if other? && other_format_name.present?

    FORMAT_LABELS.fetch(format, format.to_s.humanize)
  end

  # Whether the deck is played with any proxy, derived from the per-card real/proxy split rather
  # than declared by hand — the two used to be independent and could disagree. Only a physical
  # deck can hold proxies: a TCG Live deck consumes no collection, so its cards being unbacked
  # says nothing. Reads off a loaded deck_cards association, which both views that show the badge
  # already preload.
  def has_proxies?
    physical? && deck_cards.any? { |deck_card| deck_card.proxies.positive? }
  end

  # Energy types of the deck's archetype, used for the type stripe and badge.
  def energy_types
    archetype&.energy_types || []
  end

  # Win rate over decided games (wins + losses). Nil when nothing is decided yet.
  def win_rate(results = deck_results)
    counts = result_counts(results)
    decided = counts["win"] + counts["loss"]
    return if decided.zero?

    counts["win"].to_f / decided
  end

  # A proven performer: enough decided games and a winning majority. Earns the
  # holographic treatment in the deck list.
  def hot?(results = deck_results)
    counts = result_counts(results)
    decided = counts["win"] + counts["loss"]
    decided >= 5 && counts["win"].to_f / decided >= 0.6
  end

  def result_counts(results = deck_results)
    counts = DeckResult::RESULTS.index_with(0)
    results.each { |r| counts[r.result] += 1 if counts.key?(r.result) }
    counts
  end

  # Builds a parent-grouped archetype breakdown of the given results.
  # Returns an array of { name:, counts:, children: [{ name:, counts: }, ...] },
  # sorted by total matches descending. Results without an archetype are bucketed
  # under an "Unknown" entry.
  def archetype_breakdown(results = deck_results)
    entries = {}

    results.group_by(&:archetype).each do |archetype, group|
      counts = result_counts(group)

      if archetype.nil?
        entry = entries["unknown"] ||= { name: "Unknown", counts: result_counts([]), children: [] }
        merge_counts!(entry[:counts], counts)
        next
      end

      parent = archetype.parent || archetype
      entry = entries[parent.id] ||= { name: parent.name, counts: result_counts([]), children: [] }
      merge_counts!(entry[:counts], counts)
      entry[:children] << { name: archetype.name, counts: counts } if archetype.parent
    end

    entries.values.sort_by { |e| -e[:counts].values.sum }
  end

  private

  # Drops classification fields that don't apply to the current state so we never persist a stale
  # custom format name once the format is no longer "other".
  def clear_inapplicable_classification
    self.other_format_name = nil unless other?
  end

  def merge_counts!(target, source)
    source.each { |k, v| target[k] += v }
  end

  # When a deck stops being physical, its real (owned) copies are released back
  # to the collection's available pool.
  def release_owned_copies_if_not_physical
    return unless saved_change_to_physical? && !physical?

    deck_cards.update_all(owned_copies: 0)
  end
end
