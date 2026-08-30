class Card < ApplicationRecord
  include NameNormalizable

  # Relationships
  belongs_to :card_set, optional: true
  belongs_to :pokemon_subtype, optional: true
  has_many :attacks, -> { order(:position) }, dependent: :destroy
  has_many :abilities, -> { order(:position) }, dependent: :destroy
  has_many :collections, dependent: :destroy
  has_many :users, through: :collections
  has_many :deck_cards, dependent: :destroy
  has_many :decks, through: :deck_cards

  # Allowed values
  CARD_TYPES = %w[Pokémon Energy Trainer].freeze
  ENERGY_TYPES = %w[Grass Fire Water Lightning Fighting Psychic Darkness Metal Fairy Dragon Colorless].freeze

  # Maps each energy type to the design-system colour token that represents it.
  # Lightning reads as the "bolt" token; Colorless borrows the neutral metal grey.
  TYPE_TOKENS = {
    "Grass" => "grass", "Fire" => "fire", "Water" => "water", "Lightning" => "bolt",
    "Fighting" => "fighting", "Psychic" => "psychic", "Darkness" => "darkness",
    "Metal" => "metal", "Fairy" => "fairy", "Dragon" => "dragon", "Colorless" => "metal"
  }.freeze

  # Callbacks
  before_save :compute_fingerprint

  # Validations
  validates :name, presence: true
  validates :card_type, presence: true, inclusion: { in: CARD_TYPES }
  validates :set_name, presence: true
  # A printing is identified by its set and number — Cards::Fetcher looks cards
  # up by exactly this pair, so two rows sharing it would make that lookup
  # arbitrary. The unique index is the real guarantee; this is here for the
  # readable error.
  validates :set_number, presence: true, uniqueness: { scope: :set_name }
  validates :rarity, presence: true, unless: -> { subtype == "Basic Energy" }

  # Conditional validations for Pokémon cards
  with_options if: -> { card_type == "Pokémon" } do
    validates :hp, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :type_symbol, presence: true, inclusion: { in: ENERGY_TYPES }
    validates :retreat_cost, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end

  # CSS class slug for this card's energy type, e.g. "fire" or "lightning".
  def type_slug
    type_symbol&.downcase
  end

  # CSS colour reference for this card's energy type, e.g. "var(--fire)".
  def type_color
    token = TYPE_TOKENS[type_symbol]
    "var(--#{token})" if token
  end

  def compute_fingerprint
    self.fingerprint = if card_type == "Pokémon"
      data = [ name, hp, type_symbol,
               attacks.sort_by(&:position).map { |a| [ a.name, a.cost, a.damage ] },
               abilities.sort_by(&:position).map(&:name) ]
      Digest::SHA256.hexdigest(data.to_json)[0, 16]
    else
      Digest::SHA256.hexdigest(name.to_s)[0, 16]
    end
  end
end
