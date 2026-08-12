class Card < ApplicationRecord
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

  # Case-insensitive name substring match.
  #
  # Matched against `name_normalized` (see #normalize_name) rather than against
  # `name`, because SQLite's LIKE only folds ASCII A–Z: `name LIKE '%POKÉMON%'`
  # never matches "Pokémon", so an accented query in the wrong case silently
  # returned nothing. Normalising both sides in Ruby makes the fold Unicode-aware
  # and keeps the comparison a plain LIKE the database can run.
  #
  # The query's LIKE metacharacters are escaped so a `%` or `_` typed by a user
  # matches literally instead of acting as a wildcard. ESCAPE is required, not
  # decorative: sanitize_sql_like escapes with a backslash, but SQLite's LIKE has
  # no default escape character, so without the clause the backslash itself would
  # be matched. ESCAPE is standard SQL, so this survives the move to PostgreSQL
  # contemplated in #62.
  scope :name_matching, ->(query) {
    where("cards.name_normalized LIKE ? ESCAPE '\\'", "%#{sanitize_sql_like(query.to_s.downcase)}%")
  }

  # Callbacks
  before_save :compute_fingerprint
  before_save :normalize_name

  # Validations
  validates :name, presence: true
  validates :card_type, presence: true, inclusion: { in: CARD_TYPES }
  validates :set_name, presence: true
  validates :set_number, presence: true
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

  # Mirror of `name`, Unicode-downcased, so name_matching can search with a plain
  # LIKE instead of depending on the database's own case folding. Fixtures insert
  # rows without callbacks, so cards.yml carries the column explicitly — a
  # CardTest case keeps the two spellings in step.
  def normalize_name
    self.name_normalized = name&.downcase
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
