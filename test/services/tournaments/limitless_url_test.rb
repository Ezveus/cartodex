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

  # The paper page has six filters, each written into the URL only once it is picked, and the
  # unfiltered page carries none. LimitlessResults reads the whole deck, so a dropped filter is a
  # wider import than the page the admin was looking at — measured, ?division=jr is 134 KB against
  # the whole deck's 3.12 MB.
  test "a filtered paper page is refused rather than widened to the whole deck" do
    %w[
      https://limitlesstcg.com/decks/284/results?variant=3
      https://limitlesstcg.com/decks/284?variant=3
      https://limitlesstcg.com/decks/284/?variant=3
      https://limitlesstcg.com/decks/284/results?variant=
      https://limitlesstcg.com/decks/284/results?time=1months
      https://limitlesstcg.com/decks/284/results?region=eu
      https://limitlesstcg.com/decks/284/results?division=jr
      https://limitlesstcg.com/decks/284/results?format=expanded
      https://limitlesstcg.com/decks/284/results?type=regional
    ].each do |text|
      message = refusal(text)

      assert_match "filtered", message, text
      assert_match "decks/284/results with no filter", message, text
    end
    assert_match "(region, division)", refusal("https://limitlesstcg.com/decks/284/results?region=eu&division=jr")
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
    # Present but blank is how a half-filled filter arrives, and it is as missing as absent.
    assert_match "rotation", refusal("https://play.limitlesstcg.com/decks/dragapult-ex?format=standard&rotation=&set=30C")
    assert_match "set", refusal("https://play.limitlesstcg.com/decks/dragapult-ex?format=standard&rotation=2026&set=")
  end

  # The run fetches by format, rotation and set alone, so anything else on the URL would be dropped.
  # A Pocket leaderboard is the measured case: refused on `game`, not asked for a rotation Pocket
  # does not have.
  test "an online URL carrying anything beyond its three parameters is refused, naming it" do
    message = refusal("https://play.limitlesstcg.com/decks/dragapult-ex?game=POCKET&format=standard&rotation=2026&set=PBL")
    assert_match "game", message

    message = refusal("https://play.limitlesstcg.com/decks/aegislash-b1-archaludon-b4?game=POCKET&format=standard&set=B4a")
    assert_match "game", message
    assert_no_match "rotation and set on Limitless", message
  end

  test "a repeated or malformed parameter is refused, not raised" do
    [
      "https://play.limitlesstcg.com/decks/dragapult-ex?format=standard&format=standard&rotation=2026&set=30C",
      "https://limitlesstcg.com/decks/284/results?x=%",
      "https://play.limitlesstcg.com/decks/dragapult-ex?format=standard&rotation=2026&set=%"
    ].each do |text|
      assert_match "limitlesstcg.com/tournaments/<id>", refusal(text), text
    end
  end

  # The screen prints every address without its scheme, so typing what it shows has to work.
  test "an address without a scheme is read as https" do
    assert_equal "284", parse("limitlesstcg.com/decks/284/results").deck_id
    assert_equal "578", parse("www.limitlesstcg.com/tournaments/578").tournament_id
    assert_equal "30C", parse("play.limitlesstcg.com/decks/dragapult-ex?format=standard&rotation=2026&set=30C").set
  end

  # The job fetches with ONLINE_FORMAT whatever the URL says, so another format would import the
  # Standard leaderboard under a URL that named a different one.
  test "an online URL in another format is refused" do
    message = refusal("https://play.limitlesstcg.com/decks/dragapult-ex?format=expanded&rotation=2026&set=30C")

    assert_match "expanded", message
    %w[Standard standardx].each do |format|
      assert_match format, refusal("https://play.limitlesstcg.com/decks/dragapult-ex?format=#{format}&rotation=2026&set=30C")
    end
  end

  test "anything that is not one of the three pages is refused, naming the three" do
    [
      "",
      "   ",
      "not a url at all",
      "ftp://limitlesstcg.com/decks/284/results",
      "https://example.com/decks/284/results",
      "https://limitlesstcg.com.evil.example/decks/284/results",
      "https://notlimitlesstcg.com/decks/284/results",
      "https://evil.limitlesstcg.com/decks/284/results",
      "ftp://limitlesstcg.com//decks/284/results",
      "javascript:alert(1)//limitlesstcg.com/decks/284/results",
      "https://limitlesstcg.com/decks/284/matchups",
      "https://limitlesstcg.com/decks/284/results/extra",
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

  # A percent-escape that decodes to invalid UTF-8 is a hand-made URL, never a copied one, and it
  # must still be a refusal on the form rather than an ArgumentError out of the query parser.
  test "a parameter that decodes to invalid UTF-8 is refused, not raised" do
    assert_match "limitlesstcg.com/tournaments/<id>",
      refusal("https://play.limitlesstcg.com/decks/dragapult-ex?format=standard&rotation=2026&set=%FF")
    assert_match "limitlesstcg.com/tournaments/<id>",
      refusal("https://limitlesstcg.com/decks/284/results?variant=%FF")
  end

  # Extraction and validation are two jobs. The controller's guards (SLUG_RE, SET_RE, …) already
  # refuse a value that cannot go into a URL, before anything is fetched, and they say why. The
  # parser hands such a value over rather than answering with a vaguer "not a Limitless URL".
  test "a value the controller's guards will refuse is still extracted" do
    parsed = parse("https://play.limitlesstcg.com/decks/Dragapult-EX?format=standard&rotation=26&set=30c")

    assert_equal [ "Dragapult-EX", "26", "30c" ], [ parsed.slug, parsed.rotation, parsed.set ]
  end
end
