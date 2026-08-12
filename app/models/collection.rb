class Collection < ApplicationRecord
  belongs_to :user
  belongs_to :card

  # Validations
  validates :quantity, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :user_id, uniqueness: { scope: :card_id, message: "already has this card in collection" }

  # Scopes
  scope :with_cards, -> { where("quantity > 0") }
  # Held once so the collection page and the MCP tool cannot drift apart on what
  # "filtered by card name" means; see Card.name_matching for the matching rules.
  scope :card_name_matching, ->(query) { joins(:card).merge(Card.name_matching(query)) }
end
