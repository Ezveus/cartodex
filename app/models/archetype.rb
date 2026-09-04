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

  before_validation :sync_fingerprints
  before_validation :auto_generate_name, unless: :custom_name?

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

  private

  def custom_name?
    custom_name.present?
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
