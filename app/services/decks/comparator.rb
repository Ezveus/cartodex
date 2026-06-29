module Decks
  # Builds a side-by-side comparison of 2 to 4 decks: a unified, type-grouped
  # card table with one quantity column per deck, per-type subtotals (the type
  # breakdown) and grand totals. Cards are matched by fingerprint within a type,
  # so functionally identical prints merge into one row while genuinely different
  # cards that happen to share a name (e.g. Froakie CRI 20 vs TWM 56) stay apart.
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

    # One row per distinct fingerprint within the type, sorted by name then
    # print. Each row keeps a representative card so the view can link to it.
    def build_rows(type)
      rows = {}

      @decks.each do |deck|
        deck.deck_cards.each do |deck_card|
          card = deck_card.card
          next unless card.card_type == type

          row = rows[card.fingerprint] ||= { card: card, name: card.name, quantities: Hash.new(0) }
          row[:quantities][deck.id] += deck_card.quantity
        end
      end

      rows.values
          .sort_by { |row| [ row[:name], row[:card].set_name.to_s, row[:card].set_number.to_s ] }
          .each do |row|
        row[:differ] = @decks.map { |deck| row[:quantities][deck.id] }.uniq.size > 1
      end
    end
  end
end
