class DeckCard < ApplicationRecord
  belongs_to :deck
  belongs_to :card

  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :owned_copies, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :card_id, uniqueness: { scope: :deck_id }
  validate :owned_copies_within_quantity
  validate :owned_copies_zero_unless_physical

  private

  def owned_copies_within_quantity
    return if owned_copies.nil? || quantity.nil?

    errors.add(:owned_copies, "cannot exceed quantity") if owned_copies > quantity
  end

  def owned_copies_zero_unless_physical
    return if owned_copies.to_i.zero?

    errors.add(:owned_copies, "must be 0 for a non-physical deck") unless deck&.physical?
  end
end
