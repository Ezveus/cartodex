class Collection < ApplicationRecord
  belongs_to :user
  belongs_to :card

  # Validations
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :user_id, uniqueness: { scope: :card_id, message: "already has this card in collection" }

  # Scopes
  scope :with_cards, -> { where("quantity > 0") }
end
