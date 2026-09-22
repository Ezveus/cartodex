# "This Limitless deck is that cartodex archetype", decided once by an admin and remembered.
#
# An event's standings sheet names a deck per row — 45 distinct decks over 575 rows on the event
# this was measured against — while `tournament_standings.archetype_id` is NOT NULL, so something
# has to turn one into the other. Nothing here guesses: `Tournaments::ArchetypeProposer` proposes
# from the row's own decklist, an admin confirms or corrects it on the import preview, and only the
# confirmed answer is stored. A deck nobody has mapped is a run that refuses those rows and says
# which deck it refused them for, never a run that picks something plausible.
#
# Why a store rather than a rule: measured on real lists, Decks::ArchetypeDetector alone resolves
# the wrong archetype on 12 rows in 56 — a rule-box tech card outscores the deck's own name card
# (Slowking filed as Lillie's Clefairy ex), and two archetypes tying on score are separated by
# whichever row the database happened to return first. That is tolerable when a member is importing
# their own deck and can see the answer; it is not, 575 rows at a time, in a public wiki-governed
# sheet that says nothing about how the archetype got there.
class LimitlessArchetypeMapping < ApplicationRecord
  belongs_to :archetype

  validates :limitless_deck_id, numericality: { only_integer: true, greater_than: 0 }
  validates :limitless_variant, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :label, presence: true
  validate :reference_is_unique

  # The reference as the results page writes it: "284" for a deck, "284/3" for its third variant.
  # One string because that is what travels — on a Row, in a form field, as a Hash key — and two
  # spellings of one key is how the pair would come apart.
  def self.reference_for(deck_id, variant) = variant.presence ? "#{deck_id}/#{variant}" : deck_id.to_s

  # "284/3" => [284, 3]; "284" => [284, nil]. nil for anything that is not a reference at all, so a
  # caller reading a form field does not have to pre-validate it.
  def self.parse_reference(reference)
    match = /\A(\d+)(?:\/(\d+))?\z/.match(reference.to_s)
    match && [ match[1].to_i, match[2]&.to_i ]
  end

  # { "284" => mapping, "284/3" => mapping } for the references a run actually saw. Keyed on the
  # string so every caller asks the same question the Row answers with.
  #
  # Two `where`s OR'd rather than one null-safe comparison: SQLite spells that `IS` and PostgreSQL
  # spells it `IS NOT DISTINCT FROM`, and #62 is open. `where(variant: nil)` compiles to `IS NULL`
  # on both, so the split costs a branch and buys the query outliving the adapter.
  def self.by_reference(references = nil)
    return all.index_by(&:reference) if references.nil?

    pairs = Array(references).filter_map { |reference| parse_reference(reference) }
    return {} if pairs.empty?

    base, variant = pairs.partition { |_deck_id, v| v.nil? }
    scope = none
    scope = scope.or(where(limitless_deck_id: base.map(&:first), limitless_variant: nil)) if base.any?
    variant.group_by(&:last).each do |value, group|
      scope = scope.or(where(limitless_deck_id: group.map(&:first), limitless_variant: value))
    end
    scope.index_by(&:reference)
  end

  def reference = self.class.reference_for(limitless_deck_id, limitless_variant)

  private

  # The readable half of the two partial UNIQUE indexes — the same division of labour as
  # Tournament#name_and_date_are_unique. Two indexes and not one because SQLite treats NULLs as
  # distinct: a single (deck_id, variant) index never sees two confirmations of the *base* deck
  # collide, and one deck would quietly accumulate a mapping row per confirmation.
  def reference_is_unique
    return if limitless_deck_id.blank?

    clash = self.class.where(limitless_deck_id: limitless_deck_id, limitless_variant: limitless_variant)
    clash = clash.where.not(id: id) if persisted?
    errors.add(:limitless_deck_id, "is already mapped") if clash.exists?
  end
end
