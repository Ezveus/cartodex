require "nokogiri"

# Scrape one whole real-world event off Limitless TCG — every age division, every player.
#
# This is the third source of Tournaments::StandingsImportPlan / StandingsImporter, beside the
# paper archetype-history pages (Tournaments::LimitlessResults) and the online best-finishes
# leaderboard (Tournaments::OnlineResults), and the first whose rows do **not** all share one
# archetype. See docs/superpowers/specs/2026-09-22-tournament-standings-import-design.md.
#
# One event is three pages, one per Play! Pokémon age division, and each states its **own** field
# size: measured on /tournaments/563, Masters says "88 Players" while Seniors and Juniors say
# "? Players" — an event-wide total would have been repeated on all three. So the three figures map
# one-to-one onto tournaments.{masters,senior,junior}_participant_count, which is what
# TournamentStanding#placement_within_division_field measures a placement against. "?" is a real
# value and comes back nil, never 0: a field of zero makes every placement in that division invalid.
#
# Each row carries its data twice, as attributes and as cells:
#
#   <tr data-rank="1" data-name="Dylan Kasturi" data-country="US" data-deck="Basic Box">
#     <td>1</td>
#     <td><a href="/players/8258">Dylan Kasturi</a></td>
#     <td><img class="flag" ...></td>
#     <td><a href="/decks/339"><span data-tooltip="Basic Box">…</span></a></td>
#     <td><a href="/decks/list/29001">…</a></td>
#
# It returns rows, not records — the same contract the two older parsers have with the plan, whose
# eight fields are the first eight here.
class Tournaments::LimitlessEventResults < ApplicationService
  class ParseError < StandardError; end

  BASE_URL = "https://limitlesstcg.com".freeze

  ID_RE = /\A\d+\z/

  # The three pages of one event, and the order they are read in. nil is the base page, which is
  # Masters — the same suffix vocabulary Tournaments::LimitlessResults reads off an event href,
  # spelled the other way round because here the suffix is an input rather than something parsed.
  DIVISION_PAGES = { "masters" => nil, "senior" => "SR", "junior" => "JR" }.freeze

  # "19th September 2026 • 3122 Players • Temporal Forces - Pitch Black", squished.
  DATE_RE = /(\d{1,2})(?:st|nd|rd|th)\s+([A-Za-z]+)\s+(\d{4})/
  # The attendance and the literal "?" that stands in for it on a division nobody counted.
  ATTENDANCE_RE = /(\d+|\?)\s+Players/
  # The pool code as published — "TEF-PBL", which is StandardPool#name byte for byte. The format is
  # *stated* on the page and is never inferred from the date: StandardPool.at reads `legal_on`, so
  # an event held in the fortnight after a set ships but before Play! Pokémon rules it legal would
  # be anchored to the pool the source says it was not played under.
  FORMAT_RE = /[?&]format=([^&"']+)/
  # A deck reference, anchored: a scraped href is attacker-controlled text and this capture becomes
  # a Hash key and a form value on the mapping screen. Read off the href and never off `data-deck`,
  # because Limitless renames a deck as a metagame settles while 284, 284/3 and 284/9 stay
  # Dragapult, Dragapult Dusknoir and Dragapult Blaziken.
  DECK_HREF_RE = %r{\A/decks/(\d+)(?:\?variant=(\d+))?\z}
  # Only used as a predicate — "did this row publish a list". The list itself comes off the
  # division's bulk decklists page, addressed by rank, so the id in this href is never fetched.
  LIST_HREF_RE = %r{/decks/list/\d+}

  CELL_COUNT = 5
  PLAYER_CELL = 1
  DECK_CELL = 3
  LIST_CELL = 4

  Row = Struct.new(
    :event_name, :event_date, :division, :division_suffix, :format,
    :player_name, :placement, :list_url,
    :archetype_key, :archetype_label, :attendance,
    keyword_init: true
  )

  def initialize(tournament_id)
    @tournament_id = tournament_id.to_s
    return if ID_RE.match?(@tournament_id)

    raise ArgumentError, "tournament id #{tournament_id.inspect} is not a tournament id"
  end

  def call
    DIVISION_PAGES.flat_map { |division, suffix| rows_for(division, suffix) }
  end

  def url(suffix = nil) = [ BASE_URL, "tournaments", @tournament_id, suffix ].compact.join("/")

  private

  # The base page and a suffix page fail differently, and that is the rule rather than an
  # inconsistency. No table on /tournaments/<id> means the event does not exist or the layout
  # moved, which is the whole run's problem. A suffix page that 404s or answers 200 with no table
  # is an *empty division* — 563's SR and JR pages do exactly that, and making it fatal would put
  # every small event permanently out of reach.
  def rows_for(division, suffix)
    page = fetch(suffix)
    return [] if page.nil? && suffix.present?
    raise ParseError, "no standings table at #{url} — the event may not exist, or the layout changed" if page.nil?

    page[:table].css("tr[data-rank]").filter_map { |tr| build_row(page, division, suffix, tr) }
  end

  # nil for "there is nothing readable here", whatever the reason: a 404, a page with no heading, a
  # page with no date, a page with no table. The caller decides what that costs.
  def fetch(suffix)
    doc = Nokogiri::HTML(HttpFetcher.call(url(suffix)))
    table = doc.at_css("table")
    name = doc.at_css(".infobox-heading")&.text&.squish
    line = doc.at_css(".infobox-line")&.text&.squish.to_s
    date = parse_date(line)
    return if table.nil? || name.blank? || date.nil?

    { table: table, name: name, date: date, attendance: parse_attendance(line), format: parse_format(doc) }
  rescue HttpFetcher::FetchError
    nil
  end

  def parse_date(line)
    match = DATE_RE.match(line)
    return if match.nil?

    Date.parse("#{match[1]} #{match[2]} #{match[3]}")
  rescue Date::Error
    nil
  end

  def parse_attendance(line)
    stated = ATTENDANCE_RE.match(line)&.[](1)
    stated&.to_i if stated != "?"
  end

  def parse_format(doc)
    href = doc.css(".infobox-line a").map { |link| link["href"].to_s }.find { |h| FORMAT_RE.match?(h) }

    FORMAT_RE.match(href.to_s)&.[](1)&.squish.presence
  end

  def build_row(page, division, suffix, tr)
    cells = tr.css("td")
    return unless cells.size == CELL_COUNT

    rank = tr["data-rank"].to_s.strip
    return unless ID_RE.match?(rank)

    deck_id, variant = DECK_HREF_RE.match(cells[DECK_CELL].at_css("a")&.[]("href").to_s)&.captures

    Row.new(
      event_name: page[:name], event_date: page[:date],
      division: division, division_suffix: suffix, format: page[:format],
      player_name: player_name(tr, cells), placement: rank.to_i,
      list_url: list_key(division, rank, cells),
      archetype_key: deck_id && LimitlessArchetypeMapping.reference_for(deck_id, variant),
      archetype_label: tr["data-deck"].to_s.squish.presence,
      attendance: page[:attendance]
    )
  end

  # `data-name` first: the cell holds a partner link beside the player's own on some rows (measured
  # on 563, where Zach Lesage's cell carries a second <a> and an inline SVG), and the attribute is
  # the row's own unambiguous statement of who this is.
  def player_name(tr, cells)
    tr["data-name"].to_s.squish.presence ||
      (cells[PLAYER_CELL].at_css("a")&.text || cells[PLAYER_CELL].text).squish.presence
  end

  # Not an HTTP URL: the synthetic key Tournaments::EventDecklists answers on, since one page
  # carries every list of a division and a row is addressed within it by rank. It stays in
  # `list_url` so StandingsImporter's existing `row.list_url.blank?` gate keeps working unchanged —
  # a row that published no list still has none here.
  def list_key(division, rank, cells)
    return unless LIST_HREF_RE.match?(cells[LIST_CELL].at_css("a")&.[]("href").to_s)

    "#{@tournament_id}/#{division}/#{rank}"
  end
end
