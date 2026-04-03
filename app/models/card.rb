class Card < ApplicationRecord
  # Relationships
  has_many :attacks, -> { order(:position) }, dependent: :destroy
  has_many :collections, dependent: :destroy
  has_many :users, through: :collections
  has_many :deck_cards, dependent: :destroy
  has_many :decks, through: :deck_cards

  # Validations
  validates :name, presence: true
  validates :card_type, presence: true, inclusion: { in: %w[Pokémon Energy Trainer] }
  validates :set_name, presence: true
  validates :set_number, presence: true
  validates :rarity, presence: true

  # Conditional validations for Pokémon cards
  with_options if: -> { card_type == "Pokémon" } do
    validates :hp, presence: true, numericality: { only_integer: true, greater_than: 0 }
    validates :type_symbol, presence: true, inclusion: {
      in: %w[Grass Fire Water Lightning Fighting Psychic Darkness Metal Fairy Dragon Colorless]
    }
    validates :retreat_cost, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
end
