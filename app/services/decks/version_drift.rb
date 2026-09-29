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
    # `changes` is an ordered subset of CHANGES. `from_label`/`to_label` name the classification
    # on either side — the two pool names for :pool, the two format labels for :format — and are
    # nil when only the list moved. Keyword-initialised so a hand-built result cannot swap them.
    Result = Struct.new(:changes, :latest, :from_label, :to_label, keyword_init: true) do
      def drift? = changes.any?

      # The one sentence every surface prints, composed here so that no view or script spells it.
      def message(number)
        return if changes.empty?

        subjects = changes.map { |change| SUBJECTS.fetch(change) }
        verb = subjects.one? ? "has" : "have"
        sentence = "#{subjects.join(' and ').upcase_first} #{verb} changed since version #{number}"
        sentence += " (#{from_label} → #{to_label})" if from_label
        "#{sentence}."
      end
    end

    CHANGES = %i[cards format pool].freeze
    SUBJECTS = { cards: "the list", format: "the format", pool: "the Standard pool" }.freeze

    CLASSIFICATION = %w[format standard_pool_id other_format_name].freeze

    # The key both sides are tallied on, in Ruby. It must answer what KEY answers in SQL, since
    # Decks::VersionImporter compares a list it holds in memory against versions it reads.
    def self.card_key(card) = card.fingerprint.presence || "card:#{card.id}"

    def initialize(deck)
      @deck = deck
    end

    def call
      latest = @deck.latest_version
      return Result.new(changes: [], latest: nil) if latest.nil?

      changes = []
      changes << :cards if cards_changed?(latest)
      classification = classification_change(latest)
      changes << classification if classification

      Result.new(changes: changes, latest: latest, **labels(classification, latest))
    end

    private

    # :format covers other_format_name as well, since that name *is* the format for "other"; the
    # pool is named on its own only when nothing else about the classification moved, so a format
    # change is never reported as a pool change beside it.
    def classification_change(latest)
      if @deck.format != latest.format || @deck.other_format_name != latest.other_format_name
        :format
      elsif @deck.standard_pool_id != latest.standard_pool_id
        :pool
      end
    end

    # Only a classification change reads a pool's name, so the list-only case stays within the
    # two-query budget.
    def labels(classification, latest)
      case classification
      when :pool then { from_label: latest.standard_pool.name, to_label: @deck.standard_pool.name }
      when :format then { from_label: latest.format_label, to_label: @deck.format_label }
      else {}
      end
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
