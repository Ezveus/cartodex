require "test_helper"

class Tournaments::LimitlessEventResultsTest < ActiveSupport::TestCase
  BASE = "https://limitlesstcg.com".freeze

  def self.fixture(name) = File.read(Rails.root.join("test/fixtures/files/limitless/#{name}.html")).freeze

  MASTERS_577 = fixture("tournament_577_masters")
  SENIOR_577 = fixture("tournament_577_senior")
  JUNIOR_577 = fixture("tournament_577_junior")
  MASTERS_563 = fixture("tournament_563_masters")
  # Cape Town's Senior page: HTTP 200, "? Players", and no table at all. The measured reason a
  # suffix page may not be fatal.
  SENIOR_563 = fixture("tournament_563_senior")

  EVENT_577 = {
    "#{BASE}/tournaments/577" => MASTERS_577,
    "#{BASE}/tournaments/577/SR" => SENIOR_577,
    "#{BASE}/tournaments/577/JR" => JUNIOR_577
  }.freeze

  setup do
    @original_http_fetcher_call = HttpFetcher.method(:call)
    @http_calls = []
    stub_pages(EVENT_577)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  # One real-world event is three pages. They have to come back as one event — a name and a date
  # per division would catalogue Regional Baltimore three times over, which is the mistake
  # Tournaments::LimitlessResults already exists to avoid on the other source.
  test "reads the three division pages as one event" do
    rows = Tournaments::LimitlessEventResults.call(577)

    assert_equal [ "#{BASE}/tournaments/577", "#{BASE}/tournaments/577/SR", "#{BASE}/tournaments/577/JR" ],
      @http_calls
    assert_equal 24, rows.size
    assert_equal [ "Regional Baltimore, MD" ], rows.map(&:event_name).uniq
    assert_equal [ Date.new(2026, 9, 19) ], rows.map(&:event_date).uniq
    assert_equal({ "masters" => 8, "senior" => 8, "junior" => 8 }, rows.map(&:division).tally)
    assert_equal [ nil, "SR", "JR" ], rows.map(&:division_suffix).uniq
  end

  # The attendance on a division page is that division's field, not the event's — measured on 563,
  # where Masters states 88 and both other divisions state "?". Read once and repeated, all three
  # of tournaments.{masters,senior,junior}_participant_count get the Masters figure, and
  # TournamentStanding#placement_within_division_field then measures a Junior's 200th place
  # against a field of 3122.
  test "reads each division's own field size rather than one number three times" do
    rows = Tournaments::LimitlessEventResults.call(577)

    assert_equal({ "masters" => [ 3122 ], "senior" => [ 364 ], "junior" => [ 233 ] },
      rows.group_by(&:division).transform_values { |division| division.map(&:attendance).uniq })
  end

  # "? Players" is a real value on a real page (fixture tournament_563_senior.html). Read as an
  # integer it is 0, and a field size of 0 makes every placement in that division invalid.
  test "reads an unstated field size as nil, never as zero" do
    stub_pages("#{BASE}/tournaments/563" => MASTERS_563.sub("88", "?"))

    rows = Tournaments::LimitlessEventResults.call(563)

    assert_equal 10, rows.size
    assert_equal [ nil ], rows.map(&:attendance).uniq
  end

  # Limitless renames a deck as the metagame settles and files variants under one base id, so the
  # href is the identity and the display name is not. 284, 284/3 and 284/9 are Dragapult,
  # Dragapult Dusknoir and Dragapult Blaziken: keyed on the base id alone they are one deck, and
  # one mapping would then file three archetypes' rows under whichever was confirmed first.
  test "tells a base deck apart from its variant" do
    rows = Tournaments::LimitlessEventResults.call(577)

    assert_equal "284", row_at(rows, "senior", 1).archetype_key
    assert_equal "284/3", row_at(rows, "junior", 3).archetype_key
    assert_equal "284/9", row_at(rows, "junior", 1).archetype_key
    # The same three rows read off data-deck instead would answer with display names, which is
    # what makes this assertion the one that fails if the key moves to that attribute.
    assert_equal [ "Dragapult", "Dragapult Dusknoir", "Dragapult Blaziken" ],
      [ row_at(rows, "senior", 1), row_at(rows, "junior", 3), row_at(rows, "junior", 1) ].map(&:archetype_label)
  end

  # data-deck is HTML-escaped on the page ("Marnie&#039;s Grimmsnarl"). It reaches the mapping
  # screen as the label an admin recognises the deck by, and an escaped one is not that.
  test "unescapes the display name the label carries" do
    rows = Tournaments::LimitlessEventResults.call(577)

    assert_equal "Marnie's Grimmsnarl", row_at(rows, "masters", 351).archetype_label
  end

  # The format is *stated*, and it is StandardPool#name byte for byte. Anchoring through
  # StandardPool.at(date) instead reads legal_on, so an event held in the fortnight after a set
  # ships is anchored to the pool the source says it was not played under.
  test "reports the format as the pool code the page publishes" do
    assert_equal [ "TEF-PBL" ], Tournaments::LimitlessEventResults.call(577).map(&:format).uniq

    stub_pages("#{BASE}/tournaments/563" => MASTERS_563)
    assert_equal [ "SVI-ASC" ], Tournaments::LimitlessEventResults.call(563).map(&:format).uniq
  end

  # A row is a placement whether or not its deck cell links anywhere. Dropped, the sheet loses a
  # player who really finished there; guessed, it gains an archetype nobody published.
  test "keeps a row whose deck cell links nowhere, with no archetype key" do
    stub_pages(EVENT_577.merge("#{BASE}/tournaments/577" => MASTERS_577.sub('<a href="/decks/339">', "<a>")))

    row = row_at(Tournaments::LimitlessEventResults.call(577), "masters", 1)

    assert_nil row.archetype_key
    assert_equal "Basic Box", row.archetype_label
    assert_equal "Dylan Kasturi", row.player_name
  end

  # A scraped href is attacker-controlled text, and the key it yields becomes a form value and a
  # Hash key on the mapping screen. Only /decks/<digits> is a reference; anything else is none.
  test "reads no key at all out of an href that is not a deck reference" do
    stub_pages(EVENT_577.merge(
      "#{BASE}/tournaments/577" => MASTERS_577.sub('href="/decks/339"', 'href="javascript:alert(1)"')
    ))

    assert_nil row_at(Tournaments::LimitlessEventResults.call(577), "masters", 1).archetype_key
  end

  # The case above proves the regex is consulted; it does not prove the regex is *anchored*, since
  # "javascript:alert(1)" holds no /decks/<digits> anywhere and fails to match either way. These do
  # hold one, wrapped in something else — which is what an anchor is for, and what a mutation
  # dropping \A and \z from DECK_HREF_RE otherwise survives untouched.
  test "reads no key out of an href that merely contains a deck reference" do
    [ "/evil/decks/339", "/decks/339/extra", "/decks/339x", "/decks/339?variant=1&next=/evil" ].each do |href|
      stub_pages(EVENT_577.merge(
        "#{BASE}/tournaments/577" => MASTERS_577.sub('href="/decks/339"', %(href="#{href}"))
      ))

      assert_nil row_at(Tournaments::LimitlessEventResults.call(577), "masters", 1).archetype_key,
        "#{href} is not a deck reference and must yield no key"
    end
  end

  # The synthetic key the bulk decklist store answers on. It stays in `list_url` so the importer's
  # existing `row.list_url.blank?` gate keeps working unchanged.
  test "addresses a row's list by its division and rank" do
    rows = Tournaments::LimitlessEventResults.call(577)

    assert_equal "577/masters/1", row_at(rows, "masters", 1).list_url
    assert_equal "577/junior/3", row_at(rows, "junior", 3).list_url
    assert_equal 127, row_at(rows, "masters", 127).placement
  end

  test "leaves the list key empty for a row that published no list" do
    stub_pages("#{BASE}/tournaments/563" => MASTERS_563)

    rows = Tournaments::LimitlessEventResults.call(563)

    assert_nil row_at(rows, "masters", 3).list_url
    assert_equal "563/masters/6", row_at(rows, "masters", 6).list_url
  end

  # Half of a rule that needs two tests. The base page holding no table means the event does not
  # exist or the layout moved — both are the whole run's problem, and both are invisible if the
  # suffix pages happen to answer.
  test "refuses a base page that holds no standings table" do
    stub_pages(EVENT_577.merge("#{BASE}/tournaments/577" => "<html><body><p>Nothing</p></body></html>"))

    error = assert_raises(Tournaments::LimitlessEventResults::ParseError) do
      Tournaments::LimitlessEventResults.call(577)
    end

    assert_match(%r{/tournaments/577(?!/)}, error.message)
  end

  # The other half, and it is not the same rule: 563's SR and JR pages answer 200 with "? Players"
  # and no table. Fatal, every small event is permanently out of reach.
  test "treats a suffix page holding no table as an empty division" do
    stub_pages(EVENT_577.merge("#{BASE}/tournaments/577/SR" => SENIOR_563))

    rows = Tournaments::LimitlessEventResults.call(577)

    assert_equal({ "masters" => 8, "junior" => 8 }, rows.map(&:division).tally)
  end

  test "treats a suffix page that 404s as an empty division" do
    stub_pages(EVENT_577.except("#{BASE}/tournaments/577/SR"))

    rows = Tournaments::LimitlessEventResults.call(577)

    assert_equal({ "masters" => 8, "junior" => 8 }, rows.map(&:division).tally)
  end

  # The id is interpolated into six URLs. Narrowed in the constructor, the way
  # Tournaments::OnlineResults narrows all four of its own inputs — refused before anything leaves
  # this machine, never sanitised afterwards.
  test "refuses a tournament id that is not a number, before anything is fetched" do
    assert_raises(ArgumentError) { Tournaments::LimitlessEventResults.call("577/../563") }
    assert_raises(ArgumentError) { Tournaments::LimitlessEventResults.call("") }

    assert_empty @http_calls
  end

  # The failure a run's own pacing exists to avoid must not be readable as an empty division. Left
  # flattened onto the same nil as a 404, a throttled /JR took the eight Junior rows out of the plan
  # with no refusal raised anywhere, the preview showed a field nothing marked as amputated, and the
  # Import declared itself completed.
  test "refuses a division page the far side declined to answer, rather than emptying it" do
    stub_statuses("#{BASE}/tournaments/577/SR" => 429)

    error = assert_raises(HttpFetcher::FetchError) { Tournaments::LimitlessEventResults.call(577) }

    assert_match(/429/, error.message)
    assert_match(%r{/tournaments/577/SR}, error.message)
  end

  # And the same on the base page, where the old flattening was merely misleading rather than
  # silent: it answered "the event may not exist, or the layout changed" about an id that is
  # perfectly correct, and sent the admin to check it.
  test "refuses the base page the far side declined to answer, naming the failure" do
    stub_statuses("#{BASE}/tournaments/577" => 503)

    error = assert_raises(HttpFetcher::FetchError) { Tournaments::LimitlessEventResults.call(577) }

    assert_match(/503/, error.message)
  end

  private

  def row_at(rows, division, placement)
    rows.find { |row| row.division == division && row.placement == placement }
  end

  # The pages of 577, with a status in the way of some of them. Not `stub_pages` minus a URL: that
  # one raises a 404, which is exactly the failure this source is *allowed* to read as an empty
  # division.
  def stub_statuses(statuses)
    pages = EVENT_577
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |url|
      calls << url
      status = statuses[url]
      raise HttpFetcher::FetchError.new("HTTP #{status} for #{url}", status: status) if status

      pages.fetch(url)
    }
  end

  def stub_pages(pages)
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |url|
      calls << url
      # With the status, the way HttpFetcher raises it: a 404 is what this source is allowed to
      # read as an empty division, and a stub that dropped the status would make every page a
      # division nobody entered.
      unless pages.key?(url)
        raise HttpFetcher::FetchError.new("HTTP 404 for #{url}", status: 404)
      end


      pages.fetch(url)
    }
  end
end
