class Archetype < ApplicationRecord
  include NameNormalizable

  belongs_to :primary_card, class_name: "Card"
  belongs_to :secondary_card, class_name: "Card", optional: true
  belongs_to :parent, class_name: "Archetype", optional: true
  has_many :children, class_name: "Archetype", foreign_key: :parent_id, dependent: :nullify
  has_many :deck_results, dependent: :nullify
  has_many :decks, dependent: :nullify

  validates :name, presence: true
  validates :primary_card_id, uniqueness: { scope: :secondary_card_id }

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
end
