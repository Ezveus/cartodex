# One printing in a DeckVersion and how many copies of it the list played. The CHECK and the
# UNIQUE (deck_version_id, card_id) index are the guarantees; the validations exist for the
# readable error.
class DeckVersionCard < ApplicationRecord
  belongs_to :deck_version
  belongs_to :card

  validates :quantity, presence: true, numericality: { only_integer: true, greater_than: 0 }
end
