require "test_helper"

class Tournaments::LimitlessUrlTest < ActiveSupport::TestCase
  ONLINE = Tournaments::LimitlessImportJob::ONLINE_SOURCE
  EVENT = Tournaments::LimitlessImportJob::EVENT_SOURCE

  def parse(text) = Tournaments::LimitlessUrl.call(text)

  def refusal(text)
    assert_raises(Tournaments::LimitlessUrl::ParseError) { parse(text) }.message
  end

  # The three URLs the screen was asked to accept, as an admin copies them out of the address bar.
  test "a paper results page names its deck" do
    parsed = parse("https://limitlesstcg.com/decks/284/results")

    assert_equal "paper", parsed.source
    assert_equal "284", parsed.deck_id
    assert_nil parsed.tournament_id
    assert_nil parsed.slug
  end

  test "an online leaderboard names its slug, rotation and set" do
    parsed = parse("https://play.limitlesstcg.com/decks/dragapult-ex?format=standard&rotation=2026&set=30C")

    assert_equal ONLINE, parsed.source
    assert_equal "dragapult-ex", parsed.slug
    assert_equal "2026", parsed.rotation
    assert_equal "30C", parsed.set
    assert_nil parsed.deck_id
  end

  test "an event page names its tournament" do
    parsed = parse("https://limitlesstcg.com/tournaments/578")

    assert_equal EVENT, parsed.source
    assert_equal "578", parsed.tournament_id
    assert_nil parsed.deck_id
  end

  # The spellings a copy-paste actually produces. Limitless's own links end the online path with a
  # slash, and an address bar may hand back http, www. or a fragment.
  test "the spellings a copied URL arrives in are all read" do
    {
      "  https://limitlesstcg.com/decks/284/results  " => "284",
      "https://limitlesstcg.com/decks/284/results/" => "284",
      "https://limitlesstcg.com/decks/284" => "284",
      "http://www.limitlesstcg.com/decks/284/results#top" => "284",
      "HTTPS://LimitlessTCG.com/decks/284/results" => "284",
      # A non-breaking space comes along when the address is copied out of a web page rather than
      # an address bar, and String#strip leaves it in place — URI.parse then refuses the whole URL.
      "https://limitlesstcg.com/decks/284/results\u00A0" => "284",
      "\u00A0https://limitlesstcg.com/decks/284/results" => "284"
    }.each do |text, deck_id|
      assert_equal [ "paper", deck_id ], [ parse(text).source, parse(text).deck_id ], text
    end

    online = parse("https://play.limitlesstcg.com/decks/dragapult-ex/?format=standard&rotation=2026&set=30C")
    assert_equal [ ONLINE, "dragapult-ex", "30C" ], [ online.source, online.slug, online.set ]
  end

  # Every page the event itself links to is still that event: its division pages, its decklists,
  # its statistics. A run reads every division whichever one was pasted.
  test "an event's sub-pages name the same event" do
    %w[JR SR decklists statistics cards].each do |page|
      parsed = parse("https://limitlesstcg.com/tournaments/578/#{page}")

      assert_equal [ EVENT, "578" ], [ parsed.source, parsed.tournament_id ], page
    end
  end

  # Measured: ?variant=3 serves 1.58 MB against the whole deck's 3.12 MB. LimitlessResults reads the
  # whole deck, so dropping the parameter would import about twice what the admin was looking at.
  test "a paper variant page is refused rather than widened to the whole deck" do
    %w[
      https://limitlesstcg.com/decks/284/results?variant=3
      https://limitlesstcg.com/decks/284?variant=3
      https://limitlesstcg.com/decks/284/?variant=3
    ].each do |text|
      message = refusal(text)

      assert_match "variant", message, text
      assert_match "284", message, text
    end
  end

  # The set anchors every row the run writes to a Standard pool, and the bare page's default follows
  # the newest set. It has to come from the admin, not from whatever Limitless defaulted to that day.
  test "an online URL missing any of its three parameters is refused, naming it" do
    full = { "format" => "standard", "rotation" => "2026", "set" => "30C" }

    full.each_key do |missing|
      query = full.except(missing).to_query
      message = refusal("https://play.limitlesstcg.com/decks/dragapult-ex?#{query}")

      assert_match missing, message, "missing #{missing}"
    end
    assert_match "rotation", refusal("https://play.limitlesstcg.com/decks/dragapult-ex")
  end

  # The job fetches with ONLINE_FORMAT whatever the URL says, so another format would import the
  # Standard leaderboard under a URL that named a different one.
  test "an online URL in another format is refused" do
    message = refusal("https://play.limitlesstcg.com/decks/dragapult-ex?format=expanded&rotation=2026&set=30C")

    assert_match "expanded", message
  end

  test "anything that is not one of the three pages is refused, naming the three" do
    [
      "",
      "   ",
      "not a url at all",
      "ftp://limitlesstcg.com/decks/284/results",
      "https://example.com/decks/284/results",
      "https://limitlesstcg.com.evil.example/decks/284/results",
      "https://limitlesstcg.com/decks/list/12345",
      "https://limitlesstcg.com/tournaments",
      "https://limitlesstcg.com/tournaments/578/JR/extra",
      "https://play.limitlesstcg.com/tournament/abc/standings",
      "https://play.limitlesstcg.com/decks/dragapult-ex/matchups?format=standard&rotation=2026&set=30C",
      "https://limitlesstcg.com/decks/dragapult-ex?format=standard&rotation=2026&set=30C",
      "https://play.limitlesstcg.com/decks/284/results"
    ].each do |text|
      message = refusal(text)

      assert_match "limitlesstcg.com/decks/<id>/results", message, text.inspect
      assert_match "limitlesstcg.com/tournaments/<id>", message, text.inspect
    end
  end

  # Extraction and validation are two jobs. The controller's guards (SLUG_RE, SET_RE, …) already
  # refuse a value that cannot go into a URL, before anything is fetched, and they say why. The
  # parser hands such a value over rather than answering with a vaguer "not a Limitless URL".
  test "a value the controller's guards will refuse is still extracted" do
    parsed = parse("https://play.limitlesstcg.com/decks/Dragapult-EX?format=standard&rotation=26&set=30c")

    assert_equal [ "Dragapult-EX", "26", "30c" ], [ parsed.slug, parsed.rotation, parsed.set ]
  end
end
