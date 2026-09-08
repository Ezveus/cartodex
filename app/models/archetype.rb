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

  # Slugs a route already claims. Derived, not guessed: `resources :archetypes` in the admin
  # namespace emits GET /admin/archetypes/**new** before GET /admin/archetypes/:id, so an
  # archetype slugged "new" has no reachable admin show page and `#create`/`#update`'s
  # `redirect_to admin_archetype_path` lands on a blank New form carrying "Archetype updated."
  # `edit` needs no entry — it is nested under `:id`, so /admin/archetypes/edit matches `show`
  # with id "edit" — and the public resource declares neither, being `only: [:index, :show]`.
  # This list grows if a collection route is ever added to either resource.
  RESERVED_SLUGS = %w[new].freeze

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
  # already carries for the same reason: `derived_slug` reads name_normalized and both the
  # validation above and the callback below read `derived_slug`, so a before_save-only mirror is
  # still stale when the validation runs.
  #
  # Declared after auto_generate_name, and that order is load-bearing: that callback is what
  # produces the name when nobody typed one, so a name normalized before it would be the previous
  # one, or nothing at all — and a blank slug is refused, which would turn every
  # Api::ArchetypesController create into a 422. ArchetypeTest holds it down.
  before_validation :normalize_name
  # **before_save, not before_validation**, and that is what makes the whole dirty-slug hazard
  # unreachable rather than merely handled: a refused update never touches this column, so
  # `to_param` can read it plainly and the re-rendered admin form cannot post to the archetype
  # whose slug the rejected name collided with. The validation asks `derived_slug` instead, so
  # nothing needs the column to be written early.
  before_save :assign_slug

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
  # It can read the column plainly because `assign_slug` is a **before_save**: a rejected update
  # leaves `slug` exactly as the database holds it. That ordering is the whole reason — with a
  # before_validation callback, a refused rename left the *new* name's slug on the record, and in
  # the one case the uniqueness validation exists for that slug is another archetype's, so
  # `Admin::ArchetypesController#update`'s `render :edit` emitted a form posting to
  # /admin/archetypes/<the other archetype> and the admin's corrected resubmission renamed the
  # wrong row, with a 200 and no error anywhere. Admin::ArchetypesControllerTest pins it, and it
  # goes red if the callback moves back.
  def to_param = slug

  private

  def custom_name?
    custom_name.present?
  end

  def assign_slug
    self.slug = derived_slug
  end

  # The one definition of the rule, read by the validation and by the callback. Two readers
  # computing it separately is how the check and the write come to disagree.
  #
  # name_normalized, not name: parameterize folds case and runs of separators itself, so the two
  # agree on every name measured — but deriving from the mirror is the cheaper claim to keep
  # true, and it makes `slug == name_normalized.parameterize` an invariant a test can assert over
  # every row, fixtures included.
  def derived_slug
    name_normalized.to_s.parameterize
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
    candidate = derived_slug

    if candidate.blank?
      errors.add(:name, "must contain at least one letter or digit that can appear in a URL")
      return
    end

    if RESERVED_SLUGS.include?(candidate)
      errors.add(:name, "would give this archetype the address /archetypes/#{candidate}, which " \
                        "is reserved by a route — give it a name of its own")
      return
    end

    conflict = Archetype.where(slug: candidate).where.not(id: id).first
    return if conflict.nil?

    errors.add(:name, "is too close to #{conflict.name.inspect}, which already has the " \
                      "address /archetypes/#{candidate} — give this archetype a name of its own")
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
