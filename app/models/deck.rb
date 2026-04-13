class Deck < ApplicationRecord
  belongs_to :user
  has_many :deck_cards, dependent: :destroy
  has_many :cards, through: :deck_cards
  has_many :deck_results, dependent: :destroy

  validates :name, presence: true

  def result_counts(results = deck_results)
    counts = DeckResult::RESULTS.index_with(0)
    results.each { |r| counts[r.result] += 1 if counts.key?(r.result) }
    counts
  end
end
