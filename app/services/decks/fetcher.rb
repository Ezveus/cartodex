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

    ActiveRecord::Base.transaction do
      deck = Deck.create!(user: @user, name: @name)

      card_entries.each do |entry|
        url = "#{LIMITLESS_BASE_URL}/#{entry[:set_code]}/#{entry[:card_number]}"
        card = Cards::Fetcher.call(url)
        deck.deck_cards.create!(card: card, quantity: entry[:quantity])
      end

      deck
    end
  end

  private

  def parse_card_lines
    @decklist.lines.filter_map { |line|
      match = line.strip.match(CARD_LINE_RE)
      next unless match

      { quantity: match[1].to_i, card_name: match[2], set_code: match[3], card_number: match[4] }
    }
  end
end
