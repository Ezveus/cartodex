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

  # Which printing this row is: "Boss's Orders (PAL 172)". Several cards share a
  # name, and an archetype designates one of them, so every surface where that
  # choice is made or inspected names the printing rather than the card. Both
  # halves are validated present, so there is no partial form to fall back to.
  def printing_label
    "#{name} (#{set_name} #{set_number})"
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

  # The rarity and regulation-mark values actually present in the catalog, for /cards's filter
  # bar. Neither column is indexed, so this is two full scans of `cards` — and /cards is public
  # now, so it was two full scans on every anonymous request. A cache is the honest fix; an
  # index on a low-cardinality column read on every page load is not.
  #
  # A fixed key with a TTL, deliberately not one keyed on Card.maximum(:updated_at): that key
  # was itself an unindexed full-table aggregate, so it paid a scan on every request to protect
  # an entry that nothing ever invalidated. The writers call forget_filter_values instead, and
  # the hour is the backstop for a path that forgets to.
  FILTER_VALUES_CACHE_KEY = "cards/filter-values".freeze
  FILTER_VALUES_TTL = 1.hour

  def self.filter_values
    Rails.cache.fetch(FILTER_VALUES_CACHE_KEY, expires_in: FILTER_VALUES_TTL) do
      [
        where.not(rarity: [ nil, "" ]).distinct.order(:rarity).pluck(:rarity),
        where.not(regulation_mark: [ nil, "" ]).distinct.order(:regulation_mark).pluck(:regulation_mark)
      ]
    end
  end

  # Called by whatever can add a rarity or a regulation mark to the catalog: CardSets::Importer
  # on an import, CardSets::RescrapeJob on a repair (a `force: true` rescrape is the only thing
  # that rewrites an existing card's text at all).
  def self.forget_filter_values
    Rails.cache.delete(FILTER_VALUES_CACHE_KEY)
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
