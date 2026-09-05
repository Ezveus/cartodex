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

  # The same shape, but the suffix is mandatory: this one answers "did this player publish a list",
  # and PLAYER_HREF_RE cannot, since it matches the bare player link too.
  DECKLIST_HREF_RE = %r{\A/tournament/([A-Za-z0-9]+)/player/([A-Za-z0-9._-]+)/decklist\z}

  CELL_COUNT = 6
  PLAYER_CELL = 0
  PLACEMENT_CELL = 3
  RECORD_CELL = 4
  LIST_CELL = 5

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
    #
    # Two different causes reach this line and they need different answers. An empty <tbody> is
    # the parameter case above. A table full of <tr>s that every row guard rejected is a layout
    # change — and telling that admin to correct a rotation and a set that were fine sends them to
    # fix the one thing that is not broken.
    raise ParseError, empty_reason(table) if rows.empty?

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

  # A table holding data rows this parser threw away is a layout change; a table holding none at
  # all is the (rotation, set) pair. The discriminator is "any <tr> with a <td> in it" and not the
  # CELL_COUNT test itself — a row that gained a seventh cell is exactly the layout change to
  # report, and asking the same question that rejected it would answer "your parameters".
  def empty_reason(table)
    return "no finishes found at #{url} — the format, rotation or set may not exist" if
      table.css("tr").none? { |tr| tr.css("td").any? }

    "no readable finishes at #{url} — every row was rejected, so the page layout may have changed"
  end

  # Strict per page, lenient per row: an unreadable date, player, placement or event name costs
  # its own row rather than the whole import — one malformed entry among twenty is not a layout
  # change.
  #
  # The name is guarded like the rest and not merely read, unlike LimitlessResults, which cannot
  # produce a nil one (its name comes out of a matched HEADING_RE). Here it is an attribute that
  # may simply be absent, and StandingsImportPlan#build_event calls `name.squish` on it — so a
  # <tr> with no data-tournament is a NoMethodError inside a preview whose rescue only knows
  # ParseError and FetchError, i.e. the 500 that rescue exists to prevent.
  def build_row(tr, cells)
    date = parse_date(tr["data-date"])
    name = tr["data-tournament"].to_s.squish.presence
    player = parse_player(cells[PLAYER_CELL])
    placement, attendance = parse_placement(cells[PLACEMENT_CELL])
    player_name = parse_player_name(cells[PLAYER_CELL])
    return if date.nil? || name.nil? || player.nil? || placement.nil? || player_name.nil?

    wins, losses, ties = parse_record(cells[RECORD_CELL])
    tournament_id, slug = player

    Row.new(
      event_name: name,
      event_date: date,
      division: DIVISION,
      division_suffix: nil,
      format: @format,
      player_name: player_name,
      placement: placement,
      list_url: parse_list_url(cells[LIST_CELL]),
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

  # Guarded like the other four rather than left to fail downstream: `.presence` can come back nil
  # — an <a> whose href matches but whose text is empty falls through `&.text || cell.text`, since
  # "" is truthy — and the row is then refused far away at `create!`, on a receipt line that has no
  # name to print. "Strict per page, lenient per row" already says a row that cannot be read costs
  # its own row.
  def parse_player_name(cell)
    (cell.at_css("a")&.text || cell.text).squish.presence
  end

  # Read from the row rather than synthesised from the player's ids, and the sibling
  # Tournaments::LimitlessResults#parse_list_url does the same. A synthesised URL is never nil, so
  # a row whose player published no list becomes a 404 that HttpFetcher raises as a FetchError and
  # the importer counts against its abort budget — five such rows adjacent on a leaderboard would
  # stop a run under a message about the far side going away, when Limitless answered correctly
  # every time. It is also what makes StandingsImporter#prefetch's own `list_url.blank?` guard
  # reachable at all; synthesised, that line was unreachable.
  #
  # Measured on 2026-09-05: 145 rows over 12 leaderboards all carry a list, so this is robustness
  # rather than a live defect — a "best finishes" board links its lists by construction. The guard
  # costs one cell read and removes a way for the source to stop a run by being merely incomplete.
  def parse_list_url(cell)
    match = DECKLIST_HREF_RE.match(cell&.at_css("a")&.[]("href").to_s)
    return if match.nil?

    "#{BASE_URL}/tournament/#{match[1]}/player/#{match[2]}/decklist"
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
