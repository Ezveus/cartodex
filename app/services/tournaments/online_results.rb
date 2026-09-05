require "nokogiri"

# Scrape one archetype's best online finishes off play.limitlesstcg.com.
#
# The page is https://play.limitlesstcg.com/decks/<slug>?format=&rotation=&set=: a single <table>
# whose every data row is a `<tr>` of six `<td>`, carrying `data-player`, `data-tournament`,
# `data-date`, `data-place` and `data-score`. As measured on 2026-09-05 it is a **top-20
# leaderboard**, not a field — 20 rows whatever the parameters, fewer for a rare archetype, no
# pagination.
#
# Two of those attributes are traps, and both were measured:
#
#   * `data-place` is the row's **rank in the leaderboard** (1..N in order), not the finish. A row
#     carrying data-place="13" reads `2nd of 197`. Reading the attribute records a second place as
#     a thirteenth.
#   * `data-score` is only the **wins**. The full record is the fifth cell's `W - L - T`, matching
#     on 20/20 rows. Reading the attribute reports every player as undefeated.
#
# So both come out of the cells, and the cells alone. The fourth cell also carries the attendance
# after "of" (20/20 rows) — a figure the paper source does not publish, which is why every event
# imported from it has nil participant counts.
#
# The player's identity is likewise the **slug in the href**, not `data-player`: 20 rows carried 13
# display names against 12 slugs, `JRobrueda` and `Jose Rueda` being one person, `jrobrueda`. The
# importer de-duplicates on `(player slug, list content)`, and keyed on the displayed name that
# person splits in two and their one list is counted twice in the sample.
#
# It returns rows, not records — the same contract Tournaments::LimitlessResults has with
# Tournaments::StandingsImportPlan, whose eight fields are the first eight here.
class Tournaments::OnlineResults < ApplicationService
  class ParseError < StandardError; end

  BASE_URL = "https://play.limitlesstcg.com".freeze

  # Every one of the four is interpolated into a URL, which is the reason
  # Admin::StandingsImportsController::DECK_ID_RE exists for the paper source: an unvalidated
  # segment is how a fetch ends up pointed somewhere it was never meant to go, and an unvalidated
  # query value is how it grows a parameter nobody asked for. Refused before anything is fetched.
  SLUG_RE = /\A[a-z0-9-]+\z/
  FORMAT_RE = /\A[a-z0-9-]+\z/
  ROTATION_RE = /\A\d{4}\z/
  SET_RE = /\A[A-Z0-9]{2,5}\z/

  # "1st of 259" — the finish, then the field size. Attendance is optional (a row missing it is
  # still a placement); a cell with no leading integer is not a placement at all and costs its row.
  PLACEMENT_RE = /\A(\d+)/
  ATTENDANCE_RE = /\bof\s+(\d+)/
  RECORD_RE = /\A(\d+)\s*-\s*(\d+)\s*-\s*(\d+)\z/

  # `/tournament/<tid>/player/<slug>` with or without the `/decklist` suffix. Anchored, because the
  # captures become both the row's identity and a link on the preview page: a scraped href is
  # attacker-controlled text, and Brakeman's LinkToHref check never sees a Phlex component (they
  # are libraries, not templates), so nothing downstream would catch a `javascript:` href reaching
  # a link. The URL is rebuilt from the captures rather than passed through.
  PLAYER_HREF_RE = %r{\A/tournament/([A-Za-z0-9]+)/player/([A-Za-z0-9._-]+)(?:/decklist)?\z}

  CELL_COUNT = 6
  PLAYER_CELL = 0
  PLACEMENT_CELL = 3
  RECORD_CELL = 4

  # Online play has no age divisions. Writing "masters" would be a lie that
  # Archetypes::Performance#by_division then reports as a fact about age divisions.
  DIVISION = "open".freeze

  Row = Struct.new(
    :event_name, :event_date, :division, :division_suffix, :format,
    :player_name, :placement, :list_url,
    :player_slug, :attendance, :wins, :losses, :ties, :event_key,
    keyword_init: true
  )

  def initialize(slug, format:, rotation:, set:)
    @slug = validated(slug, SLUG_RE, "slug")
    @format = validated(format, FORMAT_RE, "format")
    @rotation = validated(rotation, ROTATION_RE, "rotation")
    @set = validated(set, SET_RE, "set")
  end

  def call
    doc = Nokogiri::HTML(HttpFetcher.call(url))
    table = doc.at_css("table")
    raise ParseError, "no results table at #{url} — the page layout may have changed" if table.nil?

    rows = parse_rows(table)
    # An invalid (rotation, set) pair answers with a perfectly valid page holding zero rows rather
    # than with an error. Silence must never be read as "this archetype has no online finishes".
    raise ParseError, "no finishes found at #{url} — the format, rotation or set may not exist" if rows.empty?

    rows
  end

  def url = "#{BASE_URL}/decks/#{@slug}?format=#{@format}&rotation=#{@rotation}&set=#{@set}"

  private

  def validated(value, pattern, name)
    string = value.to_s
    raise ArgumentError, "#{name} #{value.inspect} is not a valid #{name}" unless pattern.match?(string)

    string
  end

  def parse_rows(table)
    table.css("tr").filter_map { |tr|
      cells = tr.css("td")
      next unless cells.size == CELL_COUNT

      build_row(tr, cells)
    }
  end

  # Strict per page, lenient per row: an unreadable date, player or placement costs its own row
  # rather than the whole import — one malformed entry among twenty is not a layout change.
  def build_row(tr, cells)
    date = parse_date(tr["data-date"])
    player = parse_player(cells[PLAYER_CELL])
    placement, attendance = parse_placement(cells[PLACEMENT_CELL])
    return if date.nil? || player.nil? || placement.nil?

    wins, losses, ties = parse_record(cells[RECORD_CELL])
    tournament_id, slug = player

    Row.new(
      event_name: tr["data-tournament"].to_s.squish.presence,
      event_date: date,
      division: DIVISION,
      division_suffix: nil,
      format: @format,
      player_name: (cells[PLAYER_CELL].at_css("a")&.text || cells[PLAYER_CELL].text).squish.presence,
      placement: placement,
      list_url: "#{BASE_URL}/tournament/#{tournament_id}/player/#{slug}/decklist",
      player_slug: slug,
      attendance: attendance,
      wins: wins,
      losses: losses,
      ties: ties,
      # The tournament id, so a caller can tell two same-named events apart — online event names
      # are arbitrary and repeat weekly. Nothing writes it to the database.
      event_key: tournament_id
    )
  end

  def parse_date(value)
    Time.iso8601(value.to_s).utc.to_date
  rescue ArgumentError
    nil
  end

  # Returns [tournament_id, player_slug], the row's identity, or nil when the href names no player.
  def parse_player(cell)
    PLAYER_HREF_RE.match(cell.at_css("a")&.[]("href").to_s)&.captures
  end

  def parse_placement(cell)
    text = cell.text.squish
    placement = PLACEMENT_RE.match(text)&.[](1)&.to_i
    [ placement, ATTENDANCE_RE.match(text)&.[](1)&.to_i ]
  end

  def parse_record(cell)
    RECORD_RE.match(cell.text.squish)&.captures&.map(&:to_i) || []
  end
end
