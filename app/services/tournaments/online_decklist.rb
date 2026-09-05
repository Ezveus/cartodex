require "nokogiri"

# Turn one play.limitlesstcg.com decklist page into the PTCG text `Decks::Fetcher` already parses.
#
# This is the online sibling of Tournaments::LimitlessDecklist, and the two sources do not agree on
# where a printing lives. The page (https://play.limitlesstcg.com/tournament/<id>/player/<name>/decklist)
# renders three columns, each headed with its own subtotal:
#
#   <div class="decklist"><div class="column"><div class="cards">
#     <div class="heading">Pokémon (19)</div>
#     <p><a href="https://limitlesstcg.com/cards/MEG/104">4 Mega Kangaskhan ex (MEG-104)</a></p>
#     ...
#     <div class="heading">Trainer (27)</div>
#     <p><a href="https://limitlesstcg.com/cards/SCR/133">4 Crispin</a></p>
#
# Only the **Pokémon** lines print a "(SET-NUM)" in their visible text. A Trainer reads "4 Crispin"
# and an Energy "7 Grass Energy", with no printing at all — it exists only in the href. So the
# quantity and the name come from the text and the set and number come from the **href, always**,
# Pokémon included: a parser that regexes the text emits usable lines for the Pokémon column alone
# and loses the other two to Decks::Fetcher::CARD_LINE_RE, which drops what it cannot match without
# raising. The " (MEG-104)" suffix is stripped for the same reason — left in, the name is one no
# card carries.
#
# Nothing here writes anything: the caller hands the text to Decks::Fetcher, which owns the
# transaction, the card lookups and the archetype detection.
class Tournaments::OnlineDecklist < ApplicationService
  class ParseError < StandardError; end

  DECK_SIZE = 60

  # Decks::Fetcher::CARD_LINE_RE demands two or three uppercase letters for the set code and digits
  # for the number, and *silently drops* any line it cannot match — a dropped line is a deck four
  # cards short with no error anywhere, which is exactly the failure these guards exist for.
  SET_CODE_RE = /\A[A-Z]{2,3}\z/
  NUMBER_RE = /\A\d+\z/

  # The href is the only place a Trainer's or an Energy's printing appears. It is absolute on the
  # observed page (it points at limitlesstcg.com, a different host from the one being read), but a
  # relative one is the same link and is accepted rather than refused on a leading slash.
  CARD_HREF_RE = %r{\A(?:https?://[^/]+)?/cards/(?<set_code>[^/?#]+)/(?<number>[^/?#]+)/?\z}

  # "Pokémon (19)" — the label is what a refusal names, the subtotal is what it is checked against.
  HEADING_RE = /\A(?<label>.+?)\s*\((?<subtotal>\d+)\)\z/

  # "4 Mega Kangaskhan ex (MEG-104)": the count leads, and the printing — when the column prints one
  # at all — trails. Neither belongs to the name.
  COUNT_RE = /\A(?<quantity>\d+)\s+(?<name>.+)\z/
  PRINTING_SUFFIX_RE = /\s*\([A-Za-z0-9]{2,4}-[A-Za-z0-9]+\)\z/

  def initialize(url)
    @url = url
  end

  def call
    doc = Nokogiri::HTML(HttpFetcher.call(@url))
    columns = doc.css(".decklist .column .cards")
    raise ParseError, "no decklist found at #{@url}" if columns.empty? || columns.css("p a").empty?

    lines = columns.flat_map { |column| column_lines(column) }
    verify_deck_size(lines)
    lines.map { |line| line[:text] }.join("\n")
  end

  private

  def column_lines(column)
    label, subtotal = heading(column)
    lines = column.css("p a").map { |anchor| card_line(anchor) }
    verify_column_total!(label, subtotal, lines)
    lines
  end

  def heading(column)
    text = column.at_css(".heading")&.text.to_s.squish
    match = HEADING_RE.match(text)
    raise ParseError, "a column at #{@url} has an unreadable heading (#{text.inspect})" unless match

    [ match[:label], match[:subtotal].to_i ]
  end

  def card_line(anchor)
    text = anchor.text.to_s.squish
    match = COUNT_RE.match(text)
    quantity = match ? match[:quantity] : ""
    name = (match ? match[:name] : text).sub(PRINTING_SUFFIX_RE, "").strip

    set_code, number = printing(anchor, name)
    verify_printing!(set_code, number, name)
    verify_quantity!(quantity, name)

    { quantity: quantity.to_i, text: "#{quantity} #{name} #{set_code} #{number}" }
  end

  def printing(anchor, name)
    href = anchor["href"].to_s.strip
    match = CARD_HREF_RE.match(href)
    return [ match[:set_code], match[:number] ] if match

    raise ParseError,
      "#{label_for(name)} at #{@url} links to #{href.presence&.inspect || "nothing"}, which is not a card page"
  end

  def verify_printing!(set_code, number, name)
    label = label_for(name)
    raise ParseError, "#{label} at #{@url} is from set #{set_code}, which cartodex cannot address" unless
      SET_CODE_RE.match?(set_code)
    raise ParseError, "#{label} at #{@url} is #{set_code} #{number}, whose number cartodex cannot address" unless
      NUMBER_RE.match?(number)
    raise ParseError, "#{set_code} #{number} at #{@url} has no card name" if name.blank?
  end

  def verify_quantity!(quantity, name)
    return if quantity.match?(/\A[1-9]\d*\z/)

    raise ParseError, "#{label_for(name)} at #{@url} has an unreadable count (#{quantity.inspect})"
  end

  # The 60 check below cannot see a column that silently lost a line, because another column that
  # gained one still adds up. This source hands us three subtotals it wrote itself, so a column is
  # checked against its own heading first — and named, since "the deck is short" says nothing about
  # where the page changed shape.
  def verify_column_total!(label, subtotal, lines)
    total = lines.sum { |line| line[:quantity] }
    return if total == subtotal

    raise ParseError, "the #{label} column at #{@url} parsed to #{total} cards, not the #{subtotal} its heading claims"
  end

  # A Pokémon TCG deck is exactly sixty cards. Anything else means the page changed shape or the
  # parse only saw part of it — the one that otherwise lands silently as a deck nobody played.
  def verify_deck_size(lines)
    total = lines.sum { |line| line[:quantity] }
    return if total == DECK_SIZE

    raise ParseError, "#{@url} parsed to #{total} cards, not #{DECK_SIZE}"
  end

  def label_for(name)
    name.presence || "an unnamed card"
  end
end
