module Decks
  # "Add an earlier version": a pasted decklist becomes a DeckVersion, for a list that was played
  # before versions existed and is therefore nowhere in the database.
  #
  # It refuses rather than guesses, everywhere Decks::Fetcher is lenient. Fetcher drops a line it
  # cannot read and imports a shorter deck; this names the line. Fetcher scrapes a printing it does
  # not hold; this resolves through Cards::ReferenceResolver, which never fetches, and names the
  # reference. One refusal of either kind writes nothing, so correcting the list and resubmitting
  # it is always safe.
  class VersionImporter < ApplicationService
    Result = Struct.new(:version, :errors)

    # What a PTCG Live export puts between its card lines. Anything else is refused by name.
    SECTION_HEADER_RE = /\A(Pokémon|Trainer|Energy|Total Cards):\s*\d+\z/

    NO_CARD_LINE = "The list holds no card line.".freeze

    def initialize(deck:, decklist:, effective_at:, format:, standard_pool:, other_format_name:)
      @deck = deck
      @decklist = decklist.to_s
      @effective_at = effective_at
      @format = format
      @standard_pool = standard_pool
      @other_format_name = other_format_name
    end

    def call
      entries, errors = parse
      return Result.new(nil, errors) if errors.any?
      return Result.new(nil, [ NO_CARD_LINE ]) if entries.empty?

      resolution = Cards::ReferenceResolver.call(entries: entries)
      if resolution.unresolved.any?
        return Result.new(nil, resolution.unresolved.map { |ref| "#{ref[:set_code]} #{ref[:set_number]}: #{ref[:reason]}" })
      end

      build_version(resolution.resolved)
    end

    private

    def parse
      entries = []
      errors = []

      @decklist.each_line do |raw|
        line = raw.squish
        next if line.empty? || line.match?(SECTION_HEADER_RE)

        match = line.match(Decks::Fetcher::CARD_LINE_RE)
        if match
          entries << { set_code: match[3], set_number: match[4], quantity: match[1].to_i }
        else
          errors << "Line not understood: #{line}"
        end
      end

      [ entries, errors ]
    end

    def build_version(resolved)
      version = DeckVersion.new(
        deck: @deck, effective_at: @effective_at, format: @format,
        standard_pool: @standard_pool, other_format_name: @other_format_name
      )
      resolved.each { |row| version.deck_version_cards.build(card: row[:card], quantity: row[:quantity]) }

      return Result.new(nil, version.errors.full_messages) unless version.valid?

      serialized_transaction { version.save! }
      @deck.deck_versions.reset
      Result.new(version, [])
    end
  end
end
