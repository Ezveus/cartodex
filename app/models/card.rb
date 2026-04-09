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

  # Callbacks
  before_save :compute_fingerprint

  # Validations
  validates :name, presence: true
  validates :card_type, presence: true, inclusion: { in: %w[Pokémon Energy Trainer] }
  validates :set_name, presence: true
  validates :set_number, presence: true
  validates :rarity, presence: true, unless: -> { subtype == "Basic Energy" }

  # Conditional validations for Pokémon cards
  with_options if: -> { card_type == "Pokémon" } do
    validates :hp, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :type_symbol, presence: true, inclusion: {
      in: %w[Grass Fire Water Lightning Fighting Psychic Darkness Metal Fairy Dragon Colorless]
    }
    validates :retreat_cost, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
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
