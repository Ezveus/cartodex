class Archetype < ApplicationRecord
  belongs_to :primary_pokemon, class_name: "Card"
  belongs_to :secondary_pokemon, class_name: "Card", optional: true
  belongs_to :parent, class_name: "Archetype", optional: true
  has_many :children, class_name: "Archetype", foreign_key: :parent_id, dependent: :nullify
  has_many :deck_results, dependent: :nullify
  has_many :decks, dependent: :nullify

  validates :name, presence: true
  validates :primary_pokemon_id, uniqueness: { scope: :secondary_pokemon_id }

  before_validation :auto_generate_name, unless: :custom_name?

  scope :roots, -> { where(parent_id: nil) }
  scope :search, ->(q) {
    left_joins(:primary_pokemon, :secondary_pokemon)
      .where("archetypes.name LIKE :q OR cards.name LIKE :q OR secondary_pokemons_archetypes.name LIKE :q", q: "%#{q}%")
      .distinct
  }

  attr_accessor :custom_name

  # Energy type of the lead Pokémon, used to colour the archetype's badge.
  def primary_energy_type
    primary_pokemon&.type_symbol
  end

  # Distinct energy types of the archetype's notable Pokémon, primary first.
  def energy_types
    [ primary_pokemon, secondary_pokemon ].compact.map(&:type_symbol).compact.uniq
  end

  private

  def custom_name?
    custom_name.present?
  end

  def auto_generate_name
    parts = [ primary_pokemon&.name, secondary_pokemon&.name ].compact
    self.name = parts.join(" / ") if parts.any?
  end
end
