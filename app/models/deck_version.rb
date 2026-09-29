# One list a deck was played with: per-printing quantities and the classification, frozen at
# effective_at. A deck is edited in place, the way its cards are on the table, while its results
# and participations point here — so a match stays filed under the list it was played with after
# the list has moved on. Content is immutable once written; only effective_at may be corrected.
#
# Allocation (owned_copies) is deliberately not snapshotted: it is what the collection holds
# today, not a property of the list that was played.
class DeckVersion < ApplicationRecord
  include FormatLabelled

  belongs_to :deck
  belongs_to :standard_pool, optional: true
  has_many :deck_version_cards, dependent: :destroy
  # restrict_with_error on both: a version is deletable only once nothing was played with it.
  # DeckVersionsController#destroy names what is in the way.
  has_many :deck_results, dependent: :restrict_with_error
  has_many :tournament_entries, dependent: :restrict_with_error

  enum :format, Deck.formats, validate: true

  validates :effective_at, presence: true
  validate :effective_at_not_in_the_future
  validate :effective_at_stays_between_neighbours, on: :update, if: :effective_at_changed?

  # The order a version's number is its rank in. `id` breaks ties, so two versions dated the same
  # instant still number deterministically.
  scope :ordered, -> { order(:effective_at, :id) }

  # Written by Deck#ordered_versions, which numbers a whole list in one query.
  attr_writer :number

  # Never stored, because inserting an earlier version has to renumber every later one. Computed
  # with one COUNT when nothing wrote it — so a view printing many versions must go through
  # Deck#ordered_versions instead.
  def number
    return @number if @number
    return if new_record?

    DeckVersion.where(deck_id: deck_id)
      .where("effective_at < :at OR (effective_at = :at AND id <= :id)", at: effective_at, id: id)
      .count
  end

  def label = "v#{number}"

  # What Decks::Comparator callers print as a column header.
  def name = label

  # The duck type Decks::Comparator reads: rows answering `card` and `quantity`.
  def deck_cards = deck_version_cards

  private

  # A date is corrected, never used to reorder. Moving past a neighbour would bypass both of the
  # import's rules at once — an old list becoming the latest one drift is measured against, or two
  # identical lists ending up side by side — so the edit keeps the version where it ranks. Strict
  # on both sides: at a neighbour's exact instant the id decides the rank, and that is a reorder.
  def effective_at_stays_between_neighbours
    return if effective_at.nil?

    siblings = DeckVersion.where(deck_id: deck_id).order(:effective_at, :id).to_a
    index = siblings.index { |sibling| sibling.id == id }
    before = siblings[index - 1] if index.positive?
    after = siblings[index + 1]
    return if (before.nil? || effective_at > before.effective_at) && (after.nil? || effective_at < after.effective_at)

    errors.add(:base, neighbour_bounds(before && [ index, before ], after && [ index + 2, after ]))
  end

  def neighbour_bounds(before, after)
    bound = ->((number, version)) { "v#{number} (#{version.effective_at.strftime('%B %-d, %Y')})" }
    return "Effective from must stay between #{bound.(before)} and #{bound.(after)}" if before && after
    return "Effective from must be before #{bound.(after)}" if after

    "Effective from must be after #{bound.(before)}"
  end

  def effective_at_not_in_the_future
    return if effective_at.nil? || effective_at <= Time.current

    errors.add(:effective_at, "can't be in the future")
  end
end
