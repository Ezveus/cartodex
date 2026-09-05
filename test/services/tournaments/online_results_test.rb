require "test_helper"

class Tournaments::OnlineResultsTest < ActiveSupport::TestCase
  RESULTS_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_online_results.html")).freeze

  setup do
    @original_http_fetcher_call = HttpFetcher.method(:call)
    @http_calls = []
    stub_http(RESULTS_HTML)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  test "reads every leaderboard row off the one table" do
    rows = call

    assert_equal [ "https://play.limitlesstcg.com/decks/raging-bolt-ogerpon?format=standard&rotation=2026&set=PBL" ],
      @http_calls
    assert_equal 6, rows.size
    assert_equal(
      [ "JRobrueda", "Pumpkaweekly", Date.new(2026, 8, 17), "aaaa1111" ],
      [ rows.first.player_name, rows.first.event_name, rows.first.event_date, rows.first.event_key ]
    )
  end

  # TRAP 1. `data-place` is the row's rank in the leaderboard (1..N in order), not the finish. The
  # row below carries data-place="4" and really placed 2nd; an importer reading the attribute
  # records a second place as a fourth.
  test "reads the placement out of the cell, never off data-place" do
    row = call.find { |r| r.event_key == "dddd4444" }

    assert_equal 2, row.placement
    assert_equal [ 1, 1, 3, 2, 1, 2 ], call.map(&:placement)
  end

  # TRAP 3. The same cell carries the field size after "of" — a figure the paper source does not
  # publish at all, which is why every event imported from it has nil participant counts.
  test "reads the attendance out of the same cell" do
    assert_equal [ 259, 220, 657, 156, 128, 119 ], call.map(&:attendance)
  end

  # TRAP 2. `data-score` is only the wins: the row below carries data-score="7" and a real record of
  # 7 - 1 - 0. Reading the attribute reports every player as undefeated.
  test "reads the whole W - L - T record, never off data-score" do
    row = call.find { |r| r.event_key == "dddd4444" }

    assert_equal [ 7, 1, 0 ], [ row.wins, row.losses, row.ties ]
    assert_equal [ [ 8, 0, 0 ], [ 7, 0, 0 ], [ 10, 2, 0 ], [ 7, 1, 0 ], [ 7, 0, 0 ], [ 7, 3, 0 ] ],
      call.map { |r| [ r.wins, r.losses, r.ties ] }
  end

  # The player's identity is the slug in the href, not the displayed name: `JRobrueda` and
  # `Jose Rueda` are one person, `jrobrueda`. The whole point of the slug is the de-duplication the
  # importer does on `(player slug, list content)` — keyed on the displayed name it splits in two,
  # and one person's list is counted twice in the sample.
  test "identifies a player by the slug in the href rather than by the displayed name" do
    rows = call

    assert_equal [ "JRobrueda", "JRobrueda", "Jose Rueda" ],
      rows.select { |r| r.player_slug == "jrobrueda" }.map(&:player_name)
    assert_equal %w[jrobrueda justinbaby kashmann27 freshgazpacho], rows.map(&:player_slug).uniq
  end

  # A scraped href reaches a link on the preview page, and Brakeman's LinkToHref check does not see
  # Phlex components at all (they are libraries, not templates). So the decklist URL is rebuilt from
  # the ids the href names, absolute, rather than passed through.
  test "rebuilds an absolute decklist URL from the ids rather than trusting the scraped href" do
    assert_equal "https://play.limitlesstcg.com/tournament/aaaa1111/player/jrobrueda/decklist",
      call.first.list_url
  end

  # …and a href that names no player has no identity to rebuild from, so the row goes rather than
  # travelling on with a `javascript:` URL or a nil slug nothing downstream can de-duplicate.
  test "drops a row whose player href is not a player link" do
    stub_http(RESULTS_HTML.sub("/tournament/aaaa1111/player/jrobrueda/decklist", "javascript:alert(1)"))
    rows = call

    assert_equal 5, rows.size
    assert_equal [ "bbbb2222", "cccc3333", "dddd4444", "eeee5555", "ffff6666" ], rows.map(&:event_key)
  end

  # Online play has no age divisions — writing "masters" would be a lie that
  # Archetypes::Performance#by_division then reports as fact.
  test "reports the open division and no suffix" do
    rows = call

    assert_equal [ "open" ], rows.map(&:division).uniq
    assert_equal [ nil ], rows.map(&:division_suffix).uniq
  end

  # Reported verbatim, the way the paper source reports Limitless's own label: what the format
  # becomes in this app is the plan's decision to make and to show, not the parser's to make
  # silently.
  test "reports the format the caller asked for" do
    rows = Tournaments::OnlineResults.call("raging-bolt-ogerpon", format: "expanded", rotation: "2026", set: "PBL")

    assert_equal [ "expanded" ], rows.map(&:format).uniq
    assert_equal [ "https://play.limitlesstcg.com/decks/raging-bolt-ogerpon?format=expanded&rotation=2026&set=PBL" ],
      @http_calls
  end

  test "refuses a page with no table" do
    stub_http("<html><body><p>Nothing here</p></body></html>")

    error = assert_raises(Tournaments::OnlineResults::ParseError) { call }
    assert_match(/no results table/, error.message)
    assert_match(%r{play\.limitlesstcg\.com/decks/raging-bolt-ogerpon}, error.message)
  end

  # The important one. An invalid (rotation, set) pair answers with a perfectly valid page holding
  # zero rows rather than with an error, so silence must never be read as "this archetype has no
  # online finishes".
  # The other empty case, and it must not answer with the other message: a table full of rows this
  # parser rejected is a layout change, and telling the admin to correct a rotation and a set that
  # were fine sends them to fix the one thing that is not broken.
  test "refuses a table whose every row was rejected, and blames the layout rather than the parameters" do
    stub_http(RESULTS_HTML.gsub("</td>", "</td><td>surprise</td>"))

    error = assert_raises(Tournaments::OnlineResults::ParseError) { call }
    assert_match(/layout/, error.message)
    assert_no_match(/rotation or set/, error.message)
  end

  test "refuses a table that holds no row at all" do
    stub_http(<<~HTML)
      <html><body><table><thead>
        <tr><th>Player</th><th>Tournament</th><th>Date</th><th>Place</th><th>Score</th><th>List</th></tr>
      </thead><tbody></tbody></table></body></html>
    HTML

    error = assert_raises(Tournaments::OnlineResults::ParseError) { call }
    assert_match(/no finishes/, error.message)
    assert_match(/rotation or set/, error.message)
  end

  # Strict per page, lenient per row: one unreadable cell costs its own row, not the whole import.
  test "skips a row whose placement cell holds no leading integer" do
    stub_http(RESULTS_HTML.sub("2nd of 156", "TBD"))
    rows = call

    assert_equal 5, rows.size
    assert_empty rows.select { |r| r.event_key == "dddd4444" }
  end

  # Guarded like the date, the player and the placement, and not merely read — unlike the paper
  # source, which cannot produce a nil name because its own comes out of a matched HEADING_RE.
  # Here it is an attribute that may simply be absent, and StandingsImportPlan#build_event calls
  # `name.squish` on whatever arrives: an unguarded nil is a NoMethodError raised inside a preview
  # whose rescue knows only ParseError and FetchError, which is the 500 that rescue exists to
  # prevent.
  test "skips a row carrying no event name rather than letting a nil reach the plan" do
    stub_http(RESULTS_HTML.sub(%(data-tournament="Moujii's Dojo"), %(data-tournament="")))
    rows = call

    assert_equal 5, rows.size
    assert_empty rows.select { |r| r.event_key == "dddd4444" }
    assert(rows.all? { |r| r.event_name.present? })
    # The whole point: the plan this feeds does not raise on it.
    assert_nothing_raised { Tournaments::StandingsImportPlan.call(rows: rows, online: true) }
  end

  # Every one of these is interpolated into a URL, which is the reason
  # Admin::StandingsImportsController::DECK_ID_RE exists for the paper source. They are refused
  # before anything is fetched.
  test "refuses a slug, format, rotation or set that is not a plain identifier" do
    [
      [ "raging bolt/../../evil", "standard", "2026", "PBL" ],
      [ "raging-bolt-ogerpon", "standard&admin=1", "2026", "PBL" ],
      [ "raging-bolt-ogerpon", "standard", "20260", "PBL" ],
      [ "raging-bolt-ogerpon", "standard", "2026", "pbl" ]
    ].each do |slug, format, rotation, set|
      assert_raises(ArgumentError) do
        Tournaments::OnlineResults.call(slug, format: format, rotation: rotation, set: set)
      end
    end

    assert_empty @http_calls
  end

  private

  def call
    Tournaments::OnlineResults.call("raging-bolt-ogerpon", format: "standard", rotation: "2026", set: "PBL")
  end

  def stub_http(html)
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |url|
      calls << url
      html
    }
  end
end
