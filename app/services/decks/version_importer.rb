module Decks
  # "Add an earlier version": a pasted decklist becomes a DeckVersion, for a list that was played
  # before versions existed and is therefore nowhere in the database.
  #
  # It refuses rather than guesses, everywhere Decks::Fetcher is lenient. Fetcher drops a line it
  # cannot read and imports a shorter deck; this names the line. Fetcher scrapes a printing it does
  # not hold; this resolves through Cards::ReferenceResolver, which never fetches, and names the
  # reference. One refusal of either kind writes nothing, so correcting the list and resubmitting
  # it is always safe.
  #
  # Two refusals are about the history rather than the list. The version must be dated strictly
  # before the latest one: a later list is the live deck's to record, by snapshot, and an import
  # dated after it would renumber the version the deck is compared against. And it must differ
  # from its neighbours — the versions just before and just after its date — compared exactly as
  # Decks::VersionDrift compares, since a copy of a neighbour splits one list's results in two.
  class VersionImporter < ApplicationService
    Result = Struct.new(:version, :errors)

    # What a PTCG Live export puts between its card lines. Anything else is refused by name.
    SECTION_HEADER_RE = /\A(Pokémon|Trainer|Energy|Total Cards):\s*\d+\z/

    NO_CARD_LINE = "The list holds no card line.".freeze
    NO_VERSION = "Record the current list as version 1 first: an earlier version is dated before it.".freeze

    # A deck is sixty cards: a line beyond that is a typo, and a zero is not a card.
    QUANTITY_RANGE = (1..60)

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

      @decklist.each_line.with_index(1) do |raw, number|
        line = raw.squish
        next if line.empty? || line.match?(SECTION_HEADER_RE)

        match = line.match(Decks::Fetcher::CARD_LINE_RE)
        if match.nil?
          errors << "Line not understood: #{line}"
        elsif !QUANTITY_RANGE.cover?(match[1].to_i)
          errors << "Line #{number}: quantity must be between #{QUANTITY_RANGE.min} and #{QUANTITY_RANGE.max}."
        else
          entries << { set_code: match[3], set_number: match[4], quantity: match[1].to_i }
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

      serialized_transaction do
        refusal = history_refusal(version, resolved)
        next Result.new(nil, [ refusal ]) if refusal

        version.save!
        Result.new(version, [])
      end
    ensure
      @deck.deck_versions.reset
    end

    # Read inside the write's transaction, so a version recorded meanwhile cannot slip between the
    # check and the insert. Reads the version's cast effective_at, never the posted text.
    def history_refusal(version, resolved)
      versions = @deck.deck_versions.reload.to_a
      latest = versions.last
      return NO_VERSION if latest.nil?

      if version.effective_at >= latest.effective_at
        return "Effective from must be before v#{versions.size} (#{latest.effective_at.strftime('%B %-d, %Y')})."
      end

      identical_neighbour(version, resolved, versions)
    end

    # The new version would rank after every version sharing its instant, since its id is higher.
    def identical_neighbour(version, resolved, versions)
      after = versions.index { |existing| existing.effective_at > version.effective_at }
      neighbours = { after => versions[after], after - 1 => (versions[after - 1] if after.positive?) }.compact

      tallies = neighbour_tallies(neighbours.values)
      tally = Hash.new(0)
      resolved.each { |row| tally[Decks::VersionDrift.card_key(row[:card])] += row[:quantity] }

      index, twin = neighbours.sort.find do |_index, neighbour|
        tallies[neighbour.id] == tally && Decks::VersionDrift::CLASSIFICATION.all? { |column| neighbour[column] == version[column] }
      end
      "This list is identical to v#{index + 1}." if twin
    end

    # One query for both neighbours, keyed the way Decks::VersionDrift keys its SQL.
    def neighbour_tallies(neighbours)
      tallies = neighbours.to_h { |neighbour| [ neighbour.id, Hash.new(0) ] }
      DeckVersionCard.joins(:card).where(deck_version_id: tallies.keys)
        .group(:deck_version_id, Arel.sql(Decks::VersionDrift::KEY)).sum(:quantity)
        .each { |(id, key), quantity| tallies[id][key] += quantity }
      tallies
    end
  end
end
