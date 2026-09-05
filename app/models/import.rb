class Import < ApplicationRecord
  belongs_to :user
  # Set by the standings controller alone — a deck or card_set import has no event. It scopes the
  # "Importing…" list on an event page to that event: without it, an import started at one event
  # was listed on every other event's page, where its completion broadcast (targeted by
  # importing-<id>) then mutated a page it had nothing to do with.
  belongs_to :tournament, optional: true

  # "limitless_standings" is a *bulk* run: one Limitless deck-results page spans many events, so
  # unlike "standing_list" — one field list typed into one row of one event's sheet — it has no
  # single tournament to point at and its `tournament_id` deliberately stays nil. What it carries
  # instead is `created_standing_ids`, the receipt Tournaments::StandingsImportUndo reads.
  KINDS = %w[deck card_set standing_list limitless_standings].freeze
  STATUSES = %w[pending completed failed].freeze

  validates :kind, inclusion: { in: KINDS }
  validates :status, inclusion: { in: STATUSES }
  validates :label, presence: true

  scope :pending, -> { where(status: "pending") }
  scope :deck_imports, -> { where(kind: "deck") }
  scope :card_set_imports, -> { where(kind: "card_set") }
  scope :standing_list_imports, -> { where(kind: "standing_list") }
  scope :limitless_standings_imports, -> { where(kind: "limitless_standings") }

  def pending? = status == "pending"
  def completed? = status == "completed"
  def failed? = status == "failed"
end
