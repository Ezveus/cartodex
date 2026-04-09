class CardSet < ApplicationRecord
  has_many :cards, dependent: :nullify

  validates :code, presence: true, uniqueness: true
  validates :name, presence: true

  scope :by_release, -> { order(release_date: :desc) }
end
