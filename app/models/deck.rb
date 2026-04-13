class Deck < ApplicationRecord
  belongs_to :user
  has_many :deck_cards, dependent: :destroy
  has_many :cards, through: :deck_cards
  has_many :deck_results, dependent: :destroy

  validates :name, presence: true

  def result_counts(results = deck_results)
    counts = DeckResult::RESULTS.index_with(0)
    results.each { |r| counts[r.result] += 1 if counts.key?(r.result) }
    counts
  end

  # Builds a parent-grouped archetype breakdown of the given results.
  # Returns an array of { name:, counts:, children: [{ name:, counts: }, ...] },
  # sorted by total matches descending. Results without an archetype are bucketed
  # under an "Unknown" entry.
  def archetype_breakdown(results = deck_results)
    entries = {}

    results.group_by(&:archetype).each do |archetype, group|
      counts = result_counts(group)

      if archetype.nil?
        entry = entries["unknown"] ||= { name: "Unknown", counts: result_counts([]), children: [] }
        merge_counts!(entry[:counts], counts)
        next
      end

      parent = archetype.parent || archetype
      entry = entries[parent.id] ||= { name: parent.name, counts: result_counts([]), children: [] }
      merge_counts!(entry[:counts], counts)
      entry[:children] << { name: archetype.name, counts: counts } if archetype.parent
    end

    entries.values.sort_by { |e| -e[:counts].values.sum }
  end

  private

  def merge_counts!(target, source)
    source.each { |k, v| target[k] += v }
  end
end
