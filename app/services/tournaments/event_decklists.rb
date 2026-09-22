require "nokogiri"

# Every published decklist of one event, out of one page per division.
#
# This is what makes importing a whole event affordable. The obvious shape is the one both older
# sources have — one request per row to /decks/list/<id> — and measured on event 577 that is 575
# requests at a median 0.82 s, about 12.7 minutes of wall clock, with 45 of them (37 s) inside the
# preview's own web request. `/tournaments/577/decklists` carries all 559 Masters lists in one
# document (22.1 MB, Nokogiri::HTML 0.30 s, walking every list 0.28 s, RSS 50 → 246 MB), and the
# division goes in the path before it: `/tournaments/577/SR/decklists`. A whole event is six
# requests, not 575.
#
# It presents StandingsImporter's `decklist_service:` interface unchanged — `call(key)` answering
# PTCG text or raising — so nothing downstream knows which shape the lists arrived in. The key is
# the synthetic `"<id>/<division>/<rank>"` that Tournaments::LimitlessEventResults puts in a row's
# `list_url`.
#
# **A block is keyed on the rank its toggle states, not on its `data-target`.** Measured on the two
# committed captures: on 577 every row published a list, so `data-target="decklist-N"` and the
# row's `data-rank` are the same number and nothing can tell them apart; on 563 six of ten rows
# published, and the third block reads `data-target="decklist-3"` while its toggle reads
# "6th Kevin Krueger". The attribute is the block's index among the *published* lists. Keyed on it,
# rank 6's Crustle list is handed to rank 3, who played Rocket's Mewtwo — a list filed under a
# player who did not register it, in a public wiki-governed sheet, with nothing on the page saying
# so.
#
# Not an ApplicationService, deliberately: that base class's `.call` is `new(...).call`, and this
# instance's `call` takes the key. One class answering to both would be a trap rather than a
# convenience.
class Tournaments::EventDecklists
  class ParseError < StandardError; end

  BASE_URL = "https://limitlesstcg.com".freeze

  ID_RE = /\A\d+\z/
  KEY_RE = %r{\A(\d+)/([a-z]+)/(\d+)\z}

  # `<div class="decklist-toggle" data-toggle data-target="decklist-1">1st Dylan Kasturi</div>`
  BLOCK_SELECTOR = ".tournament-decklist".freeze
  TOGGLE_SELECTOR = ".decklist-toggle".freeze
  RANK_RE = /\A(\d+)(?:st|nd|rd|th)\b/

  def initialize(tournament_id)
    @tournament_id = tournament_id.to_s
    @divisions = {}
    return if ID_RE.match?(@tournament_id)

    raise ArgumentError, "tournament id #{tournament_id.inspect} is not a tournament id"
  end

  def call(key)
    tournament_id, division, rank = KEY_RE.match(key.to_s)&.captures
    raise ArgumentError, "#{key.inspect} is not a decklist key for tournament #{@tournament_id}" unless
      tournament_id == @tournament_id && Tournaments::LimitlessEventResults::DIVISION_PAGES.key?(division)

    nodes = blocks_for(division)[rank.to_i]
    raise ParseError, "#{url(division)} publishes no list ranked #{rank}" if nodes.nil?

    Tournaments::LimitlessDecklist.from_nodes(nodes, source: "the list ranked #{rank} on #{url(division)}")
  end

  def url(division)
    suffix = Tournaments::LimitlessEventResults::DIVISION_PAGES.fetch(division)

    [ BASE_URL, "tournaments", @tournament_id, suffix, "decklists" ].compact.join("/")
  end

  private

  # Fetched once per division, and only when a row of that division asks: an event whose rows are
  # all Masters must not pay for three pages, and 563 publishes no Junior lists at all.
  #
  # The blocks are kept as nodes rather than converted up front. Walking all 559 costs 0.28 s, so
  # this is not about time — it is that a list Tournaments::LimitlessDecklist refuses (a set code
  # cartodex cannot address, a 59-card parse) must cost its own row and not the whole division.
  def blocks_for(division)
    @divisions[division] ||= parse(division)
  end

  def parse(division)
    doc = Nokogiri::HTML(HttpFetcher.call(url(division)))
    blocks = doc.css(BLOCK_SELECTOR)
    by_rank = blocks.each_with_object({}) { |block, acc|
      rank = rank_of(block)
      acc[rank] = block.css(Tournaments::LimitlessDecklist::CARD_SELECTOR) if rank
    }
    # No blocks at all is an event that published no list for this division, which is ordinary.
    # Blocks whose ranks are all unreadable is a layout change, and left silent it imports every
    # row of the division as a standing with no list and says nothing anywhere.
    raise ParseError, "no list on #{url(division)} names the row it belongs to" if by_rank.empty? && blocks.any?

    by_rank
  end

  def rank_of(block)
    RANK_RE.match(block.at_css(TOGGLE_SELECTOR)&.text.to_s.squish)&.[](1)&.to_i
  end
end
