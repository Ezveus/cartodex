require "test_helper"

class Admin::StandingsImportsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  include Devise::Test::IntegrationHelpers

  RESULTS_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_deck_results.html")).freeze
  ONLINE_RESULTS_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_online_results.html")).freeze
  ONLINE_DECKLIST_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_online_decklist.html")).freeze
  # The set the fixture's pool is named by: standard_pools(:twm_por) ends at POR, and exactly one
  # pool does — which is the whole precondition an online run is anchored on.
  ONLINE_SET = "POR".freeze

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
    @archetype = archetypes(:standings_marker)

    # There is no mocking library in this suite: the singleton is replaced and restored by hand,
    # the way every other scraping test here does it. Recording the URLs is what lets a test
    # assert that *no* fetch happened, which is the whole point of the deck-id guard.
    @original_http_fetcher_call = HttpFetcher.method(:call)
    @http_calls = []
    stub_http(RESULTS_HTML)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
    Cards::Fetcher.define_singleton_method(:call, @cards_fetcher_restore) if @cards_fetcher_restore
  end

  # This screen writes into the public catalog with no member-facing confirmation anywhere, so the
  # panel's own gate is the only thing standing between an ordinary account and 300 public rows.
  test "a member who is not an admin cannot reach the screen" do
    sign_in users(:two)

    get new_admin_standings_import_path

    assert_redirected_to root_path
    assert_equal "Not authorized.", flash[:alert]
  end

  test "the form renders with an archetype to pick" do
    get new_admin_standings_import_path

    assert_response :success
    assert_select "input#deck_id"
    assert_select "select#archetype_id option", text: @archetype.name
    # Nothing has been fetched: opening the form must not talk to Limitless.
    assert_empty @http_calls
  end

  # The tier is guessed from the event name and nothing downstream re-checks it: filed as the
  # schema default, a World Championship becomes a Regional and Tournament::CP_REFERENCE then
  # offers a claimant 350 championship points instead of 600. The preview is the only place a
  # wrong guess can be seen before it is public, so it has to print the derived value.
  test "the preview names the tier it derived for each event" do
    get preview_admin_standings_imports_path, params: { deck_id: "280", archetype_id: @archetype.id }

    assert_response :success
    assert_equal [ "https://limitlesstcg.com/decks/280/results" ], @http_calls
    # "NAIC 2026, New Orleans" contains none of these words itself, so the label can only come
    # from TIER_PATTERNS having matched.
    assert_match "International Championship", response.body
  end

  # The division is derived from an href suffix and is part of the skip key, so a wrong one writes
  # a second public row for the same player at the same event — which the UNIQUE index cannot see
  # and a corrected re-run cannot fix. Printing it per row is the only check there is.
  test "the preview names the division it derived for each row" do
    get preview_admin_standings_imports_path, params: { deck_id: "280", archetype_id: @archetype.id }

    assert_response :success
    assert_select "[data-label=Division]", text: "senior"
    assert_select "[data-label=Division]", text: "masters"
  end

  # The deck id is interpolated straight into the URL this fetches. Refusing it *before* the fetch
  # is the whole guarantee — a refusal that happened after one would have already made the request.
  test "a deck id that is not a number is refused before anything is fetched" do
    get preview_admin_standings_imports_path,
      params: { deck_id: "280/../../evil", archetype_id: @archetype.id }

    assert_response :success
    assert_empty @http_calls, "no fetch may happen for a deck id the guard refuses"
    assert_match "must be a number", response.body
  end

  # Limitless answering 429, or moving its layout, is one bad afternoon rather than a bug here —
  # and the admin needs the form back with the reason, not a 500 page with no way on.
  test "a scrape failure re-renders the form with the reason" do
    HttpFetcher.define_singleton_method(:call) { |_url| raise HttpFetcher::FetchError, "HTTP 429 for limitlesstcg.com" }

    get preview_admin_standings_imports_path, params: { deck_id: "280", archetype_id: @archetype.id }

    assert_response :success
    assert_match "Could not read Limitless deck 280", response.body
    assert_match "HTTP 429", response.body
    assert_select "input#deck_id"
  end

  # The Import row is the run's receipt: it carries the label the admin table prints and, once the
  # job has run, the standing ids "Undo this run" reads back. Created here rather than in the job
  # so that a queue that never drains still leaves a visible pending row.
  test "confirming creates the import row and enqueues the job with what the admin saw" do
    assert_difference -> { Import.count }, 1 do
      post admin_standings_imports_path, params: {
        deck_id: "280", archetype_id: @archetype.id,
        event_filters: "NAIC\nWorld Championships", limit_per_event: "4", expected_row_count: "5"
      }
    end

    import = Import.last
    assert_equal @admin, import.user
    assert_equal "limitless_standings", import.kind
    assert_equal "Standings Marker — Limitless deck 280", import.label

    assert_enqueued_with(job: Tournaments::LimitlessImportJob, args: [
      import.id, @admin.id,
      {
        "deck_id" => "280",
        "archetype_id" => @archetype.id,
        "event_filters" => [ "NAIC", "World Championships" ],
        "limit_per_event" => 4,
        "expected_row_count" => 5
      }
    ])

    assert_redirected_to admin_imports_path
  end

  # The confirm form is what the POST is built from, so it has to carry back exactly what the plan
  # was built from — and the count the admin actually looked at, which the job compares its refetch
  # against. A hand-built params hash in the test below could only ever confirm the controller;
  # this is the half that says the rendered form agrees with it.
  test "the confirm form carries the previewed parameters back" do
    get preview_admin_standings_imports_path,
      params: { deck_id: "280", archetype_id: @archetype.id, event_filters: "NAIC", limit_per_event: "1" }

    assert_response :success
    assert_select "form.standings-import-confirm" do
      assert_select "input[name=deck_id][value=280]"
      assert_select "input[name=archetype_id][value=?]", @archetype.id.to_s
      assert_select "input[name=event_filters][value=NAIC]"
      assert_select "input[name=limit_per_event][value=1]"
      # Three, not one: the cap is per age division, so NAIC keeps its best Masters, its best
      # Senior and its best Junior. A cap applied across the whole event would have kept ten
      # Masters rows and dropped the single Junior one, which is the row hardest to find anywhere
      # else.
      assert_select "input[name=expected_row_count][value=3]"
    end
    # A hidden field must not steal the id of the input the admin types into.
    assert_select "input#deck_id", 1
  end

  # A plan with nothing to write must offer no button at all. Rendering a disabled one, or one
  # that submits a run of zero rows, teaches an admin that the button sometimes does nothing —
  # which is the wrong thing to learn about a control that writes to a public catalog.
  test "no confirm button when every row is blocked" do
    get preview_admin_standings_imports_path,
      params: { deck_id: "280", archetype_id: @archetype.id, event_filters: "Antwerp" }

    assert_response :success
    assert_select ".standings-import-event--blocked"
    assert_select "form.standings-import-confirm", false
  end

  # The ceiling exists because a whole results page is 1569 rows and thousands of requests to
  # somebody else's site. Over it the refusal replaces the button rather than sitting beside it.
  test "over the row ceiling the plan refuses instead of offering a button" do
    with_max_rows(2) do
      get preview_admin_standings_imports_path, params: { deck_id: "280", archetype_id: @archetype.id }
    end

    assert_response :success
    assert_select ".standings-import-refusal"
    assert_match "over the 2-row ceiling", response.body
    assert_select "form.standings-import-confirm", false
  end

  # Same class of refusal as the preview's, and it has to be repeated: the confirm form carries
  # these values back through the browser, which makes them ordinary user input again.
  test "confirming with a non-numeric deck id enqueues nothing" do
    assert_no_difference -> { Import.count } do
      assert_no_enqueued_jobs do
        post admin_standings_imports_path, params: {
          deck_id: "not-a-number", archetype_id: @archetype.id, expected_row_count: "5"
        }
      end
    end

    assert_redirected_to new_admin_standings_import_path
    assert_match "must be a number", flash[:alert]
  end

  # The one test that runs the whole thing: this screen and the job behind it were written against
  # a written-down contract, and a Hash key spelled differently on either side would leave every
  # real import failing while twelve controller tests and nine job tests stayed green.
  test "the job the form enqueues actually imports the plan the preview showed" do
    stub_pages
    stub_cards_fetcher

    perform_enqueued_jobs do
      post admin_standings_imports_path, params: {
        deck_id: "280", archetype_id: @archetype.id, event_filters: "World Championships 2026",
        limit_per_event: "", expected_row_count: "2"
      }
    end

    import = Import.limitless_standings_imports.sole
    assert_equal "completed", import.status, import.error_message
    assert_equal 2, import.created_standing_ids.size

    worlds = Tournament.find_by(name_normalized: "world championships 2026")
    assert_equal "worlds", worlds.tier
    assert_equal @admin, worlds.created_by
    assert_equal [ "James Cox", "Tomi Markkula" ], worlds.standings.pluck(:player_name).sort
    assert_equal [ @archetype ], worlds.standings.map(&:archetype).uniq
    # The row Limitless publishes with no decklist is still a standing; the other one gets a list.
    assert_equal [ nil, 60 ], worlds.standings.map { |s| s.deck&.deck_cards&.sum(:quantity) }.sort_by(&:to_i)
  end

  # --- the online source -------------------------------------------------------------------
  #
  # play.limitlesstcg.com's best finishes: a slug, a rotation and a set where the paper source has
  # one number, all three interpolated into the URL this fetches.

  test "an online preview renders the plan and carries its own parameters into the confirm form" do
    stub_http(ONLINE_RESULTS_HTML)

    get preview_admin_standings_imports_path, params: online_params

    assert_response :success
    assert_equal(
      [ "https://play.limitlesstcg.com/decks/raging-bolt-ogerpon?format=standard&rotation=2026&set=POR" ],
      @http_calls
    )
    assert_match "Pumpkaweekly", response.body
    # Online play has no age divisions, and "open" is the fourth value that says so rather than
    # filing every online result as a Masters one.
    assert_select "[data-label=Division]", text: "open"
    assert_select "form.standings-import-confirm" do
      assert_select "input[name=source][value=online]"
      assert_select "input[name=slug][value=raging-bolt-ogerpon]"
      assert_select "input[name=rotation][value=2026]"
      assert_select "input[name=set][value=?]", ONLINE_SET
      assert_select "input[name=expected_row_count][value=6]"
    end
  end

  # The same guarantee the deck id has, three times over: each of these is interpolated into the
  # URL, so each is refused while there is still a form to send the admin back to. Tournaments::
  # OnlineResults validates them too and raises ArgumentError — which is a 500 by the time it
  # reaches a browser, and a fetch has been made by then anyway.
  test "a slug that is not a plain identifier is refused before anything is fetched" do
    get preview_admin_standings_imports_path, params: online_params(slug: "raging-bolt/../../evil")

    assert_response :success
    assert_empty @http_calls, "no fetch may happen for a slug the guard refuses"
    assert_match "slug must be lowercase letters", response.body
  end

  test "a rotation that is not a year is refused before anything is fetched" do
    get preview_admin_standings_imports_path, params: online_params(rotation: "2026&format=evil")

    assert_response :success
    assert_empty @http_calls, "no fetch may happen for a rotation the guard refuses"
    assert_match "rotation must be a four-digit year", response.body
  end

  test "a set that is not a set code is refused before anything is fetched" do
    get preview_admin_standings_imports_path, params: online_params(set: "por&x=1")

    assert_response :success
    assert_empty @http_calls, "no fetch may happen for a set the guard refuses"
    assert_match "set must be a short uppercase set code", response.body
  end

  # Tournaments::OnlineResults::ParseError is a *different constant* from the paper source's, and a
  # source switch that rescued only the old one would answer a slug nobody has published — or a
  # rotation and set pair that names an empty leaderboard — with a 500.
  test "an online parse failure re-renders the form with the reason rather than 500ing" do
    stub_http("<html><body><p>Nothing here.</p></body></html>")

    get preview_admin_standings_imports_path, params: online_params

    assert_response :success
    assert_match "Could not read the online raging-bolt-ogerpon leaderboard (2026 POR)", response.body
    assert_match "no results table", response.body
    assert_select "input#slug"
  end

  # A pool is its *pair* of bounds, so two of them may legitimately end at one set — a rotation
  # landing between two set releases moves the first bound and leaves the last alone. Picking one
  # would look right up until it silently was not, so the run is blocked and both are named.
  test "two Standard pools ending at the set block the run and name both" do
    StandardPool.create!(first_card_set: card_sets(:asc), last_card_set: card_sets(:por),
      regulation_marks: %w[H I J], released_on: Date.new(2026, 1, 16), legal_on: Date.new(2026, 1, 30))

    get preview_admin_standings_imports_path, params: online_params

    assert_response :success
    assert_empty @http_calls, "a run that cannot be anchored must not fetch anything"
    assert_match "2 Standard pools end at POR", response.body
    assert_match "TWM-POR", response.body
    assert_match "ASC-POR", response.body
    assert_select "form.standings-import-confirm", false
  end

  test "a set that names no Standard pool is refused with a reason" do
    get preview_admin_standings_imports_path, params: online_params(set: "PBL")

    assert_response :success
    assert_empty @http_calls, "a run that cannot be anchored must not fetch anything"
    assert_match "No Standard pool ends at PBL", response.body
  end

  test "confirming an online run enqueues the job with the source it was previewed from" do
    assert_difference -> { Import.count }, 1 do
      post admin_standings_imports_path, params: online_params(expected_row_count: "6")
    end

    import = Import.last
    # The same kind as a paper run, deliberately: Tournaments::StandingsImportUndo and
    # Admin::ImportsController#undo both gate on this literal, so a kind of its own would produce
    # runs that look identical in the admin table and silently cannot be undone.
    assert_equal "limitless_standings", import.kind
    assert_equal "Standings Marker — online raging-bolt-ogerpon (2026 POR)", import.label

    assert_enqueued_with(job: Tournaments::LimitlessImportJob, args: [
      import.id, @admin.id,
      {
        "archetype_id" => @archetype.id,
        "event_filters" => [],
        "limit_per_event" => nil,
        "expected_row_count" => 6,
        "source" => "online",
        "slug" => "raging-bolt-ogerpon",
        "rotation" => "2026",
        "set" => ONLINE_SET
      }
    ])
  end

  # The online twin of the end-to-end test above, and it exists for the same reason: a Hash key
  # spelled differently on either side of this screen would leave every real online import failing
  # while every other test here stayed green.
  test "the job an online confirmation enqueues actually imports the plan the preview showed" do
    stub_online_pages
    stub_cards_fetcher

    perform_enqueued_jobs do
      post admin_standings_imports_path, params: online_params(expected_row_count: "6")
    end

    import = Import.limitless_standings_imports.sole
    assert_equal "completed", import.status, import.error_message
    # Six leaderboard rows, four rows written: jrobrueda holds three of them and one list, and one
    # player's registration habit must not weigh their deck three times in the sample.
    assert_equal 4, import.created_standing_ids.size

    standings = TournamentStanding.where(id: import.created_standing_ids)
    assert_equal [ "open" ], standings.map(&:division).uniq
    # A list on every row, which is also what says the *online* decklist service ran: the paper one
    # reads a different page shape and would have refused all four.
    assert_equal [ 60 ], standings.map { |standing| standing.deck.deck_cards.sum(:quantity) }.uniq
    events = Tournament.where(id: standings.map(&:tournament_id))
    assert_equal [ true ], events.map(&:online).uniq
    assert_equal [ standard_pools(:twm_por) ], events.map(&:standard_pool).uniq
  end

  private

  def online_params(**overrides)
    { source: "online", slug: "raging-bolt-ogerpon", rotation: "2026", set: ONLINE_SET,
      archetype_id: @archetype.id }.merge(overrides)
  end

  # The leaderboard for the leaderboard URL, a decklist for anything else.
  def stub_online_pages
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |url|
      calls << url
      url.include?("/decks/") ? ONLINE_RESULTS_HTML : ONLINE_DECKLIST_HTML
    }
  end

  # The ceiling is a keyword with a constant default precisely so a test can prove the refusal
  # with two rows instead of a 300-row HTML fixture. Restored in an ensure: it is a real constant
  # and every later test in this process would otherwise inherit it.
  def with_max_rows(limit)
    plan = Tournaments::StandingsImportPlan
    original = plan::DEFAULT_MAX_ROWS
    plan.send(:remove_const, :DEFAULT_MAX_ROWS)
    plan.const_set(:DEFAULT_MAX_ROWS, limit)
    yield
  ensure
    plan.send(:remove_const, :DEFAULT_MAX_ROWS)
    plan.const_set(:DEFAULT_MAX_ROWS, original)
  end

  def stub_http(html)
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |url|
      calls << url
      html
    }
  end

  # The results page for the results URL, a decklist for anything else — the shape the job really
  # sees, rather than one page answering every request.
  def stub_pages
    decklist = File.read(Rails.root.join("test/fixtures/files/limitless_decklist.html"))
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |url|
      calls << url
      url.include?("/results") ? RESULTS_HTML : decklist
    }
  end

  def stub_cards_fetcher
    original = Cards::Fetcher.method(:call)
    Cards::Fetcher.define_singleton_method(:call) { |url|
      segments = URI.parse(url).path.split("/")
      Card.find_or_create_by!(set_name: segments[2], set_number: segments[3]) do |card|
        card.name = "Card #{segments[2]} #{segments[3]}"
        card.card_type = "Trainer"
        card.rarity = "Common"
      end
    }
    @cards_fetcher_restore = original
  end
end
