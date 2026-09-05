# One label on one card — where "one card" is a fingerprint, not a printing: what a card is and
# what it does are properties of the card, and every printing of Prime Catcher is an ACE SPEC.
#
# `source` is what decides who may overwrite whom. The importer writes `imported` rows and touches
# nothing else; stage 2's suggester rewrites only its own `suggested` rows; a `curated` row is a
# human decision and is never overwritten by anything automatic. A `curated` row with `rejected`
# set is that human saying no, kept rather than deleted so the next run does not undo the refusal.
class CardLabelAssignment < ApplicationRecord
  SOURCES = %w[imported suggested curated].freeze

  belongs_to :card_label
  # The printing the decision came from. Optional, and nullified rather than cascaded: deleting a
  # printing from the admin panel must not delete what was decided about the card.
  belongs_to :card, optional: true

  validates :fingerprint, presence: true
  validates :source, inclusion: { in: SOURCES }
  # The UNIQUE index is the guarantee; this exists for the readable error — the same division of
  # labour as (set_name, set_number) on Card.
  validates :card_label_id, uniqueness: { scope: :fingerprint }

  scope :active, -> { where(rejected: false) }
  scope :imported, -> { where(source: "imported") }
end
