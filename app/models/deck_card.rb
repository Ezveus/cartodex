class DeckCard < ApplicationRecord
  belongs_to :deck
  belongs_to :card

  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
end
