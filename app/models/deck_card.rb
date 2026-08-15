class DeckCard < ApplicationRecord
  belongs_to :deck
  belongs_to :card

  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :owned_copies, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :card_id, uniqueness: { scope: :deck_id }
  validate :owned_copies_within_quantity
  validate :owned_copies_zero_unless_physical

  # Rows holding at least one copy that no owned card backs. Says nothing about the deck being
  # physical — on its own it matches every card of a TCG Live deck, which sits at owned_copies 0
  # by construction. Deck.with_proxies is what adds that half of the condition.
  scope :with_proxies, -> { where("owned_copies < quantity") }

  # Copies in this deck not backed by an owned card. Derived, never stored.
  def proxies
    quantity.to_i - owned_copies.to_i
  end

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
