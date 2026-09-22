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
    Tournaments::EventDecklists.define_method(:call, @decklists_restore) if @decklists_restore
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

  # --- one whole event ----------------------------------------------------------------------
  #
  # limitlesstcg.com/tournaments/<id>: three division pages of one real event. Its rows do not
  # share an archetype — 15 distinct decks over the 24 fixture rows, 45 over 575 on the measured
  # event — so the screen gains a line per distinct deck reference, and the run carries no
  # archetype of its own at all.

  test "a tournament id that is not a number is refused before anything is fetched" do
    get preview_admin_standings_imports_path, params: event_params(tournament_id: "577/../../evil")

    assert_response :success
    assert_empty @http_calls, "no fetch may happen for a tournament id the guard refuses"
    assert_match "must be a number", response.body
  end

  # The claim this whole source rests on. The event's lists come off one bulk page per division,
  # and the preview asks for one list per *unmapped reference* — 13 here, where the rows are 24
  # and the references 15. Counting the calls rather than their `uniq` is the point: an
  # implementation that fetched one per row and grouped afterwards satisfies `uniq.size` exactly
  # as well, and on the real event that is 575 fetches instead of 45.
  test "the preview asks for one list per distinct unmapped deck reference, never one per row" do
    stub_event_pages
    keys = record_decklist_keys

    get preview_admin_standings_imports_path, params: event_params

    assert_response :success
    assert_equal EVENT_UNMAPPED_REFERENCES, keys.size
    assert_equal keys.uniq, keys
  end

  # A deck an admin has already arbitrated is never proposed for again, which is what makes the
  # second event cheap: only the decks nobody has seen cost a list.
  test "a reference already in the store is shown as confirmed and costs no list" do
    stub_event_pages
    keys = record_decklist_keys

    get preview_admin_standings_imports_path, params: event_params

    # The representative rows of the two mapped references: 284 (Dragapult) and 284/3.
    assert_not_includes keys, "577/senior/1"
    assert_not_includes keys, "577/masters/127"
    assert_select "[data-label=Proposal]", text: /confirmed/i, count: 2
    assert_select "select[name=?] option[selected][value=?]",
      "mappings[284][archetype_id]", archetypes(:ogerpon).id.to_s
  end

  test "the preview renders one line per distinct deck reference, carrying the label Limitless published" do
    stub_event_pages
    record_decklist_keys

    get preview_admin_standings_imports_path, params: event_params

    assert_select ".standings-import-mappings select", EVENT_REFERENCES
    assert_select "[data-label=Deck]", text: /Basic Box/
    assert_select "select[name=?]", "mappings[339][archetype_id]"
    # The label travels with the selection: limitless_archetype_mappings.label is NOT NULL and
    # #create never fetches, so nothing else could tell it what deck 339 is called.
    assert_select "input[name=?][value=?]", "mappings[339][label]", "Basic Box"
    # Nothing is decided here: the archetype the list resolves to is a proposal with a reason.
    assert_select "[data-label=Proposal]", text: /name says nothing/, minimum: 1
  end

  test "a decided proposal arrives pre-selected in its own line" do
    stub_event_pages
    record_decklist_keys
    proposed = archetypes(:standings_marker)

    with_proposal(archetype: proposed, verdict: :decided) do
      get preview_admin_standings_imports_path, params: event_params
    end

    assert_select "select[name=?]", "mappings[339][archetype_id]" do
      assert_select "option[selected][value=?]", proposed.id.to_s
    end
  end

  # One event, its own key, the pool its page publishes, and a ceiling of its own: DEFAULT_MAX_ROWS
  # is 300 to stop an archetype-history run walking 176 events, and one event is a bounded thing
  # the admin has just seen the size of.
  test "the plan is built for one event, anchored to the pool the page publishes, at the 1000-row ceiling" do
    pool = tef_pbl_pool
    stub_event_pages
    record_decklist_keys

    options = capture_plan_options do
      get preview_admin_standings_imports_path, params: event_params
    end

    assert_response :success
    assert_equal "limitless-event:#{EVENT_ID}", options[:event_key]
    assert_equal 1000, options[:max_rows]
    assert_equal pool, options[:standard_pool]
    assert_not options[:online], "an event sheet is paper, and partitions with the paper half"
  end

  # Tournaments::LimitlessEventResults::ParseError is a *third* constant beside the two the rescue
  # already names, and an id nobody has published reaches it. Unrescued that is a 500 on the one
  # screen whose whole job is to be looked at before anything is written.
  test "an event page with no standings table re-renders the form with the reason rather than 500ing" do
    stub_http("<html><body><p>Nothing here.</p></body></html>")

    get preview_admin_standings_imports_path, params: event_params

    assert_response :success
    assert_match "Could not read Limitless tournament #{EVENT_ID}", response.body
    assert_match "no standings table", response.body
    assert_select "input#tournament_id"
  end

  # The bulk pages publish a list for some rows and not others — 4 of 8 Masters here, 6 of 10 on
  # the measured Cape Town event — so a reference whose representative published nothing is
  # ordinary. It costs its own line and not the other 14 proposals.
  test "a list that cannot be read costs its own line and not the preview" do
    stub_event_pages

    get preview_admin_standings_imports_path, params: event_params

    assert_response :success
    assert_select ".standings-import-mappings select", EVENT_REFERENCES
    assert_match "publishes no list ranked", response.body
  end

  # The two sources that declare one archetype for the whole run keep the guard; this one has no
  # archetype at all, so relaxing it for everybody would take #create into import_label's
  # @archetype.name and 500 there. Every older test in this file passes archetype_id, so nothing
  # but these two would notice.
  test "a paper preview with no archetype is still refused" do
    get preview_admin_standings_imports_path, params: { deck_id: "280" }

    assert_response :success
    assert_empty @http_calls, "no fetch may happen for a run that has no archetype to write"
    assert_match "Pick the archetype", response.body
  end

  test "a paper confirmation with no archetype enqueues nothing" do
    assert_no_difference -> { Import.count } do
      assert_no_enqueued_jobs do
        post admin_standings_imports_path, params: { deck_id: "280", expected_row_count: "5" }
      end
    end

    assert_redirected_to new_admin_standings_import_path
    assert_match "archetype no longer exists", flash[:alert]
  end

  test "the confirm form carries the event and its mapping selections back" do
    stub_event_pages
    record_decklist_keys

    get preview_admin_standings_imports_path, params: event_params

    assert_select "form.standings-import-confirm" do
      assert_select "input[name=source][value=event]"
      assert_select "input[name=tournament_id][value=?]", EVENT_ID
      assert_select "select[name=?]", "mappings[339][archetype_id]"
    end
    # A hidden field must not steal the id of the input the admin types into.
    assert_select "input#tournament_id", 1
  end

  # What the admin confirmed is stored before the run is enqueued, because the plan reads the store
  # and nothing about archetypes travels in the job's arguments.
  test "confirming persists the confirmed mappings and enqueues the run" do
    assert_difference -> { LimitlessArchetypeMapping.count }, 1 do
      post admin_standings_imports_path, params: event_params(mappings: {
        "339" => { "label" => "Basic Box", "archetype_id" => archetypes(:standings_marker).id.to_s },
        "329" => { "label" => "Marnie's Grimmsnarl", "archetype_id" => "" },
        "284" => { "label" => "Dragapult", "archetype_id" => archetypes(:budew_ogerpon).id.to_s }
      })
    end

    mapping = LimitlessArchetypeMapping.find_by(limitless_deck_id: 339, limitless_variant: nil)
    assert_equal archetypes(:standings_marker), mapping.archetype
    assert_equal "Basic Box", mapping.label
    # A reference left blank is a refusal, not a guess: nothing is stored, and the run blocks its
    # rows naming the deck.
    assert_nil LimitlessArchetypeMapping.find_by(limitless_deck_id: 329)
    # A correction to a reference already confirmed is an update, never a second row — which is
    # what the partial UNIQUE index on (deck_id) WHERE variant IS NULL is there to guarantee.
    assert_equal archetypes(:budew_ogerpon), limitless_archetype_mappings(:dragapult).reload.archetype

    import = Import.last
    assert_equal "limitless_standings", import.kind
    assert_equal "Limitless tournament #{EVENT_ID}", import.label
    assert_enqueued_with(job: Tournaments::LimitlessImportJob, args: [
      import.id, @admin.id,
      { "source" => "event", "tournament_id" => EVENT_ID, "event_filters" => [], "limit_per_event" => nil }
    ])
    assert_redirected_to admin_imports_path
  end

  # The selections come back through the browser, which makes them ordinary user input again —
  # and an archetype can be deleted between the preview and the click.
  test "an archetype that no longer exists is dropped from the mappings rather than 500ing" do
    vanished = Archetype.maximum(:id) + 1

    assert_no_difference -> { LimitlessArchetypeMapping.count } do
      post admin_standings_imports_path, params: event_params(mappings: {
        "339" => { "label" => "Basic Box", "archetype_id" => vanished.to_s }
      })
    end

    assert_redirected_to admin_imports_path
    assert_enqueued_jobs 1
  end

  # The end-to-end twin of the two above it, and it exists for their reason: a Hash key spelled
  # differently on either side of this screen would leave every real event import failing while
  # every other test here stayed green.
  test "the job an event confirmation enqueues imports the rows whose deck is mapped" do
    pool = tef_pbl_pool
    stub_event_pages
    stub_cards_fetcher

    with_no_pause do
      perform_enqueued_jobs do
        post admin_standings_imports_path, params: event_params
      end
    end

    import = Import.limitless_standings_imports.sole
    assert_equal "completed", import.status, import.error_message

    event = Tournament.find_by(external_key: "limitless-event:#{EVENT_ID}")
    assert_equal "Regional Baltimore, MD", event.name
    assert_equal "regional", event.tier
    assert_equal pool, event.standard_pool
    # One field size per division, read off that division's own page.
    assert_equal [ 3122, 364, 233 ],
      [ event.masters_participant_count, event.senior_participant_count, event.junior_participant_count ]
    # Only the rows whose Limitless deck the store already answers for: 284 (five rows) and 284/3
    # (three). The other 16 are blocked by name rather than guessed at.
    assert_equal 8, import.created_standing_ids.size
    assert_equal [ archetypes(:budew_ogerpon), archetypes(:ogerpon) ].sort_by(&:name),
      TournamentStanding.where(id: import.created_standing_ids).map(&:archetype).uniq.sort_by(&:name)
  end

  private

  EVENT_ID = "577".freeze
  # 24 rows over three divisions carrying 15 distinct deck references, two of which
  # (284 and 284/3) test/fixtures/limitless_archetype_mappings.yml already holds.
  EVENT_REFERENCES = 15
  EVENT_UNMAPPED_REFERENCES = 13

  EVENT_PAGES = {
    "https://limitlesstcg.com/tournaments/577" => "tournament_577_masters",
    "https://limitlesstcg.com/tournaments/577/SR" => "tournament_577_senior",
    "https://limitlesstcg.com/tournaments/577/JR" => "tournament_577_junior",
    "https://limitlesstcg.com/tournaments/577/decklists" => "tournament_577_masters_decklists",
    "https://limitlesstcg.com/tournaments/577/SR/decklists" => "tournament_577_senior_decklists"
  }.freeze
  # 577 publishes no Junior lists, which is ordinary: a division page with no block is an event
  # whose rows simply carry no list.
  EMPTY_PAGE = "<html><body></body></html>".freeze

  # Resolves to one archetype through Decks::ArchetypeDetector's containment rule and to no
  # overlap with any of the fixture's deck names, which is the :name_says_nothing case.
  LIST_TEXT = <<~TEXT.freeze
    Pokémon: 1
    4 Teal Mask Ogerpon ex TWM 25

    Trainer: 1
    4 Boss's Orders PAL 172

    Energy: 1
    4 Psychic Energy SVE 5
  TEXT

  def event_params(**overrides)
    { source: "event", tournament_id: EVENT_ID }.merge(overrides)
  end

  def stub_event_pages
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |url|
      calls << url
      page = EVENT_PAGES[url]
      page ? File.read(Rails.root.join("test/fixtures/files/limitless/#{page}.html")) : EMPTY_PAGE
    }
  end

  # The instance method and not a singleton: EventDecklists is constructed per run, and what has
  # to be counted is the calls its instance takes.
  def record_decklist_keys(text = LIST_TEXT)
    keys = []
    @decklists_restore = Tournaments::EventDecklists.instance_method(:call)
    Tournaments::EventDecklists.define_method(:call) { |key| keys << key; text }
    keys
  end

  def with_proposal(archetype:, verdict:)
    proposer = Tournaments::ArchetypeProposer
    original = proposer.method(:call)
    proposer.define_singleton_method(:call) { |**_options|
      proposer::Proposal.new(archetype: archetype, verdict: verdict, candidates: [ archetype ].compact)
    }
    yield
  ensure
    proposer.define_singleton_method(:call, original)
  end

  def capture_plan_options
    plan = Tournaments::StandingsImportPlan
    original = plan.method(:call)
    captured = nil
    plan.define_singleton_method(:call) { |**options| captured = options; original.call(**options) }
    yield
    captured
  ensure
    plan.define_singleton_method(:call, original)
  end

  # The fixtures' two pools are TWM-ASC and TWM-POR; this event publishes TEF-PBL, which is
  # StandardPool#name byte for byte and is the only thing the pool is resolved by.
  def tef_pbl_pool
    StandardPool.create!(
      first_card_set: CardSet.create!(code: "TEF", name: "Temporal Forces", release_date: Date.new(2024, 3, 22)),
      last_card_set: CardSet.create!(code: "PBL", name: "Pitch Black", release_date: Date.new(2026, 8, 1)),
      regulation_marks: %w[H I J], released_on: Date.new(2026, 8, 1), legal_on: Date.new(2026, 8, 15)
    )
  end

  # Eight rows at the importer's half-second courtesy pause is four seconds of sleeping against a
  # remote that is a fixture on disk.
  def with_no_pause
    original = Tournaments::LimitlessImportJob.request_pause
    Tournaments::LimitlessImportJob.request_pause = 0
    yield
  ensure
    Tournaments::LimitlessImportJob.request_pause = original
  end

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
