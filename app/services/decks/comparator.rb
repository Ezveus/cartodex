module Decks
  # Builds a side-by-side comparison of 2 to 4 decks: a unified, type-grouped
  # card table with one quantity column per deck, per-type subtotals (the type
  # breakdown) and grand totals. Cards are matched by name within a type, so
  # different prints of the same card are merged into a single row.
  class Comparator < ApplicationService
    TYPE_ORDER = %w[Pokémon Trainer Energy].freeze

    def initialize(decks)
      @decks = decks
    end

    def call
      {
        decks: @decks,
        groups: build_groups,
        totals: @decks.map { |deck| deck.deck_cards.sum(&:quantity) }
      }
    end

    private

    def build_groups
      TYPE_ORDER.filter_map do |type|
        rows = build_rows(type)
        next if rows.empty?

        {
          type: type,
          rows: rows,
          subtotals: @decks.map { |deck| rows.sum { |row| row[:quantities][deck.id] || 0 } }
        }
      end
    end

    # One row per distinct card name within the type, sorted alphabetically.
    def build_rows(type)
      rows = {}

      @decks.each do |deck|
        deck.deck_cards.each do |deck_card|
          card = deck_card.card
          next unless card.card_type == type

          row = rows[card.name] ||= { name: card.name, quantities: Hash.new(0) }
          row[:quantities][deck.id] += deck_card.quantity
        end
      end

      rows.values.sort_by { |row| row[:name] }.each do |row|
        row[:differ] = @decks.map { |deck| row[:quantities][deck.id] }.uniq.size > 1
      end
    end
  end
end
