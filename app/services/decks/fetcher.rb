# Parse a decklist string and create a Deck with its cards fetched from Limitless
class Decks::Fetcher < ApplicationService
  class ParseError < StandardError; end

  CARD_LINE_RE = /\A(\d+)\s+(.+?)\s+([A-Z]{2,3})\s+(\d+)\z/
  LIMITLESS_BASE_URL = "https://limitlesstcg.com/cards"

  def initialize(decklist, user, name)
    @decklist = decklist
    @user = user
    @name = name
  end

  def call
    card_entries = parse_card_lines
    raise ParseError, "No card lines found in decklist" if card_entries.empty?

    # Cards::Fetcher reads a printing then writes it, so two concurrent imports
    # of the same card must not both miss and both create it. What actually
    # guarantees that is the UNIQUE index on (cards.set_name, set_number): the
    # loser raises instead of duplicating. This is serialized_transaction rather
    # than a plain one for consistency with the other write services and because
    # it stays correct if this is ever called from inside another transaction —
    # not because it changes the locking, which a top-level ActiveRecord
    # transaction already takes in immediate mode (see ApplicationService).
    serialized_transaction do
      # The import never asks for a format, so the deck takes the "standard"
      # column default. Anchor it to the current pool rather than leave it
      # unsavable; the deck form is where the user corrects it.
      deck = Deck.create!(user: @user, name: @name, standard_pool: StandardPool.current)

      card_entries.each do |entry|
        url = "#{LIMITLESS_BASE_URL}/#{entry[:set_code]}/#{entry[:card_number]}"
        card = Cards::Fetcher.call(url)
        deck.deck_cards.create!(card: card, quantity: entry[:quantity])
      end

      assign_detected_archetype(deck)

      deck
    end
  end

  private

  # Tags the freshly imported deck with an existing archetype when its line-up
  # clearly matches one. We never create a new archetype implicitly here.
  def assign_detected_archetype(deck)
    deck.reload
    detection = Decks::ArchetypeDetector.call(deck)
    deck.update!(archetype: detection.archetype) if detection.matched?
  end

  def parse_card_lines
    entries = @decklist.lines.filter_map { |line|
      match = line.strip.match(CARD_LINE_RE)
      next unless match

      { quantity: match[1].to_i, card_name: match[2], set_code: match[3], card_number: match[4] }
    }

    merge_repeated_printings(entries)
  end

  # A decklist can name the same printing on more than one line (a split entry,
  # or a hand-edited list). `(deck_id, card_id)` is UNIQUE, so those lines have
  # to become one DeckCard carrying the summed quantity — and one fetch. A Hash
  # keyed on the printing keeps them in order of first appearance.
  def merge_repeated_printings(entries)
    entries.each_with_object({}) { |entry, merged|
      key = [ entry[:set_code], entry[:card_number] ]
      existing = merged[key]

      if existing
        reject_conflicting_names!(existing, entry)
        existing[:quantity] += entry[:quantity]
      else
        merged[key] = entry
      end
    }.values
  end

  # The `ex` suffix carries meaning and its case is part of it: `ex` marks a
  # Ruby & Sapphire, Scarlet & Violet or Mega Evolution card, `EX` a Black &
  # White or XY one, and those are different cards. So the rest of the name
  # folds case — a hand-typed `iron hands ex` is the same card as
  # `Iron Hands ex` — but the suffix is compared exactly.
  RULE_BOX_SUFFIX = /\s(ex|EX)\z/

  # Two lines may only be merged if they really name the same card. A set code
  # and number that repeat under two different names mean one of them carries a
  # typo — `2 Iron Thorns ex PAR 70` under `4 Iron Hands ex PAR 70` — and
  # summing those silently would import a deck nobody wrote. Names are the only
  # signal available here: `call` builds its URL from the set code and number
  # alone, so a wrong number resolves to a real, wrong card without complaint.
  def reject_conflicting_names!(existing, entry)
    return if comparable_name(existing[:card_name]) == comparable_name(entry[:card_name])

    raise ParseError,
      "#{existing[:set_code]} #{existing[:card_number]} is named both " \
      "\"#{existing[:card_name]}\" and \"#{entry[:card_name]}\""
  end

  # Case-folded name paired with its rule-box suffix kept verbatim, so the two
  # halves can be compared under different rules in one equality.
  def comparable_name(name)
    [ name.sub(RULE_BOX_SUFFIX, "").downcase, name[RULE_BOX_SUFFIX, 1] ]
  end
end
