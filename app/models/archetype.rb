class Archetype < ApplicationRecord
  include NameNormalizable

  belongs_to :primary_card, class_name: "Card"
  belongs_to :secondary_card, class_name: "Card", optional: true
  belongs_to :parent, class_name: "Archetype", optional: true
  has_many :children, class_name: "Archetype", foreign_key: :parent_id, dependent: :nullify
  has_many :deck_results, dependent: :nullify
  has_many :decks, dependent: :nullify
  # restrict_with_error, unlike this model's :nullify cascades above — archetype_id is NOT NULL
  # on a standing, so nullifying is not available. A standing is another member's public record
  # of a real placement, and deleting an archetype *tag* does not remove the reason that
  # placement exists; destroying it behind a confirmation that only ever said "Archetype" is the
  # bug StandardPool#decks, Tournament#entries, TournamentProfile#tournament_entries and
  # Deck#tournament_entries all carry this same cascade to avoid. Leaving the association off
  # entirely is not the neutral option it looks like: the admin panel has a reachable destroy and
  # the FK carries no on_delete, so it would raise a bare ActiveRecord::InvalidForeignKey.
  has_many :tournament_standings, dependent: :restrict_with_error

  validates :name, presence: true
  # These two are denormalised copies of the member cards' fingerprints, and they
  # back the unique index — identity is the fingerprint pair, not the card-id
  # pair, so designating another printing of the same card is the same archetype.
  # The presence check turns "this card has never been scraped" into a readable
  # error instead of a NOT NULL violation.
  validates :primary_fingerprint, presence: true
  # "" means "no secondary" — a *present* secondary card that resolves to "" has
  # simply never been scraped, which is not the same state, and must not be
  # silently treated as single-member (it would then be free to collide with an
  # unrelated single-member archetype on the same primary).
  validates :secondary_fingerprint, presence: true, if: -> { secondary_card_id.present? }
  validates :primary_fingerprint, uniqueness: { scope: :secondary_fingerprint }
  # Both errors land on :name, and neither on :slug. Nobody types a slug — the admin form has a
  # name field and nothing else — so "Slug has already been taken" would name a field that does
  # not exist. See #slug_is_addressable_and_unique for what each half refuses.
  validate :slug_is_addressable_and_unique

  before_validation :sync_fingerprints
  before_validation :auto_generate_name, unless: :custom_name?
  # normalize_name here as well as in NameNormalizable's own before_save, the addition Tournament
  # already carries for the same reason: assign_slug below reads name_normalized, and a
  # before_save mirror is still stale at validation time.
  #
  # The order of these two lines is load-bearing and is what ArchetypeTest's "an archetype named
  # by its member cards gets the slug of the generated name" holds down: auto_generate_name is
  # what produces the name when nobody typed one, so a slug assigned before it would be blank —
  # and blank is refused, which would turn every Api::ArchetypesController create into a 422.
  before_validation :normalize_name
  before_validation :assign_slug

  scope :roots, -> { where(parent_id: nil) }
  # Matches the archetype's own name or either member card's, all three through their
  # normalized mirrors (see NameNormalizable). Every LIKE needs its own ESCAPE clause. Spans
  # three columns, so it can't delegate to the concern's single-column scope.
  scope :search, ->(q) {
    like = "LIKE :q ESCAPE '\\'"
    left_joins(:primary_card, :secondary_card)
      .where(
        "archetypes.name_normalized #{like} OR cards.name_normalized #{like} " \
        "OR secondary_cards_archetypes.name_normalized #{like}",
        q: "%#{normalize_for_match(q)}%"
      )
      .distinct
  }

  attr_accessor :custom_name

  # Energy type of the lead card, used to colour the archetype's badge. Nil for a
  # Trainer- or Energy-led archetype, which the badge already falls back on.
  def primary_energy_type
    primary_card&.type_symbol
  end

  # Distinct energy types of the archetype's member cards, primary first.
  def energy_types
    [ primary_card, secondary_card ].compact.map(&:type_symbol).compact.uniq
  end

  # The archetype's address, everywhere: `to_param` returns it, so every archetype_path and
  # admin_archetype_path in the app emits it without an edit, and the two lookups that resolve
  # one (ArchetypesController#show, Admin::ArchetypesController#set_archetype) key on this
  # column. No fallback to the id: a record whose callbacks have not run has no address, and a
  # component test that renders an unpersisted archetype spells the slug out by hand, the rule
  # the fixtures already follow for name_normalized.
  #
  # **The value in the database, not the one in memory**, and that is not a nicety: an address
  # names a row as it is stored. `assign_slug` runs before_validation, so a *rejected* update
  # leaves the new name's slug on the in-memory record — and in the one case the uniqueness
  # validation exists for, that slug is another archetype's. Reading the dirty attribute made
  # `Admin::ArchetypesController#update`'s `render :edit` emit a form posting to
  # /admin/archetypes/<the other archetype>, so the admin's corrected resubmission renamed the
  # wrong row, with a 200 and no error anywhere. Admin::ArchetypesControllerTest pins it.
  #
  # `slug_in_database` is nil only for a new record, which is what the `||` covers — and a new
  # record's `_path` is a collection path anyway.
  def to_param = slug_in_database || slug

  private

  def custom_name?
    custom_name.present?
  end

  # name_normalized, not name: parameterize folds case and runs of separators itself, so the two
  # agree on every name measured — but deriving from the mirror is the cheaper claim to keep
  # true, and it makes `slug == name_normalized.parameterize` an invariant a test can assert over
  # every row, fixtures included.
  def assign_slug
    self.slug = name_normalized.to_s.parameterize
  end

  # Two refusals, both about the URL and both reported on :name.
  #
  # Blank: parameterize transliterates, so every one of the 1806 distinct card names in the
  # catalogue produces something (Flabébé → flabebe, Nidoran♀ → nidoran, Heat Factory ♢ →
  # heat-factory). It returns "" only for a name with no Latin-transliterable character at all,
  # which is what #111 (Japanese card sets) will produce and what this refusal is the written
  # record of.
  #
  # Taken: two archetypes may differ by nothing but punctuation, and the slug is what makes that
  # a collision — measured, two pairs of card names in the whole catalogue collide
  # (Nidoran♀/Nidoran♂ and Team Rocket's Nidoran♀/♂). Refused rather than disambiguated with a
  # suffix, because a suffix breaks "the name decides the URL" and because the escape hatch is
  # the custom name the admin is already typing. The message names the archetype in the way so
  # that they can.
  def slug_is_addressable_and_unique
    if slug.blank?
      errors.add(:name, "must contain at least one letter or digit that can appear in a URL")
      return
    end

    conflict = Archetype.where(slug: slug).where.not(id: id).first
    return if conflict.nil?

    errors.add(:name, "is too close to #{conflict.name.inspect}, which already has the " \
                      "address /archetypes/#{slug} — give this archetype a name of its own")
  end

  def auto_generate_name
    parts = [ primary_card&.name, secondary_card&.name ].compact
    self.name = parts.join(" / ") if parts.any?
  end

  # A missing secondary is the empty string, never nil: SQLite treats NULLs as
  # distinct, so a nil would let the pair index accept duplicate single-member
  # archetypes. Nothing *decides* anything from these columns — detection joins
  # `cards` and reads the live fingerprint — so drift after a re-scrape is
  # harmless, and Archetypes::FingerprintSync is what brings them back in step.
  def sync_fingerprints
    self.primary_fingerprint = primary_card&.fingerprint
    self.secondary_fingerprint = secondary_card&.fingerprint.to_s
  end
end
