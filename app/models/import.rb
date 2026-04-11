class Import < ApplicationRecord
  belongs_to :user

  KINDS = %w[deck card_set].freeze
  STATUSES = %w[pending completed failed].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :label, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :deck_imports, -> { where(kind: "deck") }
  scope :card_set_imports, -> { where(kind: "card_set") }

  def pending? = status == "pending"
  def completed? = status == "completed"
  def failed? = status == "failed"
end
