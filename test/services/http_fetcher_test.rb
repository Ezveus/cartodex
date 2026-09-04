require "test_helper"

# HttpFetcher is the single choke point for every request this app makes to another site: the card
# scraper, the set importer, the Limitless standings import and the public image proxy all go
# through it. The guards below are the ones nothing else can make up for.
class HttpFetcherTest < ActiveSupport::TestCase
  # The backstop behind every caller-side rule about what may be interpolated into a URL. The
  # standings import validates its Limitless deck id against /\A\d+\z/ before building one, and
  # that check is tested where it lives — but a caller that forgets is exactly what this is for,
  # and Net::HTTP must never be handed a scheme it was not meant to open.
  test "refuses a URL that is not HTTP" do
    [ "ftp://example.com/x", "file:///etc/passwd", "javascript:alert(1)", "/decks/280/results" ].each do |url|
      error = assert_raises(HttpFetcher::FetchError, "#{url} should have been refused") { HttpFetcher.call(url) }
      assert_match(/is not an HTTP URL/, error.message)
    end
  end

  # URI::InvalidURIError is not a class any caller rescues — CardsController#image answers 502 for
  # a FetchError and 500 for anything else — so a malformed image_url on a Card would have been a
  # crash on a public page.
  test "reports a malformed URL as a fetch failure" do
    error = assert_raises(HttpFetcher::FetchError) { HttpFetcher.call("http://[") }

    assert_match(/is not a URL/, error.message)
  end

  # Scraping thousands of pages anonymously is how a block arrives with no way to ask about it.
  test "identifies itself" do
    assert_match(%r{\ACartodex/\d}, HttpFetcher::USER_AGENT)
    assert_includes HttpFetcher::USER_AGENT, "https://"
  end

  # Net::HTTP defaults both to 60 seconds. That is long enough for one hung remote to hold one of
  # five Puma threads for a minute — and the image proxy is reachable by anyone.
  test "bounds how long a request may hang" do
    assert_operator HttpFetcher::OPEN_TIMEOUT, :<=, 15
    assert_operator HttpFetcher::READ_TIMEOUT, :<=, 30
  end
end
