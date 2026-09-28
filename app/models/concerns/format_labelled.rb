# The classification a Deck carries and a DeckVersion snapshots: a format, a Standard pool when
# the format is Standard, a custom name when it is "other". Shared rather than copied because a
# version is compared against its deck column by column (Decks::VersionDrift) and printed beside
# it, so the two must agree on what a valid classification is and on how it reads.
#
# The including model declares the `format` enum itself; this reads its predicates.
module FormatLabelled
  extend ActiveSupport::Concern

  included do
    validates :other_format_name, presence: true, if: :other?
    validates :standard_pool, presence: true, if: :standard?

    before_validation :clear_inapplicable_classification
  end

  # Human-readable format label. For the "other" format the user-supplied name
  # takes precedence when present; for Standard the pool is named, since
  # "Standard" alone does not identify a card pool.
  def format_label
    return other_format_name if other? && other_format_name.present?

    base = Deck::FORMAT_LABELS.fetch(format, format.to_s.humanize)
    return base unless standard? && standard_pool

    "#{base} (#{standard_pool.name})"
  end

  private

  # Drops classification fields that don't apply to the current state so we never persist a stale
  # custom format name once the format is no longer "other".
  def clear_inapplicable_classification
    self.other_format_name = nil unless other?
    self.standard_pool_id = nil unless standard?
  end
end
