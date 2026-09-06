require "test_helper"

class CardLabels::LimitlessSearchTest < ActiveSupport::TestCase
  SEARCH_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_card_search.html")).freeze

  setup do
    @original_http = HttpFetcher.method(:call)
    @urls = []
    stub_http(SEARCH_HTML)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http)
  end

  # One request, not a page walk: `show=all` returns every match at once. Measured against the
  # live source — is:ace 46 of 46 in 25 KB, is:tera 151 of 151, is:ex 986 of 986 in 234 KB, a
  # quarter of the standings page HttpFetcher already reads inside its 30-second read timeout.
  test "reads the whole label in a single request" do
    result = CardLabels::LimitlessSearch.call("is:ace")

    assert_equal [ "https://limitlesstcg.com/cards?q=is%3Aace&show=all" ], @urls
    assert_equal [
      [ "PRE", "116" ], [ "PRE", "117" ], [ "TEF", "157" ], [ "SVI", "SV107" ]
    ], result.printings.map { |p| [ p.set_code, p.number ] }
  end

  # A set number is a String holding something like "SV107" as often as it holds a number, and it
  # is half of the (set_name, set_number) pair the importer looks a printing up by.
  test "keeps a non-numeric card number as written" do
    assert_includes CardLabels::LimitlessSearch.call("is:ace").printings.map(&:number), "SV107"
  end

  # The count the page states is the integrity check. A run that read four of an announced seven
  # has to be able to say so rather than implying the source lost three cards.
  test "reads the count the page announces and compares it" do
    result = CardLabels::LimitlessSearch.call("is:ace")

    assert_equal 7, result.announced_count
    assert_not result.complete?
  end

  test "a page with no card grid is a ParseError naming the URL" do
    stub_http("<html><body><p>Nothing here.</p></body></html>")

    error = assert_raises(CardLabels::LimitlessSearch::ParseError) do
      CardLabels::LimitlessSearch.call("is:ace")
    end

    assert_match "cards?q=is%3Aace", error.message
  end

  # The token is interpolated into a URL that is then fetched. HttpFetcher refuses a non-HTTP URI
  # as a backstop, but a backstop is not the caller saying what it will interpolate.
  test "a token that is not a search term is refused before any request" do
    assert_raises(ArgumentError) { CardLabels::LimitlessSearch.call("is:ace https://evil.test") }
    assert_empty @urls
  end

  private

  def stub_http(body)
    urls = @urls
    HttpFetcher.define_singleton_method(:call) do |url|
      urls << url
      body
    end
  end
end
