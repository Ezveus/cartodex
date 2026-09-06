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
  #
  # There is in fact no destroy action to trigger this anywhere in the app — `resources :cards` is
  # index/show/edit/update in both namespaces — so today this callback and its test are purely
  # defensive, kept for whichever future caller (a console session, a fixture teardown) does
  # destroy a Card first.
  belongs_to :card, optional: true

  # For a Trainer or Energy, `fingerprint` is `SHA256(name)` alone (Card#compute_fingerprint), so
  # this key is really "same name" rather than "same card" for almost everything this feature
  # labels. Accepted trade-off, not a live defect — see the design record's "The decisions" §9 for
  # the measurements and what would flip it.
  validates :fingerprint, presence: true
  validates :source, inclusion: { in: SOURCES }
  # The UNIQUE index is the guarantee; this exists for the readable error — the same division of
  # labour as (set_name, set_number) on Card.
  validates :card_label_id, uniqueness: { scope: :fingerprint }

  scope :active, -> { where(rejected: false) }
  scope :imported, -> { where(source: "imported") }
  scope :suggested, -> { where(source: "suggested") }
  scope :curated, -> { where(source: "curated") }
end
