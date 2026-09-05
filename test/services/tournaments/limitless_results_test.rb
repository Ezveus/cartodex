require "test_helper"

class Tournaments::LimitlessResultsTest < ActiveSupport::TestCase
  RESULTS_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_deck_results.html")).freeze

  setup do
    @original_http_fetcher_call = HttpFetcher.method(:call)
    @http_calls = []
    stub_http(RESULTS_HTML)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  test "reads every placement row, including one with no decklist" do
    rows = Tournaments::LimitlessResults.call(280)

    assert_equal [ "https://limitlesstcg.com/decks/280/results" ], @http_calls
    assert_equal 7, rows.size
    assert_equal [ "Tomi Markkula", 4, "https://limitlesstcg.com/decks/list/28788" ],
      [ rows.first.player_name, rows.first.placement, rows.first.list_url ]
    # 21 of the 1569 rows on the real page name a player with no public list. They are still
    # standings — a placement and an archetype is a record — so they must survive the parse.
    assert_nil rows.second.list_url
    assert_equal "James Cox", rows.second.player_name
  end

  # The one mistake here that no later correction undoes cheaply: /tournaments/518,
  # /tournaments/518/SR and /tournaments/518/JR are three age divisions of ONE event, and
  # Tournament identity is (name_normalized, date). Keep the suffix and the public catalog grows a
  # permanent duplicate row per division, per event, per import.
  test "folds the JR and SR headings into the event they belong to" do
    rows = Tournaments::LimitlessResults.call(280)
    naic = rows.select { |row| row.event_name.include?("NAIC") }

    assert_equal 4, naic.size
    assert_equal [ "NAIC 2026, New Orleans" ], naic.map(&:event_name).uniq
    assert_equal [ Date.new(2026, 6, 10) ], naic.map(&:event_date).uniq
    assert_equal({ "masters" => 2, "senior" => 1, "junior" => 1 }, naic.map(&:division).tally)
  end

  test "reads the date off the heading and the format off the row" do
    rows = Tournaments::LimitlessResults.call(280)

    assert_equal Date.new(2026, 8, 28), rows.first.event_date
    assert_equal "World Championships 2026", rows.first.event_name
    # Reported verbatim. "standard-jp" is the Japanese card pool and the enum has no such value —
    # folding it to "standard" here would anchor a Japanese event to a western StandardPool, which
    # is a decision for the plan to make and show, not for the parser to make silently.
    assert_equal "standard-jp", rows.find { |row| row.player_name == "Kenji Watanabe" }.format
  end

  # A scraped href reaches a link on the preview page, and Brakeman's LinkToHref check does not
  # see Phlex components at all (they are libraries, not templates). So the URL is rebuilt from the
  # list id rather than trusted, and a href that is not a decklist link yields no URL.
  test "rebuilds the decklist URL from its id rather than trusting the scraped href" do
    stub_http(RESULTS_HTML.sub("/decks/list/28788", "javascript:alert(1)"))

    assert_nil Tournaments::LimitlessResults.call(280).first.list_url
  end

  test "refuses a page with no results table" do
    stub_http("<html><body><p>Nothing here</p></body></html>")

    error = assert_raises(Tournaments::LimitlessResults::ParseError) do
      Tournaments::LimitlessResults.call(280)
    end
    assert_match(/no results table/, error.message)
  end

  test "refuses a table that holds no placement at all" do
    stub_http(<<~HTML)
      <html><body><table class="data-table striped">
        <tr><th></th><th>Place</th><th>Variant</th><th>Player</th><th>List</th></tr>
      </table></body></html>
    HTML

    assert_raises(Tournaments::LimitlessResults::ParseError) { Tournaments::LimitlessResults.call(280) }
  end

  # Only /JR and /SR occur today (measured: 38 and 24 against 114 bare headings). A third suffix
  # must surface as a refused row rather than being filed as Masters, which is what a bare
  # `DIVISION_BY_SUFFIX.fetch(suffix, "masters")` would have done.
  test "leaves the division unknown rather than guessing Masters for a new suffix" do
    stub_http(RESULTS_HTML.sub("/tournaments/518/SR", "/tournaments/518/XX").sub("(SR)", "(XX)"))

    row = Tournaments::LimitlessResults.call(280).find { |r| r.player_name == "Ellie Nakamura" }

    assert_nil row.division
    assert_equal "XX", row.division_suffix
    # The name keeps its suffix too — nothing may quietly merge an event whose division nobody
    # could read into the Masters row of the same tournament.
    assert_equal "NAIC 2026, New Orleans (XX)", row.event_name
  end

  private

  def stub_http(html)
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |url|
      calls << url
      html
    }
  end
end
