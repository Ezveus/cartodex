class Import < ApplicationRecord
  belongs_to :user
  # Set by the standings controller alone — a deck or card_set import has no event. It scopes the
  # "Importing…" list on an event page to that event: without it, an import started at one event
  # was listed on every other event's page, where its completion broadcast (targeted by
  # importing-<id>) then mutated a page it had nothing to do with.
  belongs_to :tournament, optional: true

  KINDS = %w[deck card_set standing_list].freeze
  STATUSES = %w[pending completed failed].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :label, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :deck_imports, -> { where(kind: "deck") }
  scope :card_set_imports, -> { where(kind: "card_set") }
  scope :standing_list_imports, -> { where(kind: "standing_list") }

  def pending? = status == "pending"
  def completed? = status == "completed"
  def failed? = status == "failed"
end
