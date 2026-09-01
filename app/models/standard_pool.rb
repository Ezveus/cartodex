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
  # A regulation mark is a single uppercase letter printed on the card. Nothing reads
  # the marks yet (#27, #61 and #125 will), which is exactly why a malformed one has
  # to be refused at the door: it would sit unnoticed until the first consumer.
  validate :regulation_marks_are_single_letters
  # Legality follows existence: a pool cannot be legal in an event before its cards
  # are printed. The admin screen can type either date, so the order is checked here.
  validate :legal_on_not_before_released_on

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

  private

  def regulation_marks_are_single_letters
    marks = regulation_marks
    return if marks.blank?

    unless marks.is_a?(Array)
      errors.add(:regulation_marks, "must be a list of single-letter marks")
      return
    end

    return if marks.all? { |mark| mark.to_s.match?(/\A[A-Z]\z/) }

    errors.add(:regulation_marks, "must each be a single uppercase letter, e.g. H")
  end

  def legal_on_not_before_released_on
    return if legal_on.blank? || released_on.blank?
    return if legal_on >= released_on

    errors.add(:legal_on, "can't be before the release date")
  end
end
