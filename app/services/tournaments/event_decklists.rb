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

    list = blocks_for(division)[rank.to_i]
    raise ParseError, "#{url(division)} publishes no list ranked #{rank}" if list.nil?
    # A list this page published in a shape LimitlessDecklist refuses was converted with every
    # other, so its refusal is raised here — against the row that asked for it — rather than having
    # cost the whole division at parse time.
    raise list if list.is_a?(StandardError)

    list
  end

  # Whether answering this key would leave the machine. StandingsImporter paces everything that does
  # — half a second between requests — and a division already parsed answers out of a Hash: on the
  # reference event that is 572 of 575 calls, each of which was paying the pause for a request
  # nobody was making, ~4.8 minutes of it, against the six-requests-for-a-whole-event this class
  # exists to buy. The two older decklist services fetch one URL per row, so every call of theirs
  # *is* remote and they answer this question by not having it.
  #
  # Keyed on the division and not on the rank, because a fetch is: a rank this page never published
  # is answered — with a refusal — without a request, and a memoised failure is answered the same
  # way.
  def held?(key)
    @divisions.key?(KEY_RE.match(key.to_s)&.captures&.second)
  end

  def url(division)
    suffix = Tournaments::LimitlessEventResults::DIVISION_PAGES.fetch(division)

    [ BASE_URL, "tournaments", @tournament_id, suffix, "decklists" ].compact.join("/")
  end

  private

  # Fetched once per division, and only when a row of that division asks: an event whose rows are
  # all Masters must not pay for three pages, and 563 publishes no Junior lists at all.
  #
  # **A refusal is memoised too, and that is not tidiness.** `||=` stores a result and never an
  # exception, so a division whose ranks stopped being readable was re-fetched and re-parsed by
  # every row of it — 559 rows against a 22.1 MB page is 12.4 GB off limitlesstcg.com in one run,
  # 575 × 0.30 s of Nokogiri, and an Import that still says "completed" with every list missing.
  # `StandingsImporter`'s five-consecutive-failure abort cannot see it either, because it counts
  # HttpFetcher::FetchError and this is a ParseError.
  def blocks_for(division)
    unless @divisions.key?(division)
      @divisions[division] = begin
        parse(division)
      rescue StandardError => e
        e
      end
    end

    parsed = @divisions[division]
    raise parsed if parsed.is_a?(StandardError)

    parsed
  end

  # Converted to text here rather than kept as nodes, and the document is dropped with the method.
  # Holding three parsed division DOMs for a whole run measures **+355 MB RSS** on pages a third
  # smaller than the real ones, in a Solid Queue worker that also holds the app — and a preview
  # request holds a second such store concurrently. Walking all 559 costs 0.28 s either way.
  #
  # The property that made nodes look necessary is kept: a list LimitlessDecklist refuses (a set
  # code cartodex cannot address, a 59-card parse) is stored *as its exception* and raised against
  # the row that asks for it, so it still costs its own row and not the whole division.
  def parse(division)
    blocks = Nokogiri::HTML(HttpFetcher.call(url(division))).css(BLOCK_SELECTOR)
    by_rank = {}
    blocks.each do |block|
      rank = rank_of(block)
      next if rank.nil?

      # Last-wins here would hand one player's sixty cards to another player's row, which is the
      # exact failure keying on the stated rank exists to prevent — and a top-cut page writing
      # "9th-16th" on eight blocks makes all eight claim rank 9. Refused, loudly, for the whole
      # division: nothing here can tell which of the two the row meant.
      raise ParseError, "#{url(division)} publishes two lists ranked #{rank}" if by_rank.key?(rank)

      by_rank[rank] = convert(block, rank, division)
    end
    # No blocks at all is an event that published no list for this division, which is ordinary.
    # Blocks whose ranks are all unreadable is a layout change, and left silent it imports every
    # row of the division as a standing with no list and says nothing anywhere.
    raise ParseError, "no list on #{url(division)} names the row it belongs to" if by_rank.empty? && blocks.any?

    by_rank
  end

  def convert(block, rank, division)
    Tournaments::LimitlessDecklist.from_nodes(
      block.css(Tournaments::LimitlessDecklist::CARD_SELECTOR),
      source: "the list ranked #{rank} on #{url(division)}"
    )
  rescue Tournaments::LimitlessDecklist::ParseError => e
    e
  end

  def rank_of(block)
    RANK_RE.match(block.at_css(TOGGLE_SELECTOR)&.text.to_s.squish)&.[](1)&.to_i
  end
end
