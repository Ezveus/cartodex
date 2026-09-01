require "test_helper"

class CardSets::ImporterTest < ActiveSupport::TestCase
  SET_URL = "https://limitlesstcg.com/cards/POR".freeze

  SET_HTML = <<~HTML.freeze
    <html><body>
      <h1>Perfect Order (POR)</h1>
      <img src="https://limitlesstcg.com/sets/POR.png">
      <a href="/cards/POR/56">Honedge</a>
      <a href="/cards/POR/57">Doublade</a>
    </body></html>
  HTML

  setup do
    @original_http_fetcher_call = HttpFetcher.method(:call)
    @http_calls = []
    stub_http
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  test "re-links a skipped card whose set is wrong" do
    honedge = cards(:honedge)
    honedge.update_column(:card_set_id, card_sets(:twm).id)
    # The card is skipped by Cards::Fetcher; the re-link is a local write that
    # must happen anyway.
    Card.where(set_name: "POR", set_number: %w[56 57]).update_all(updated_at: 30.days.ago)

    result = CardSets::Importer.call(SET_URL)

    assert_equal card_sets(:por), honedge.reload.card_set
    assert_equal 2, result[:imported]
  end

  test "scrapes the set page only, never its already-known cards" do
    # Aged past any freshness window: presence alone must be enough to skip.
    Card.where(set_name: "POR", set_number: %w[56 57]).update_all(updated_at: 30.days.ago)

    CardSets::Importer.call(SET_URL)

    assert_equal [ SET_URL ], @http_calls
  end

  # A set imported from the admin panel used to arrive with a NULL release_date,
  # which every date-driven rule then read as "never released".
  CRI_URL = "https://limitlesstcg.com/cards/CRI".freeze

  # No card links, so Cards::Fetcher is never reached and no card page is needed.
  CRI_HTML = <<~HTML.freeze
    <html><body>
      <div class="infobox">
        <div class="infobox-heading sm">Chaos Rising (CRI)</div>
        <div class="infobox-line"> 22nd May 2026  •  122 Cards • $641.12 • 578.42€ </div>
      </div>
    </body></html>
  HTML

  UNRELEASED_HTML = <<~HTML.freeze
    <html><body>
      <div class="infobox">
        <div class="infobox-heading sm">Chaos Rising (CRI)</div>
        <div class="infobox-line"> 122 Cards </div>
      </div>
    </body></html>
  HTML

  test "records the release date printed on the set page" do
    stub_http(CRI_URL => CRI_HTML)

    result = CardSets::Importer.call(CRI_URL)

    assert_equal Date.new(2026, 5, 22), result[:card_set].release_date
  end

  test "leaves a release date already on the record alone" do
    # POR is fixtured at 2026-01-16. The page deliberately claims a different,
    # obviously wrong date: a hand-seeded date must win over a scrape.
    page = SET_HTML.sub("<h1>", <<~INFOBOX + "<h1>")
      <div class="infobox"><div class="infobox-line">9th September 2099 • 4 Cards</div></div>
    INFOBOX
    stub_http(SET_URL => page)

    CardSets::Importer.call(SET_URL)

    assert_equal Date.new(2026, 1, 16), card_sets(:por).reload.release_date
  end

  test "leaves the release date nil when the page prints none" do
    stub_http(CRI_URL => UNRELEASED_HTML)

    result = CardSets::Importer.call(CRI_URL)

    assert_nil result[:card_set].release_date
  end

  private

  # Serves a url => html map and records every URL asked for, so a test can
  # assert that the per-card pages were never requested.
  def stub_http(pages = { SET_URL => SET_HTML })
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |u|
      calls << u
      pages.fetch(u) { raise "Unexpected URL: #{u}" }
    }
  end
end
