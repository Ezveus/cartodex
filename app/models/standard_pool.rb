# One period of the rotating Standard calendar. A period is created by exactly one
# of two events — a set release, which moves the upper bound, or a rotation, which
# moves the lower bound — and players name it by both bounds: "TEF-PBL".
class StandardPool < ApplicationRecord
  belongs_to :first_card_set, class_name: "CardSet"
  belongs_to :last_card_set, class_name: "CardSet"

  # restrict, not the :nullify that Archetype uses for its decks. An archetype is
  # a tag, so dropping it is harmless; a NULL anchor on a Standard deck makes that
  # deck unsavable on its next edit. A referenced pool is corrected, never deleted.
  has_many :decks, dependent: :restrict_with_error
  has_many :tournaments, dependent: :restrict_with_error

  validates :regulation_marks, presence: true
  validates :released_on, presence: true
  validates :legal_on, presence: true
  validates :first_card_set_id, uniqueness: { scope: :last_card_set_id }

  scope :by_release, -> { order(released_on: :desc) }

  # Exists because #name reads both bounds: rendering a pool's name without this
  # costs two extra queries per pool, which is how the deck list and the spotlight
  # search each grew an N+1 the day format_label started naming the pool. Every
  # site that renders a pool's name should read through it.
  scope :named, -> { includes(:first_card_set, :last_card_set) }

  # The oldest legal set, then the newest — the name players already use.
  def name = "#{first_card_set.code}-#{last_card_set.code}"

  # The pool a new deck is pre-anchored to. Filtered on released_on rather than
  # simply taking the newest row: a pool seeded for an announced set must not
  # become the default before that set exists.
  def self.current = where(released_on: ..Date.current).by_release.first

  # The pool a tournament held on `date` was played under. Reads legal_on, since
  # a set is tournament-legal about two weeks after it releases.
  def self.at(date) = where(legal_on: ..date).order(legal_on: :desc).first

end
