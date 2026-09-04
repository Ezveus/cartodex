require "nokogiri"

# Scrape one archetype's tournament history off Limitless TCG.
#
# The page is https://limitlesstcg.com/decks/<deck_id>/results: a single <table> where each event
# is a `<th class="sub-heading">` spanning the row, followed by one `<tr>` per placement. As
# measured on 2026-09-05 against deck 280, the page held 176 events and 1569 placement rows, every
# one of them with exactly five `<td>` and a player link; 21 had no decklist.
#
# It returns rows, not records. Deciding which of them can become a Tournament and a
# TournamentStanding is Tournaments::StandingsImportPlan's job, and writing them is
# Tournaments::StandingsImporter's.
class Tournaments::LimitlessResults < ApplicationService
  class ParseError < StandardError; end

  BASE_URL = "https://limitlesstcg.com".freeze

  # "28th August 2026 - World Championships 2026". Split on " - " and a name that contains the
  # same separator loses half of itself, so the date prefix is matched rather than the separator.
  HEADING_RE = /\A(\d{1,2})(?:st|nd|rd|th)\s+([A-Za-z]+)\s+(\d{4})\s+-\s+(.+)\z/
  EVENT_HREF_RE = %r{\A/tournaments/(\d+)(?:/([A-Za-z]+))?/?\z}
  PLACEMENT_RE = /\A(\d+)/

  # The suffix on the event's href is the age division, and it is the only place the page states
  # one: /tournaments/518 is Masters, /tournaments/518/SR the Senior half of the *same* event.
  # Only these two suffixes occur (38 JR and 24 SR against 114 bare headings, measured). An
  # unknown one yields a nil division rather than a guess — the plan refuses that row by name,
  # which is how a third division would be noticed instead of being filed as Masters.
  DIVISION_BY_SUFFIX = { nil => "masters", "JR" => "junior", "SR" => "senior" }.freeze

  # A decklist link is rebuilt from the id it names rather than passed through: a scraped href is
  # attacker-controlled text, and Brakeman's LinkToHref check never sees a Phlex component (they
  # are libraries, not templates), so nothing downstream would catch a `javascript:` href reaching
  # a link.
  LIST_HREF_RE = %r{/decks/list/(\d+)}

  Row = Struct.new(
    :event_name, :event_date, :division, :division_suffix, :format,
    :player_name, :placement, :list_url,
    keyword_init: true
  )

  def initialize(deck_id)
    @deck_id = deck_id.to_s
  end

  def call
    doc = Nokogiri::HTML(HttpFetcher.call(url))
    table = doc.at_css("table")
    raise ParseError, "no results table at #{url} — the page layout may have changed" if table.nil?

    rows = parse_rows(table)
    raise ParseError, "no placements found at #{url}" if rows.empty?

    rows
  end

  def url = "#{BASE_URL}/decks/#{@deck_id}/results"

  private

  def parse_rows(table)
    heading = nil

    table.css("tr").filter_map { |tr|
      sub_heading = tr.at_css("th.sub-heading")
      if sub_heading
        heading = parse_heading(sub_heading)
        next
      end

      next if heading.nil?

      cells = tr.css("td")
      next unless cells.size == 5

      build_row(heading, cells)
    }
  end

  def parse_heading(sub_heading)
    link = sub_heading.at_css("a")
    return if link.nil?

    match = HEADING_RE.match(link.text.squish)
    return if match.nil?

    suffix = EVENT_HREF_RE.match(link["href"].to_s)&.[](2)
    {
      name: strip_division_suffix(match[4].squish, suffix),
      date: parse_date(match),
      division: DIVISION_BY_SUFFIX[suffix],
      division_suffix: suffix
    }
  end

  # The heading repeats the division as " (JR)" in the name itself. Left in place it would
  # catalogue "NAIC 2026, New Orleans (JR)" as an event of its own, forever, beside the Masters
  # row of the very same tournament — the one mistake here that no later correction undoes
  # cheaply. Only a suffix the href named *and* DIVISION_BY_SUFFIX recognises is removed, so a name
  # that genuinely ends in parentheses survives — and so does an unreadable division, which must
  # not be merged into the Masters row of the same tournament on the strength of a suffix nobody
  # could interpret.
  def strip_division_suffix(name, suffix)
    return name if suffix.blank? || !DIVISION_BY_SUFFIX.key?(suffix)

    name.sub(/\s*\(#{Regexp.escape(suffix)}\)\z/, "")
  end

  def parse_date(match)
    Date.parse("#{match[1]} #{match[2]} #{match[3]}")
  rescue Date::Error
    nil
  end

  def build_row(heading, cells)
    return if heading[:date].nil?

    Row.new(
      event_name: heading[:name],
      event_date: heading[:date],
      division: heading[:division],
      division_suffix: heading[:division_suffix],
      format: parse_format(cells[0]),
      player_name: parse_player_name(cells[3]),
      placement: parse_placement(cells[1]),
      list_url: parse_list_url(cells[4])
    )
  end

  # Reported verbatim — "standard", "standard-jp", "expanded-jp" — rather than folded to the
  # cartodex enum here. "standard-jp" is not Standard as this app means it: mapping it would anchor
  # a Japanese event to a western StandardPool. Deciding what it becomes is the plan's job, which
  # is also where the admin can see the decision.
  def parse_format(cell)
    cell.at_css("img.format")&.[]("alt").presence
  end

  def parse_player_name(cell)
    (cell.at_css("a")&.text || cell.text).squish.presence
  end

  def parse_placement(cell)
    PLACEMENT_RE.match(cell.text.squish)&.[](1)&.to_i
  end

  def parse_list_url(cell)
    id = LIST_HREF_RE.match(cell.at_css("a")&.[]("href").to_s)&.[](1)
    return if id.nil?

    "#{BASE_URL}/decks/list/#{id}"
  end
end
