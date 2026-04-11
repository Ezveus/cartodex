class DeckResult < ApplicationRecord
  belongs_to :deck
  belongs_to :archetype, optional: true

  RESULTS = %w[win loss draw timeout].freeze

  validates :result, presence: true, inclusion: { in: RESULTS }
end
