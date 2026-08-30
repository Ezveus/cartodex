require "test_helper"

class Cards::FetcherCacheTest < ActiveSupport::TestCase
  URL = "https://limitlesstcg.com/cards/POR/56".freeze

  setup do
    @honedge_html = File.read(Rails.root.join("test/fixtures/files/POR_56.html"))
    @original_http_fetcher_call = HttpFetcher.method(:call)
    @http_calls = []
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  # --- Known cards are never re-scraped ---

  # This one held before the change too — it is here so a regression that
  # reinstated any kind of refresh window would still be caught at both ends.
  test "issues no HTTP request when the known card is fresh" do
    card = cards(:honedge)
    card.update_column(:updated_at, 12.hours.ago)
    stub_http(URL, @honedge_html)

    result = Cards::Fetcher.call(URL)

    assert_equal 0, @http_calls.size, "a known card must not be scraped"
    assert_equal card.id, result.id
  end

  test "leaves a known card untouched however stale it is" do
    card = cards(:honedge)
    card.update!(name: "Stale Name", price_eur: BigDecimal("99.99"))
    card.update_column(:updated_at, 30.days.ago)
    before = card.reload.attributes
    attacks_before = card.attacks.count
    abilities_before = card.abilities.count
    stub_http(URL, @honedge_html)

    Cards::Fetcher.call(URL)

    assert_equal before, card.reload.attributes
    # assign_attacks/assign_abilities destroy before they rebuild, and that
    # destroy commits on its own. A skip that was not really a skip would show
    # up here and nowhere in `attributes`.
    assert_equal attacks_before, card.attacks.count
    assert_equal abilities_before, card.abilities.count
  end

  test "links a known card to its set when the association is missing" do
    card = cards(:honedge)
    card.update_column(:card_set_id, nil)
    # A sentinel compute_fingerprint would overwrite, so the assertion below
    # really tests the write path rather than comparing nil to nil.
    card.update_column(:fingerprint, "0000000000000000")
    stub_http(URL, @honedge_html)

    Cards::Fetcher.call(URL)

    assert_equal 0, @http_calls.size, "re-linking a set is a local write, not a scrape"
    assert_equal card_sets(:por), card.reload.card_set
    # The link goes in through update_column precisely so compute_fingerprint
    # does not run: re-deriving a card's identity here would move it out of its
    # printing group behind everyone's back.
    assert_equal "0000000000000000", card.fingerprint
  end

  test "issues no HTTP request when the known card is stale" do
    card = cards(:honedge)
    card.update_column(:updated_at, 30.days.ago)
    stub_http(URL, @honedge_html)

    result = Cards::Fetcher.call(URL)

    assert_equal 0, @http_calls.size, "staleness is no longer a reason to scrape"
    assert_equal card.id, result.id
    assert_in_delta 30.days.ago, result.reload.updated_at, 5.seconds
  end

  # --- Unknown cards and the force escape hatch still scrape ---

  test "issues exactly one HTTP request when the card is unknown" do
    cards(:honedge).destroy
    stub_http(URL, @honedge_html)

    assert_difference "Card.count", 1 do
      Cards::Fetcher.call(URL)
    end

    assert_equal [ URL ], @http_calls
  end

  test "issues exactly one HTTP request when forced, however fresh the card is" do
    card = cards(:honedge)
    card.update_column(:updated_at, Time.current)
    stub_http(URL, @honedge_html)

    result = Cards::Fetcher.call(URL, force: true)

    assert_equal [ URL ], @http_calls
    assert_equal card.id, result.id
    assert_in_delta Time.current, result.reload.updated_at, 5.seconds
  end

  test "issues exactly one HTTP request when forced on a stale card" do
    cards(:honedge).update_column(:updated_at, 30.days.ago)
    stub_http(URL, @honedge_html)

    Cards::Fetcher.call(URL, force: true)

    assert_equal [ URL ], @http_calls
  end

  private

  # Records every URL asked for in @http_calls, so a test can assert on the
  # number of round trips rather than only on the record that comes back.
  def stub_http(url, body)
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |u|
      calls << u
      u == url ? body : raise("Unexpected URL: #{u}")
    }
  end
end
