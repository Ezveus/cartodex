module Decks
  # Whether a deck's live list has moved on from its latest version. Compared by fingerprint and
  # summed quantity — the "same card, any printing" key — plus the three classification columns,
  # so a printing swap, a proxy turned real or a re-save is not drift, while a card added, removed
  # or requantified is. A card with no fingerprint has nothing to say two printings are one card,
  # so it is compared by card_id; Decks::Comparator keys its rows the same way, which is what keeps
  # the diff a version page shows in agreement with the drift that sent the reader there.
  #
  # Two queries at most, whatever the deck's size: the latest version, then both card lists in one
  # UNION ALL.
  class VersionDrift < ApplicationService
    Result = Struct.new(:drift, :latest) do
      def drift? = drift
    end

    CLASSIFICATION = %w[format standard_pool_id other_format_name].freeze

    def initialize(deck)
      @deck = deck
    end

    def call
      latest = @deck.latest_version
      return Result.new(false, nil) if latest.nil?

      Result.new(classification_changed?(latest) || cards_changed?(latest), latest)
    end

    private

    def classification_changed?(latest)
      CLASSIFICATION.any? { |column| @deck[column] != latest[column] }
    end

    def cards_changed?(latest)
      live = Hash.new(0)
      recorded = Hash.new(0)

      rows(latest).each do |side, key, quantity|
        (side == "live" ? live : recorded)[key] += quantity
      end

      live != recorded
    end

    def rows(latest)
      sql = ActiveRecord::Base.sanitize_sql_array([ <<~SQL, @deck.id, latest.id ])
        SELECT 'live', #{KEY}, deck_cards.quantity
        FROM deck_cards JOIN cards ON cards.id = deck_cards.card_id
        WHERE deck_cards.deck_id = ? AND deck_cards.quantity > 0
        UNION ALL
        SELECT 'version', #{KEY}, deck_version_cards.quantity
        FROM deck_version_cards JOIN cards ON cards.id = deck_version_cards.card_id
        WHERE deck_version_cards.deck_version_id = ?
      SQL

      ActiveRecord::Base.connection.select_rows(sql)
    end

    # NULLIF as well as COALESCE: an empty fingerprint identifies nothing either.
    KEY = "COALESCE(NULLIF(cards.fingerprint, ''), 'card:' || cards.id)".freeze
  end
end
