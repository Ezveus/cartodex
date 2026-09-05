require "test_helper"

class Tournaments::LimitlessDecklistTest < ActiveSupport::TestCase
  URL = "https://limitlesstcg.com/decks/list/28788".freeze
  DECKLIST_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_decklist.html")).freeze

  setup do
    @original_http_fetcher_call = HttpFetcher.method(:call)
    stub_http(DECKLIST_HTML)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  test "emits the PTCG line format Decks::Fetcher already parses" do
    text = Tournaments::LimitlessDecklist.call(URL)

    assert_equal "4 Mega Kangaskhan ex MEG 104", text.lines.first.strip
    # The point of the whole class: every line it emits has to survive the regex on the other
    # side, which drops what it cannot match without raising.
    assert_equal text.lines.size, text.lines.count { |line| line.strip.match?(Decks::Fetcher::CARD_LINE_RE) }
    assert_equal 60, text.lines.sum { |line| line.to_i }
  end

  # The page renders the same cards twice — `[data-text-decklist]` with data-set/data-number and a
  # textual `.card-count`, `[data-image-decklist]` with neither (its count is an `<img alt="4">`).
  # Reading the text view is therefore a shape this parser depends on, not an implementation
  # detail, and a page that no longer has one has to be refused rather than parsed out of whatever
  # `.decklist-card` markup happens to remain. Removing the scoping makes this test pass a page it
  # has never seen.
  test "refuses a page whose text view is gone" do
    stub_http(DECKLIST_HTML.sub("data-text-decklist", "data-something-else"))

    error = assert_raises(Tournaments::LimitlessDecklist::ParseError) { Tournaments::LimitlessDecklist.call(URL) }

    assert_match(/no decklist found/, error.message)
  end

  test "reads one line per distinct printing" do
    assert_equal 15, Tournaments::LimitlessDecklist.call(URL).lines.size
  end

  test "refuses a list that does not add up to sixty" do
    stub_http(File.read(Rails.root.join("test/fixtures/files/limitless_decklist_incomplete.html")))

    error = assert_raises(Tournaments::LimitlessDecklist::ParseError) { Tournaments::LimitlessDecklist.call(URL) }

    assert_match(/parsed to 59 cards, not 60/, error.message)
  end

  # Decks::Fetcher::CARD_LINE_RE wants [A-Z]{2,3} and silently drops a line it cannot match, so a
  # four-character set code would land as a deck quietly missing four cards. It has to be refused
  # here, while there is still a card name to put in the message.
  test "refuses a set code cartodex cannot address, and names the card" do
    stub_http(File.read(Rails.root.join("test/fixtures/files/limitless_decklist_unsupported_set.html")))

    error = assert_raises(Tournaments::LimitlessDecklist::ParseError) { Tournaments::LimitlessDecklist.call(URL) }

    assert_match(/Mega Kangaskhan ex/, error.message)
    assert_match(/SV9a/, error.message)
  end

  # The other half of the same guard as the set code: CARD_LINE_RE wants `(\d+)\z` and drops what
  # it cannot match without a word, so a lettered card number — a Trainer Gallery style "TG05" —
  # would land as a field list four cards short that nothing anywhere reports.
  test "refuses a card number cartodex cannot address, and names the card" do
    stub_http(DECKLIST_HTML.sub('data-number="104"', 'data-number="TG05"'))

    error = assert_raises(Tournaments::LimitlessDecklist::ParseError) { Tournaments::LimitlessDecklist.call(URL) }

    assert_match(/Mega Kangaskhan ex/, error.message)
    assert_match(/MEG TG05/, error.message)
  end

  test "refuses a card carrying no printing" do
    stub_http(DECKLIST_HTML.sub('data-set="MEG" data-number="104"', 'data-set="" data-number=""'))

    error = assert_raises(Tournaments::LimitlessDecklist::ParseError) { Tournaments::LimitlessDecklist.call(URL) }

    assert_match(/carries no printing/, error.message)
  end

  test "refuses a page with no decklist on it" do
    stub_http("<html><body><p>Deleted</p></body></html>")

    assert_raises(Tournaments::LimitlessDecklist::ParseError) { Tournaments::LimitlessDecklist.call(URL) }
  end

  private

  def stub_http(html)
    HttpFetcher.define_singleton_method(:call) { |_url| html }
  end
end
