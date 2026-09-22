require "nokogiri"

# Turn one Limitless decklist page into the PTCG text `Decks::Fetcher` already parses.
#
# The page (https://limitlesstcg.com/decks/list/<id>) renders each card as
#
#   <div class="decklist-card" data-set="MEG" data-number="104" data-lang="en">
#     <a class="card-link" href="/cards/MEG/104">
#       <span class="card-count">4</span><span class="card-name">Mega Kangaskhan ex</span>
#
# which is exactly the `QUANTITY NAME SET NUMBER` line Decks::Fetcher::CARD_LINE_RE wants. Nothing
# here writes anything: the caller hands the text to Decks::Fetcher, which owns the transaction,
# the card lookups and the archetype detection.
#
# The page also renders the same cards a second time as an image grid, under
# `[data-image-decklist]` — those carry neither `data-set` nor a text `.card-count` (the count is
# an `<img alt="4">`), so the selector is scoped to the text view rather than trusting that the
# two views will keep differing.
#
# The same markup arrives a second way. An event's `/tournaments/<id>/decklists` page carries every
# published list of a division in one document — 559 of them, 22.1 MB, measured — and
# Tournaments::EventDecklists reads it. So the rule that turns those nodes into text lives in
# `.from_nodes`, which `#call` is an application of: two spellings of it is exactly the failure
# Decks::Fetcher::SET_CODE_RE exists to prevent, and a divergence would be invisible because each
# path has tests of its own. `source:` is what @url used to be — a URL here, "the 6th list on
# …/decklists" there — and it appears in every message, since that is the only thing saying which
# of 559 lists was refused.
class Tournaments::LimitlessDecklist < ApplicationService
  class ParseError < StandardError; end

  DECK_SIZE = 60

  # Decks::Fetcher::CARD_LINE_RE *silently drops* any line it cannot match — a dropped line is a
  # deck four cards short with no error anywhere, which is exactly the failure these guards exist
  # for. The set-code half therefore reads that regex's own shape rather than restating it: two
  # spellings of one rule is how `30C` came to be refused here and lost there on the same day. Both
  # halves are checked here, by name, while there is still something to say about the card. No page
  # observed so far carries a non-numeric card number, which is precisely why a future one would
  # go unnoticed: nothing downstream would complain.
  SET_CODE_RE = ::Decks::Fetcher::SET_CODE_RE
  NUMBER_RE = /\A\d+\z/

  CARD_SELECTOR = "[data-text-decklist] .decklist-card".freeze

  class << self
    def from_nodes(card_nodes, source:)
      raise ParseError, "no decklist found at #{source}" if card_nodes.empty?

      lines = card_nodes.map { |card| card_line(card, source) }
      verify_deck_size(lines, source)
      lines.map { |line| line[:text] }.join("\n")
    end

    private

    def card_line(card, source)
      set_code = card["data-set"].to_s.strip
      number = card["data-number"].to_s.strip
      quantity = card.at_css(".card-count")&.text.to_s.squish
      name = card.at_css(".card-name")&.text.to_s.squish

      verify_printing!(set_code, number, name, source)
      verify_quantity!(quantity, name, source)

      { quantity: quantity.to_i, text: "#{quantity} #{name} #{set_code} #{number}" }
    end

    def verify_printing!(set_code, number, name, source)
      label = name.presence || "an unnamed card"
      raise ParseError, "#{label} at #{source} carries no printing" if set_code.blank? || number.blank?
      raise ParseError, "#{label} at #{source} is from set #{set_code}, which cartodex cannot address" unless
        SET_CODE_RE.match?(set_code)
      raise ParseError, "#{label} at #{source} is #{set_code} #{number}, whose number cartodex cannot address" unless
        NUMBER_RE.match?(number)
      raise ParseError, "#{set_code} #{number} at #{source} has no card name" if name.blank?
    end

    def verify_quantity!(quantity, name, source)
      return if quantity.match?(/\A[1-9]\d*\z/)

      raise ParseError, "#{name.presence || "a card"} at #{source} has an unreadable count (#{quantity.inspect})"
    end

    # A Pokémon TCG deck is exactly sixty cards. Anything else means the page changed shape or the
    # parse only saw part of it — the failure the reference script warns about, and the one that
    # otherwise lands silently as a deck nobody played.
    def verify_deck_size(lines, source)
      total = lines.sum { |line| line[:quantity] }
      return if total == DECK_SIZE

      raise ParseError, "#{source} parsed to #{total} cards, not #{DECK_SIZE}"
    end
  end

  def initialize(url)
    @url = url
  end

  def call
    doc = Nokogiri::HTML(HttpFetcher.call(@url))

    self.class.from_nodes(doc.css(CARD_SELECTOR), source: @url)
  end
end
