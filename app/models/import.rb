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
  # "card_labels" is a run of Limitless's card search for one label's `is:` token. Like
  # "limitless_standings" it points at no tournament; unlike it, it leaves no receipt to undo,
  # because a re-run writes exactly the same rows and deletes nothing.
  # "bulk_cards" is one call of add_cards_to_collection or add_cards_to_deck. It is the only kind
  # whose payload really is stored — `receipt` holds every printing it touched with the before and
  # after it moved through — and it is still neither reimportable nor undoable: the add is
  # relative, so replaying it adds the copies a second time (Imports::Replayer refuses it in those
  # words), and an undo has not been asked for.
  KINDS = %w[deck card_set standing_list limitless_standings card_labels bulk_cards].freeze

  # The kinds /admin/imports can run again from `replay_params` — every kind but bulk_cards. An
  # allowlist rather than KINDS minus a refusal, so a kind added tomorrow gets no Reimport button
  # until somebody writes its replay in Imports::Replayer.
  REPLAYABLE_KINDS = %w[deck card_set standing_list limitless_standings card_labels].freeze
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

  # `replay_params` is `{}` on every row written before the column existed (bar card_set, which the
  # migration rebuilt from its label), and on those there is nothing to run again.
  def replayable? = REPLAYABLE_KINDS.include?(kind) && replay_params.present?
end
