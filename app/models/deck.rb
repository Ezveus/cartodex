class Deck < ApplicationRecord
  belongs_to :user
  has_many :deck_cards, dependent: :destroy
  has_many :cards, through: :deck_cards
  has_many :deck_results, dependent: :destroy

  validates :name, presence: true
end
