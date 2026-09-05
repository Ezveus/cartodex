require "test_helper"

class Tournaments::OnlineDecklistTest < ActiveSupport::TestCase
  URL = "https://play.limitlesstcg.com/tournament/aaaa1111/player/jrobrueda/decklist".freeze
  DECKLIST_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_online_decklist.html")).freeze

  setup do
    @original_http_fetcher_call = HttpFetcher.method(:call)
    stub_http(DECKLIST_HTML)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  test "emits the PTCG line format Decks::Fetcher already parses" do
    text = Tournaments::OnlineDecklist.call(URL)

    # The trailing " (MEG-104)" the page prints beside a Pokémon name is a printing, not part of
    # the name: left in, the line reads "4 Mega Kangaskhan ex (MEG-104) MEG 104" and Decks::Fetcher
    # looks up a card nobody printed.
    assert_equal "4 Mega Kangaskhan ex MEG 104", text.lines.first.strip
    assert_equal 60, text.lines.sum { |line| line.to_i }
  end

  test "reads one line per printing, across all three columns" do
    assert_equal 26, Tournaments::OnlineDecklist.call(URL).lines.size
  end

  # THE TRAP. Only the Pokémon lines carry "(SET-NUM)" in their visible text; a Trainer reads
  # "4 Crispin" and an Energy "7 Grass Energy", with no printing anywhere in the text. The set and
  # number live in the href alone — so a parser that regexes the text emits 15 usable lines and
  # loses the other 11 to CARD_LINE_RE, which drops what it cannot match without a word.
  test "takes the printing from the href on lines whose text carries none" do
    lines = Tournaments::OnlineDecklist.call(URL).lines.map(&:strip)

    assert_includes lines, "4 Crispin SCR 133"
    assert_includes lines, "2 Boss's Orders MEG 114"
    assert_includes lines, "7 Grass Energy MEE 1"
    assert_equal lines.size, lines.count { |line| line.match?(Decks::Fetcher::CARD_LINE_RE) }
  end

  # The other half of the same rule, stated so it cannot be satisfied by regexing the text and
  # merely tolerating the lines that have no printing: where the two disagree, the href wins.
  test "prefers the href over the printing printed in the text" do
    stub_http(DECKLIST_HTML.sub("/cards/MEG/104", "/cards/PAL/12"))

    text = Tournaments::OnlineDecklist.call(URL)

    assert_equal "4 Mega Kangaskhan ex PAL 12", text.lines.first.strip
    refute_match(/Mega Kangaskhan ex MEG 104/, text)
  end

  # The point of the whole class: every line it emits has to survive the regex on the other side,
  # and carry the printing the page actually linked to, in the page's own order.
  test "every emitted line matches CARD_LINE_RE and captures the hrefs' own printings" do
    hrefs = DECKLIST_HTML.scan(%r{/cards/([A-Za-z0-9]+)/(\d+)})

    captured = Tournaments::OnlineDecklist.call(URL).lines.map do |line|
      match = line.strip.match(Decks::Fetcher::CARD_LINE_RE)
      assert match, "#{line.strip.inspect} does not match Decks::Fetcher::CARD_LINE_RE"
      [ match[3], match[4] ]
    end

    assert_equal 26, hrefs.size
    assert_equal hrefs, captured
  end

  test "refuses a page with no decklist on it" do
    stub_http("<html><body><p>This player did not submit a decklist.</p></body></html>")

    error = assert_raises(Tournaments::OnlineDecklist::ParseError) { Tournaments::OnlineDecklist.call(URL) }

    assert_match(/no decklist found/, error.message)
    assert_match(URL, error.message)
  end

  test "refuses a decklist block that holds no card lines" do
    stub_http(DECKLIST_HTML.gsub(%r{<p>.*</p>}, ""))

    error = assert_raises(Tournaments::OnlineDecklist::ParseError) { Tournaments::OnlineDecklist.call(URL) }

    assert_match(/no decklist found/, error.message)
  end

  # A card whose link does not name a printing is the one shape this parser has nothing to fall
  # back on: the text does not carry it either. Refuse while there is still a card name to say.
  test "refuses a card linking somewhere other than a card page, and names the card" do
    stub_http(DECKLIST_HTML.sub("https://limitlesstcg.com/cards/SCR/133", "/tournament/aaaa1111"))

    error = assert_raises(Tournaments::OnlineDecklist::ParseError) { Tournaments::OnlineDecklist.call(URL) }

    assert_match(/Crispin/, error.message)
    assert_match(%r{/tournament/aaaa1111}, error.message)
  end

  test "refuses a card carrying no link at all, and names the card" do
    stub_http(DECKLIST_HTML.sub(' href="https://limitlesstcg.com/cards/SCR/133"', ""))

    error = assert_raises(Tournaments::OnlineDecklist::ParseError) { Tournaments::OnlineDecklist.call(URL) }

    assert_match(/Crispin/, error.message)
  end

  # Decks::Fetcher::CARD_LINE_RE wants [A-Z]{2,3} and silently drops a line it cannot match, so a
  # Japanese set code would land as a deck quietly missing four cards. It has to be refused here,
  # while there is still a card name to put in the message.
  test "refuses a set code cartodex cannot address, and names the card" do
    stub_http(DECKLIST_HTML.sub("/cards/MEG/104", "/cards/SV9a/104"))

    error = assert_raises(Tournaments::OnlineDecklist::ParseError) { Tournaments::OnlineDecklist.call(URL) }

    assert_match(/Mega Kangaskhan ex/, error.message)
    assert_match(/SV9a/, error.message)
  end

  # The other half of the same guard: CARD_LINE_RE wants `(\d+)\z` and drops what it cannot match
  # without a word, so a Trainer Gallery style "TG05" would land as a field list four cards short.
  test "refuses a card number cartodex cannot address, and names the card" do
    stub_http(DECKLIST_HTML.sub("/cards/MEG/104", "/cards/MEG/TG05"))

    error = assert_raises(Tournaments::OnlineDecklist::ParseError) { Tournaments::OnlineDecklist.call(URL) }

    assert_match(/Mega Kangaskhan ex/, error.message)
    assert_match(/MEG TG05/, error.message)
  end

  test "refuses a card whose count is unreadable" do
    stub_http(DECKLIST_HTML.sub(">4 Crispin<", ">Crispin<"))

    error = assert_raises(Tournaments::OnlineDecklist::ParseError) { Tournaments::OnlineDecklist.call(URL) }

    assert_match(/Crispin/, error.message)
    assert_match(/unreadable count/, error.message)
  end

  test "refuses a list that does not add up to sixty" do
    # Both halves have to move together, or the column check below fires first: this is the case
    # where every column agrees with its own heading and the deck is still short.
    stub_http(DECKLIST_HTML.sub("Energy (14)", "Energy (13)").sub(">7 Grass Energy<", ">6 Grass Energy<"))

    error = assert_raises(Tournaments::OnlineDecklist::ParseError) { Tournaments::OnlineDecklist.call(URL) }

    assert_match(/parsed to 59 cards, not 60/, error.message)
  end

  # The sixty check alone cannot see this: a column that silently loses a line still sums to sixty
  # if another column gained one. This source hands us three subtotals — one per column heading —
  # and a disagreement is exactly the shape change that would otherwise import a deck nobody
  # played. The deck below still totals sixty; only the Pokémon heading disagrees.
  test "refuses a column that disagrees with its own heading, and names the column" do
    stub_http(DECKLIST_HTML.sub("Pokémon (19)", "Pokémon (18)"))

    error = assert_raises(Tournaments::OnlineDecklist::ParseError) { Tournaments::OnlineDecklist.call(URL) }

    assert_match(/Pokémon/, error.message)
    assert_match(/19 cards, not the 18/, error.message)
  end

  test "refuses a column whose heading carries no subtotal" do
    stub_http(DECKLIST_HTML.sub("Pokémon (19)", "Pokémon"))

    error = assert_raises(Tournaments::OnlineDecklist::ParseError) { Tournaments::OnlineDecklist.call(URL) }

    assert_match(/unreadable heading/, error.message)
  end

  private

  def stub_http(html)
    HttpFetcher.define_singleton_method(:call) { |_url| html }
  end
end
