class Deck < ApplicationRecord
  include NameNormalizable

  # Nullable since tournament standings: a field list belongs to an event, not to a member.
  # Every allocation service that reads deck.user sits behind an owner-only policy that a nil
  # user can never satisfy, so all of them are unreachable for such a deck by construction
  # rather than by convention — see ownerless_deck_is_shared_and_virtual below.
  belongs_to :user, optional: true
  belongs_to :archetype, optional: true
  # Which Standard the deck was built for. Standard rotates, so its name alone
  # does not identify a card pool; every other format is eternal and has no anchor.
  belongs_to :standard_pool, optional: true
  has_many :deck_cards, dependent: :destroy
  has_many :cards, through: :deck_cards
  has_many :deck_results, dependent: :destroy
  # restrict_with_error, not :destroy — the same call Tournament#entries and
  # TournamentProfile#tournament_entries make. A participation records a placement, CP and a
  # profile, and this cascade left the *event* standing while the player's own record of
  # attending it vanished behind a confirmation that only mentioned cards and results.
  # User#tournament_entries is declared ahead of User#decks precisely so account cancellation
  # empties the entries before it reaches this rule — see the note there.
  has_many :tournament_entries, dependent: :restrict_with_error
  # :nullify, the reverse direction of #destroy_if_ownerless (called by
  # TournamentStanding#destroy_ownerless_deck on destroy, and by
  # Tournaments::StandingListImportJob when a re-import replaces a standing's field list).
  # Nothing else in the app destroys an ownerless deck — there is no Admin::DecksController
  # destroy action, and every other deck write is scoped to a member's own decks, which an
  # ownerless deck is in none of — so this is the backstop for any future caller: without it, a
  # deck destroyed some other way would leave the standing pointing at a dangling deck_id and its
  # row's list link 404ing.
  has_one :tournament_standing, dependent: :nullify

  enum :format, { standard: "standard", glc: "glc", expanded: "expanded", other: "other" }, validate: true

  FORMAT_LABELS = {
    "standard" => "Standard",
    "glc"      => "GLC",
    "expanded" => "Expanded",
    "other"    => "Other"
  }.freeze

  # SecureRandom.urlsafe_base64(16) yields 22 URL-safe characters and 128 bits of entropy.
  # The length is fixed on purpose: a key can therefore never collide with a literal path
  # segment such as "shared", which Stage 2 adds as a collection route.
  KEY_BYTES = 16

  validates :name, presence: true
  validates :other_format_name, presence: true, if: :other?
  validates :standard_pool, presence: true, if: :standard?
  validates :key, presence: true
  validate :ownerless_deck_is_shared_and_virtual

  before_validation :clear_inapplicable_classification
  before_validation :assign_key, if: -> { key.blank? }
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

  # The pool *and both of its bounds*, because StandardPool#name reads them: preloading the
  # pool alone still costs two queries per distinct pool. Every listing that renders a deck's
  # format badge wants this — the two deck indexes, the dashboard showcase, the spotlight's two
  # deck groups and the list_decks MCP tool — and each used to spell it out and re-explain it.
  scope :with_standard_pool, -> { includes(standard_pool: [ :first_card_set, :last_card_set ]) }

  # Written by hand, not generated: Active Record refuses to define a scope named `public`
  # or `private`, since both are Module methods. `shared`/`unshared` is also the vocabulary
  # the Share modal and the badge use, so the column, the scopes and the UI agree.
  scope :shared, -> { where(shared: true) }
  scope :unshared, -> { where(shared: false) }

  # Human-readable format label. For the "other" format the user-supplied name
  # takes precedence when present; for Standard the pool is named, since
  # "Standard" alone does not identify a card pool.
  def format_label
    return other_format_name if other? && other_format_name.present?

    base = FORMAT_LABELS.fetch(format, format.to_s.humanize)
    return base unless standard? && standard_pool

    "#{base} (#{standard_pool.name})"
  end

  # Who to print in the admin panel's three deck listings. Named here rather than repeated as
  # `deck.user&.email || "…"` in each of them: all three read `deck.user.email` and all three
  # raised the day user_id became nullable.
  def owner_label = user&.email || "Tournament field list"

  # The one destroy path an ownerless deck has. Guarded here rather than left to each caller,
  # because both of today's callers (TournamentStanding#destroy_ownerless_deck,
  # Tournaments::StandingListImportJob replacing a standing's field list) need the identical
  # guard against a future caller detonating a member's own deck by mistake.
  def destroy_if_ownerless
    destroy if user_id.nil?
  end

  def to_param = key

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

  # An ownerless deck is a tournament field list: it belongs to an event, not to a member. It
  # must be shared, because /decks/shared is the only listing that can show it, and it must not
  # be physical, because `physical` is what makes a deck consume a collection and there is no
  # collection to consume.
  def ownerless_deck_is_shared_and_virtual
    return if user_id.present?

    errors.add(:shared, "must be true for a deck with no owner") unless shared?
    errors.add(:physical, "must be false for a deck with no owner") if physical?
  end

  # Drops classification fields that don't apply to the current state so we never persist a stale
  # custom format name once the format is no longer "other".
  def clear_inapplicable_classification
    self.other_format_name = nil unless other?
    self.standard_pool_id = nil unless standard?
  end

  def merge_counts!(target, source)
    source.each { |k, v| target[k] += v }
  end

  # The deck's address, everywhere: `to_param` returns it, so every URL of this deck is
  # built from it. before_validation rather than before_create so that the callback and the
  # presence validation agree — with before_create, `Deck.new(name: "x").valid?` would be
  # false while `save` succeeded. The `key.blank?` guard stops an update from rewriting it
  # (before_validation runs on update too) and heals a row written by a callback-bypassing
  # insert. There is no uniqueness validation: it would add a SELECT to every deck save to
  # guard a 128-bit collision that will not happen, and the UNIQUE index is the guarantee —
  # the same division of labour as `(set_name, set_number)` on Card.
  def assign_key
    self.key = SecureRandom.urlsafe_base64(KEY_BYTES)
  end

  # When a deck stops being physical, its real (owned) copies are released back
  # to the collection's available pool.
  def release_owned_copies_if_not_physical
    return unless saved_change_to_physical? && !physical?

    deck_cards.update_all(owned_copies: 0)
  end
end
