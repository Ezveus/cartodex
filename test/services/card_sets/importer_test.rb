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

  private

  # Serves the set index page and records every URL asked for, so a test can
  # assert that the per-card pages were never requested.
  def stub_http
    calls = @http_calls
    set_url = SET_URL
    set_html = SET_HTML
    HttpFetcher.define_singleton_method(:call) { |u|
      calls << u
      u == set_url ? set_html : raise("Unexpected URL: #{u}")
    }
  end
end
