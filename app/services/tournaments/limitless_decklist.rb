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
class Tournaments::LimitlessDecklist < ApplicationService
  class ParseError < StandardError; end

  DECK_SIZE = 60

  # Decks::Fetcher::CARD_LINE_RE demands two or three uppercase letters for the set code and
  # *silently drops* any line it cannot match — a dropped line is a deck missing four cards with
  # no error anywhere. So a code it could not parse is refused here, by name, while there is still
  # something to say about it.
  SET_CODE_RE = /\A[A-Z]{2,3}\z/

  def initialize(url)
    @url = url
  end

  def call
    doc = Nokogiri::HTML(HttpFetcher.call(@url))
    cards = doc.css("[data-text-decklist] .decklist-card")
    raise ParseError, "no decklist found at #{@url}" if cards.empty?

    lines = cards.map { |card| card_line(card) }
    verify_deck_size(lines)
    lines.map { |line| line[:text] }.join("\n")
  end

  private

  def card_line(card)
    set_code = card["data-set"].to_s.strip
    number = card["data-number"].to_s.strip
    quantity = card.at_css(".card-count")&.text.to_s.squish
    name = card.at_css(".card-name")&.text.to_s.squish

    verify_printing!(set_code, number, name)
    verify_quantity!(quantity, name)

    { quantity: quantity.to_i, text: "#{quantity} #{name} #{set_code} #{number}" }
  end

  def verify_printing!(set_code, number, name)
    label = name.presence || "an unnamed card"
    raise ParseError, "#{label} at #{@url} carries no printing" if set_code.blank? || number.blank?
    raise ParseError, "#{label} at #{@url} is from set #{set_code}, which cartodex cannot address" unless
      SET_CODE_RE.match?(set_code)
    raise ParseError, "#{set_code} #{number} at #{@url} has no card name" if name.blank?
  end

  def verify_quantity!(quantity, name)
    return if quantity.match?(/\A[1-9]\d*\z/)

    raise ParseError, "#{name.presence || "a card"} at #{@url} has an unreadable count (#{quantity.inspect})"
  end

  # A Pokémon TCG deck is exactly sixty cards. Anything else means the page changed shape or the
  # parse only saw part of it — the failure the reference script warns about, and the one that
  # otherwise lands silently as a deck nobody played.
  def verify_deck_size(lines)
    total = lines.sum { |line| line[:quantity] }
    return if total == DECK_SIZE

    raise ParseError, "#{@url} parsed to #{total} cards, not #{DECK_SIZE}"
  end
end
