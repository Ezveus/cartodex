require "test_helper"

class Cards::FetcherCacheTest < ActiveSupport::TestCase
  setup do
    @honedge_html = File.read(Rails.root.join("test/fixtures/files/POR_56.html"))
    @original_http_fetcher_call = HttpFetcher.method(:call)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  # --- 1-day cache ---

  test "skips fetch when card was updated less than 1 day ago" do
    card = cards(:honedge)
    card.update_column(:updated_at, 12.hours.ago)
    http_called = false

    HttpFetcher.define_singleton_method(:call) { |_url|
      http_called = true
      @honedge_html
    }

    result = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/56")

    assert_not http_called, "HttpFetcher should not have been called for a fresh card"
    assert_equal card.id, result.id
  end

  test "fetches when card was updated more than 1 day ago" do
    card = cards(:honedge)
    card.update_column(:updated_at, 2.days.ago)

    stub_http("https://limitlesstcg.com/cards/POR/56", @honedge_html)

    result = Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/56")

    assert_equal card.id, result.id
    assert_in_delta Time.current, result.reload.updated_at, 5.seconds
  end

  test "fetches when card does not exist" do
    cards(:honedge).destroy

    stub_http("https://limitlesstcg.com/cards/POR/56", @honedge_html)

    assert_difference "Card.count", 1 do
      Cards::Fetcher.call("https://limitlesstcg.com/cards/POR/56")
    end
  end

  private

  def stub_http(url, body)
    HttpFetcher.define_singleton_method(:call) { |u| u == url ? body : raise("Unexpected URL: #{u}") }
  end
end
