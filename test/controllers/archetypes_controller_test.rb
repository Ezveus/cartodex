require "test_helper"

class ArchetypesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "index lists every archetype in the catalog" do
    get archetypes_path

    assert_response :success
    # Against Archetype.count rather than a literal: the fixture set is shared, and this row is
    # about the page showing all of them, not about how many there happen to be.
    assert_select ".data-table-row", count: Archetype.count
    assert_select ".data-table-row", text: /Teal Mask Ogerpon ex/
  end

  # Both member printings, never the bare names: several cards share a name and an archetype
  # designates one of them.
  test "index names the printing of each member card" do
    get archetypes_path

    assert_select ".data-table-row", text: /#{Regexp.escape(cards(:budew_pre).printing_label)}/
    assert_select ".data-table-row",
      text: /#{Regexp.escape(cards(:teal_mask_ogerpon_ex).printing_label)}/
  end

  test "index prints the recorded counts and leaves an unrecorded archetype dashed" do
    get archetypes_path

    # standings_marker is the one fixture archetype standings point at: two rows, one event, no
    # list attached to either.
    assert_select ".data-table-row", text: /Standings Marker/ do
      assert_select ".data-table-cell[data-label=Standings]", text: "2"
      assert_select ".data-table-cell[data-label=Events]", text: "1"
      assert_select ".data-table-cell[data-label=Lists]", text: "—"
    end
    assert_select ".data-table-row", text: /Teal Mask Ogerpon ex/ do
      assert_select ".data-table-cell[data-label=Standings]", text: "—"
    end
  end

  # The index's four figures all blend paper events with imported online ones — a weekly online
  # tournament contributes a standing, a distinct event, a list and possibly the "Last event" date
  # — and the ordering key is the standings count, so the blend also decides which archetype leads
  # the page. Measured on production when the first online import landed: 106 standings and 16
  # events for one archetype, of which 13 and 13 came from online play, with nothing on the page
  # saying so.
  #
  # The note qualifies the row rather than any one figure, which is why it is asserted inside the
  # Archetype cell and not beside a number.
  test "index says when a row's figures include online play" do
    archetype = archetypes(:standings_marker)
    online_event = Tournament.create!(
      name: "Pumpkaweekly Index", date: Date.new(2026, 4, 18), tier: "other", online: true,
      format: "standard", standard_pool: standard_pools(:twm_por), created_by: @user
    )
    online_event.standings.create!(
      player_name: "JRobrueda", division: "open", placement: 1, archetype: archetype,
      created_by: @user
    )

    get archetypes_path

    assert_select ".data-table-row", text: /Standings Marker/ do
      # Both halves of the ratio. The standings share and the events share diverge sharply —
      # measured on production, 13 of 106 standings but 13 of 16 events — so a note carrying only
      # the first invites the reader to map it onto the bigger number and read the blend as
      # marginal. Here: 1 of 3 standings, but 1 of 2 events.
      assert_select ".archetype-row-note",
        text: /Includes 1 standing from online play, at 1 of these 2 events\./
      # The blend is still counted in, not filtered out — the note names it, it does not hide it.
      assert_select ".data-table-cell[data-label=Standings]", text: "3"
      assert_select ".data-table-cell[data-label=Events]", text: "2"
    end
  end

  # "Includes" states a mixture, and an archetype whose only record is an online import has none —
  # the ordinary shape of one online run against an archetype with no paper results. The detail
  # page draws the same branch (Performance::Result#all_events_online?).
  test "index says every result is online when none of them is not" do
    archetype = Archetype.create!(primary_card: cards(:honedge))
    online_event = Tournament.create!(
      name: "Weekly Only", date: Date.new(2026, 4, 18), tier: "other", online: true,
      format: "standard", standard_pool: standard_pools(:twm_por), created_by: @user
    )
    2.times do |i|
      online_event.standings.create!(
        player_name: "Online Player #{i}", division: "open", placement: i + 1,
        archetype: archetype, created_by: @user
      )
    end

    get archetypes_path

    assert_select ".data-table-row", text: /#{archetype.name}/ do
      assert_select ".archetype-row-note", text: "Every one of these 2 standings comes from online play."
      assert_select ".archetype-row-note", text: /Includes/, count: 0
    end
  end

  # The negative control. 61 of the 62 archetypes in production carry no online result, so a note
  # that renders unconditionally would be noise on almost every row — and this assertion is what
  # would catch it.
  test "index says nothing about online play on a row that has none" do
    get archetypes_path

    assert_select ".data-table-row", text: /Standings Marker/ do
      assert_select ".archetype-row-note", count: 0
    end
    assert_no_match(/online play/, response.body)
  end

  test "index links each row to the archetype's page and escapes the frame" do
    get archetypes_path

    assert_select "a[href=?][data-turbo-frame=_top]", archetype_path(archetypes(:ogerpon))
  end

  test "index filters by name" do
    get archetypes_path(q: "budew")

    assert_response :success
    assert_select ".data-table-row", count: 1
    assert_select ".data-table-row", text: /Budew/
  end

  test "index ignores a blank q" do
    get archetypes_path(q: "   ")

    assert_select ".data-table-row", count: Archetype.count
  end

  test "index keeps the query in the search field" do
    get archetypes_path(q: "budew")

    assert_select "form.archetypes-search input[name=q][value=budew]"
  end

  # The filter form targets this frame so the field survives the debounce — see
  # Archetypes::IndexView::FRAME_ID.
  test "index wraps the results in the turbo frame the filter form targets" do
    get archetypes_path

    assert_select "turbo-frame#archetype_results .data-table-row"
    assert_select "form.archetypes-search[data-turbo-frame=archetype_results][data-turbo-action=replace]"
  end

  test "index says so when a search matches nothing" do
    get archetypes_path(q: "nothingmatchesthis")

    assert_response :success
    assert_select ".data-table-row", count: 0
    assert_select ".empty-state", text: /No archetypes match this search/
  end

  test "index paginates and its pager links replace the address bar" do
    fill_a_page

    get archetypes_path

    assert_select ".data-table-row", count: ArchetypesController::PER_PAGE
    assert_select ".cards-pagination-info", text: %r{Page 1 / 2}
    assert_select "a.cards-pagination-link[data-turbo-action=replace]", text: /Next/
  end

  # `?page[]=1` hands params[:page] over as an Array, which does not answer to_i.
  test "an unknown page number does not blow up" do
    get archetypes_path(page: [ "1" ])

    assert_response :success
  end

  # Clamped rather than allowed to run off the end: an out-of-range page otherwise renders "No
  # archetypes recorded yet." over a catalog that is not empty.
  test "a page past the end renders the last page rather than the empty state" do
    fill_a_page

    get archetypes_path(page: 99)

    assert_response :success
    assert_select ".cards-pagination-info", text: %r{Page 2 / 2}
    assert_select ".data-table-row", minimum: 1
    assert_select ".empty-state", count: 0
  end

  # The ordering the spec asks for: most recorded first, so the archetypes members have actually
  # imported a field for lead, and the ones nobody has recorded a result for stay listed at the
  # bottom rather than being hidden — they are what members tag their own decks with.
  test "index orders by recorded standings, then by name" do
    quiet_archetype(1, name: "Aaa Unrecorded")
    recorded = quiet_archetype(2, name: "Zzz Recorded")
    record_standing_for(recorded, 2)

    get archetypes_path

    rows = css_select(".data-table-row").map(&:text)
    assert_operator position_of(rows, "Zzz Recorded"), :<, position_of(rows, "Aaa Unrecorded"),
      "an archetype with a recorded standing must come before one with none"
    # The tie-break among the archetypes with no standings at all. Without `:name` in the ORDER
    # BY, SQLite hands them back in rowid order and the one created last lands last.
    assert_operator position_of(rows, "Aaa Unrecorded"),
      :<, position_of(rows, archetypes(:budew_ogerpon).name),
      "archetypes with no standings must be ordered by name"
  end

  # The three counts and the date come from one grouped query, and the member cards from one
  # preload. Each archetype gets a card, a tournament and a field list of its own on purpose:
  # rows sharing an association issue identical SQL, which the per-request query cache serves and
  # count_queries does not count — hiding the very N+1 this guards.
  test "index issues a constant number of queries regardless of how many archetypes" do
    2.times { |i| catalogued_archetype(i) }

    get archetypes_path # warm the session: the first request of a test also loads the Devise user

    small = count_queries { get archetypes_path }

    (2..7).each { |i| catalogued_archetype(i) }

    large = count_queries { get archetypes_path }

    assert_response :success
    assert_equal small, large, "query count grew with the catalog: #{small} -> #{large}"
  end

  test "show renders the archetype's report" do
    get archetype_path(archetypes(:standings_marker))

    assert_response :success
    assert_select "h1", text: /Standings Marker/
  end

  # A card row names its printing and links to it. Here rather than only in
  # Archetypes::NameGroupRowTest because the component test builds its own Cards and invents their
  # ids — this is the only thing that proves the id reaching the page is the id of the card the
  # report actually chose.
  test "show names each card's printing and links it to that card" do
    archetype = quiet_archetype(700, name: "Linked Archetype")
    standing = listed_standing_for(archetype, 700)
    card = standing.deck.deck_cards.first.card

    get archetype_path(archetype)

    assert_response :success
    assert_select ".archetype-card-row a.archetype-card-name-text[href=?]",
                  card_path(card), text: card.printing_label
  end

  # No request test in the suite had ever rendered a printing sub-row: `listed_standing_for` gives
  # every standing a uniquely-named card, and the system helpers use one printing each, so
  # `NameGroupRow#printings` — where the sub-row links live — was reachable only from a component
  # test. Two printings of one *name* under two different fingerprints is the shape, and the
  # assertion is on two distinct hrefs: counting the anchors stays green with both pointing at the
  # first entry's card.
  test "show links each printing of a split name to its own card" do
    archetype = quiet_archetype(710, name: "Split Name Archetype")
    first, second = split_name_standing_for(archetype, 710)

    get archetype_path(archetype)

    assert_response :success
    assert_select ".archetype-printing-row a[href=?]", card_path(first), text: first.printing_label
    assert_select ".archetype-printing-row a[href=?]", card_path(second), text: second.printing_label
    # And the name line above them stays a name: it covers two genuinely different cards, so a
    # code there would name one of them as if it were the group.
    assert_select ".archetype-card-main .archetype-card-name-text", text: "Owl Of Two Printings"
    assert_select ".archetype-card-main a", count: 0
  end

  # The page the spec costs out at greatest length, and the one the index's own flat-cost test
  # says nothing about. Four services run here — the sample selector's grouped query, the card report's
  # two, the performance panel's four — and every one of them is a grouped or aggregate query
  # whose cost must not move with the sample.
  #
  # Every row gets an event, a field list and a card of its own on purpose: rows sharing an
  # association issue identical SQL, which the per-request query cache serves and count_queries
  # does not count — which is exactly what would hide an N+1. The pool is shared, deliberately:
  # it is what keeps the default sample growing with the rows instead of moving to a new pool
  # holding one list. Measured at 17 queries, unchanged from 3 lists to 10 — 16 of those plus one
  # more since the card report started reading `card_label_assignments` in its own query, a
  # single LEFT OUTER JOIN against `card_labels`.
  #
  # Every card here carries its own distinct label, on purpose — not one label shared across all
  # of them: identical association SQL is exactly what the per-request query cache serves after
  # the first hit, which is what `count_queries`/`capture_queries` cannot see and what would hide
  # this join regressing into one query per card. Read the count straight off `capture_queries`
  # rather than trusting `small`/`large` to agree by coincidence.
  test "show issues a constant number of queries regardless of how many lists" do
    archetype = quiet_archetype(200, name: "Reported Archetype")
    3.times { |i| label_card(listed_standing_for(archetype, i)) }

    get archetype_path(archetype) # warm the session: the first request also loads the Devise user

    small = capture_queries { get archetype_path(archetype) }

    (3..9).each { |i| label_card(listed_standing_for(archetype, i)) }

    large = capture_queries { get archetype_path(archetype) }

    assert_response :success
    assert_select ".archetype-card-row", minimum: 1
    assert_equal small.size, large.size, "query count grew with the sample: #{small.size} -> #{large.size}"
    assert_equal 1, small.count { |sql| sql.include?("card_label") },
      "the label join ran more than once against the small sample"
    assert_equal 1, large.count { |sql| sql.include?("card_label") },
      "the label join ran more than once against the large sample"
  end

  test "show badges a card's type label on its row" do
    archetype = quiet_archetype(400, name: "Labelled Archetype")
    standing = listed_standing_for(archetype, 400)
    card = standing.deck.deck_cards.first.card
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")

    get archetype_path(archetype)

    assert_response :success
    assert_select ".archetype-card-row .archetype-card-label", text: "ACE SPEC"
  end

  # Stage 2 introduces the `role` family, and NameGroupRow#type_labels filters to it with a bare
  # `.select(&:type?)` at the render layer rather than in the service — nothing before this test
  # exercised a card carrying both families at once, so a role label would have silently badged
  # beside the type one the day the seed added roles. Delete that `.select(&:type?)` call to watch
  # this go red.
  test "show does not badge a card's role label" do
    archetype = quiet_archetype(420, name: "Roled Archetype")
    standing = listed_standing_for(archetype, 420)
    card = standing.deck.deck_cards.first.card
    type_label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    type_label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")
    role_label = CardLabel.create!(slug: "attacker", name: "Attacker", family: "role", position: 10)
    role_label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")

    get archetype_path(archetype)

    assert_response :success
    assert_select ".archetype-card-row .archetype-card-label", text: "ACE SPEC"
    assert_select ".archetype-card-row .archetype-card-label", text: "Attacker", count: 0
  end

  # ── The card report's second grouping mode ──────────────────────────────────────────────────

  # And the type badge keeps its place on the name line while the sections are role sections: the
  # two families answer two different questions about one card, so a mode that hid the badge would
  # make "is this an ACE SPEC?" a question the reader can only answer by switching modes.
  test "show groups the card report by role when asked" do
    archetype = quiet_archetype(480, name: "Roled Report Archetype")
    standing = role_card(listed_standing_for(archetype, 480), "gust", "Gust", 30)
    card = standing.deck.deck_cards.first.card
    ace_spec = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    ace_spec.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")
    listed_standing_for(archetype, 481)

    get archetype_path(archetype, group: "role")

    assert_response :success
    assert_select ".archetype-category-header h3", text: "Gust"
    assert_select ".archetype-category-header h3", text: "No role recorded"
    assert_select ".archetype-category-header h3", text: "Pokémon", count: 0
    assert_select ".archetype-category-header h3", text: "ACE SPEC", count: 0
    assert_select ".archetype-card-row .archetype-card-label", text: "ACE SPEC"
  end

  # The clamp `#index` makes for `?page=` and `#show` already makes for `?pool=`, on the third
  # parameter this page reads: `?group[]=role` hands over an Array, which is neither the string
  # "role" nor anything that could be compared to it without raising. The report falls back to the
  # grouping it has always had rather than 404ing or blowing up.
  test "show survives a malformed group parameter and stays in type mode" do
    archetype = quiet_archetype(500, name: "Malformed Group Archetype")
    listed_standing_for(archetype, 500)

    get archetype_path(archetype, group: [ "role" ])

    assert_response :success
    assert_select ".archetype-category-header h3", text: "Pokémon"
    assert_select ".archetype-category-header h3", text: "No role recorded", count: 0
  end

  # The rule the mode links exist under: each re-emits the sample the page is *showing*, which is
  # the scope's own answer, never the parameter that produced it. Asserted through a malformed
  # `?pool[]=` precisely because that is the case where the two differ — the scope fell back to the
  # default pool, and a link built from `params[:pool]` would carry `pool[]=junk` back into the
  # next request and into every copy of that link.
  test "the report's mode links re-emit the sample the page fell back to, never the parameter" do
    archetype = quiet_archetype(520, name: "Fallback Archetype")
    listed_standing_for(archetype, 520)

    get archetype_path(archetype, pool: [ "junk" ])

    assert_response :success
    hrefs = css_select("a.archetype-report-mode").map { |link| link["href"] }

    assert_equal 2, hrefs.size
    assert hrefs.all? { |href| href.include?("pool=#{standard_pools(:twm_por).id}") },
      "a mode link did not carry the pool the page is showing: #{hrefs.inspect}"
    assert hrefs.any? { |href| href.include?("group=type") }
    assert hrefs.any? { |href| href.include?("group=role") }
    assert_no_match(/junk/, response.body)
  end

  # Role mode regroups entries the page has already loaded, so it must cost exactly what type mode
  # costs — the same 17 the test above pins for the type report.
  #
  # The literal matters here and a `small == large` comparison would not have caught what this is
  # for. Measured: an N+1 issued once *per section* moved this page from 17 to 18 on a fixture
  # whose role mode renders a single "No role recorded" section, and to 25 on the eight sections
  # the production data produces — while the type/role equality stayed true and the test stayed
  # green. Hence two roles on two distinct cards below: role mode has to render several sections
  # before the count can say anything at all.
  test "role mode costs no query the type report does not" do
    archetype = quiet_archetype(540, name: "Grouped Archetype")
    role_card(listed_standing_for(archetype, 540), "draw", "Draw", 10)
    role_card(listed_standing_for(archetype, 541), "search", "Search", 20)
    listed_standing_for(archetype, 542)

    get archetype_path(archetype) # warm the session: the first request also loads the Devise user

    type_mode = capture_queries { get archetype_path(archetype) }
    role_mode = capture_queries { get archetype_path(archetype, group: "role") }

    assert_response :success
    assert_select ".archetype-category-header h3", text: "Draw"
    assert_select ".archetype-category-header h3", text: "Search"
    assert_select ".archetype-category-header h3", text: "No role recorded"

    assert_equal 17, type_mode.size, "the type report moved off its pinned cost"
    assert_equal 17, role_mode.size, "role mode issued a query the type report does not"
    assert_equal 1, role_mode.count { |sql| sql.include?("card_label") },
      "the label join ran more than once in role mode"
  end

  # The blend neither the sample selector nor the performance panel can show any other way: the
  # pool axis puts an online weekly and a Regional anchored to the same pool in one bucket, and the
  # online import forces `tier: "other"`, so `by_tier` cannot tell them apart either. This is the
  # request that proves both sentences reach the rendered page rather than merely the two services.
  test "show names how much of the sample comes from online play" do
    archetype = quiet_archetype(300, name: "Blended Archetype")
    2.times { |i| listed_standing_for(archetype, 300 + i) }
    3.times { |i| listed_standing_for(archetype, 310 + i, online: true) }

    get archetype_path(archetype)

    assert_response :success
    assert_select ".archetype-sample-note",
      text: /3 of these 5 lists come from an online tournament\./
    assert_select ".archetype-fact",
      text: /3 of these standings come from online tournaments, at 3 of the 5 events counted above\./
  end

  # And says nothing at all about it on a sample of paper events — a "0 online" line reads as a
  # warning about nothing.
  test "show says nothing about online play when the sample holds none" do
    archetype = quiet_archetype(320, name: "Paper Archetype")
    3.times { |i| listed_standing_for(archetype, 320 + i) }

    get archetype_path(archetype)

    assert_response :success
    # Against the raw body rather than assert_select: `assert_select "body", text: …, count: 0`
    # looked like this assertion and was vacuous — the filter matches nothing on a document whose
    # single <body> is not compared the way the option reads, so it passed with the sentence
    # rendered. Sabotage proved it: removing the guard left this test green.
    assert_no_match(/online/, response.body)
  end

  # ---- the venue axis (#160) ----

  # The defect the issue names, from the page's side: Alakazam's blended report prints twelve cards
  # between 40 % and 60 %, none of which describes either half. What is asserted here is the
  # mechanism only — the report covers fewer cards once the sample narrows — because
  # `listed_standing_for` gives every standing a card of its own, so no card here can move from a
  # blend to 100 %. That half is measured by the system test, whose fixture plays one card on the
  # paper side alone (50 % → 100 %).
  test "a venue narrows the report to the sample it names" do
    archetype = quiet_archetype(600, name: "Venued Archetype")
    2.times { |i| listed_standing_for(archetype, 600 + i) }
    3.times { |i| listed_standing_for(archetype, 610 + i, online: true) }

    get archetype_path(archetype)

    # One pool and both venues: the Venue select alone, and no Sample select — a `<select>` of one
    # option is the non-choice `Result#selectable?` exists to drop. 15 of the 24 blended
    # archetypes in production are in exactly this shape.
    assert_select ".archetype-sample-label", count: 1
    assert_select "select[name=venue]", count: 1
    assert_select "select[name=pool]", count: 0
    blended = css_select(".archetype-card-row").size

    get archetype_path(archetype, venue: "paper")

    assert_response :success
    assert_select "select[name=venue] option[selected]", text: /\APaper/
    paper = css_select(".archetype-card-row").size
    assert_operator paper, :<, blended, "the paper sample reported as many cards as the blend"
  end

  # Two pools *and* both venues is the only shape where both selects render, and it is the state
  # the system test measures the geometry of. Nine archetypes in production are multi-pool with a
  # blended pool.
  test "an archetype with two pools and two venues renders both selects" do
    archetype = quiet_archetype(690, name: "Two Axis Archetype")
    2.times { |i| listed_standing_for(archetype, 690 + i) }
    2.times { |i| listed_standing_for(archetype, 695 + i, online: true) }
    older = Tournament.create!(name: "Older Cup 690", date: Date.new(2025, 6, 1), tier: "regional",
                               format: "standard", standard_pool: standard_pools(:twm_asc),
                               created_by: @user)
    older.standings.create!(player_name: "Older Player 690", division: "masters", placement: 1,
                            archetype: archetype, created_by: @user,
                            deck: Deck.create!(name: "Older List 690", shared: true,
                                               standard_pool: standard_pools(:twm_asc)))

    get archetype_path(archetype)

    assert_select ".archetype-sample-label", count: 2
    assert_select "select[name=pool]", count: 1
    assert_select "select[name=venue]", count: 1
  end

  # The clamp, in the only two things the page still shows once it has fired: there is no venue
  # select to read, because a clamp fires exactly when one venue holds nothing and that is when
  # `venue_selectable?` is false. So the report must render its blended rows *and* the mode links
  # must carry no venue — the second alone passes an implementation that empties the relation, and
  # the first alone passes one that keeps the dead parameter in every copied URL.
  test "a venue naming an empty cell renders the blended report and re-emits no venue" do
    archetype = quiet_archetype(620, name: "Clamped Archetype")
    2.times { |i| listed_standing_for(archetype, 620 + i) }

    get archetype_path(archetype, venue: "online")

    assert_response :success
    assert_select ".archetype-card-row", minimum: 1
    assert_select "select[name=venue]", count: 0
    hrefs = css_select("a.archetype-report-mode").map { |link| link["href"] }
    assert_predicate hrefs, :any?
    assert_empty hrefs.select { |href| href.include?("venue=") },
      "a mode link carried a venue the page had clamped away"
  end

  # `?venue[]=junk` hands over an Array, which no comparison here may assume is a String.
  test "show survives a malformed venue parameter" do
    archetype = quiet_archetype(630, name: "Malformed Venue Archetype")
    listed_standing_for(archetype, 630)
    listed_standing_for(archetype, 631, online: true)

    get archetype_path(archetype, venue: [ "junk" ])

    assert_response :success
    assert_select "select[name=venue] option[selected]", text: /\AAll/
  end

  # The pinned cost, per venue and as a literal, on a *blended* archetype — on a paper-only one
  # both venue values clamp to the blended sample and the count is flat for the wrong reason,
  # which is what the `assert_select` guards against. A duplicated `joins(:tournament)` is
  # deliberately not what this defends: Rails collapses it to one INNER JOIN, so no query counter
  # could ever see it.
  test "the venue axis costs no query the blended page does not" do
    archetype = quiet_archetype(640, name: "Venue Cost Archetype")
    2.times { |i| listed_standing_for(archetype, 640 + i) }
    2.times { |i| listed_standing_for(archetype, 650 + i, online: true) }

    get archetype_path(archetype) # warm the session: the first request also loads the Devise user

    counts = [ nil, "paper", "online" ].to_h do |venue|
      queries = capture_queries { get archetype_path(archetype, venue: venue) }
      assert_select ".archetype-card-row", minimum: 1
      [ venue, queries.size ]
    end

    assert_equal [ 17, 17, 17 ], counts.values, "a venue changed the page's cost: #{counts.inspect}"
  end

  # The twin of the note below, one panel further down, and false in the other direction: under
  # `venue=online` the counts *do* separate online play from paper, because every row is online.
  # It was already false on the 23 of 48 production archetypes whose whole sample is online, so
  # this assertion is red on master before the venue axis exists.
  test "the performance panel does not claim to blend a sample that is all online" do
    archetype = quiet_archetype(660, name: "All Online Archetype")
    2.times { |i| listed_standing_for(archetype, 660 + i, online: true) }

    get archetype_path(archetype)

    assert_response :success
    assert_select ".archetype-fact-muted", text: /comes from an online tournament|come from online/
    assert_no_match(/do not separate online play from paper/, response.body)
  end

  # The one thing the placement breakdown cannot say for itself, and the reason this note exists:
  # the online source is a leaderboard of best finishes, de-duplicated per player keeping the best
  # result, while the paper source is an event's whole results page. Measured over the production
  # data's placed standings, online is 20.2 % firsts and 42.9 % top-4 against paper's 0.9 % and
  # 4.3 %. Unsaid, "1st 18 of 20" reads as a win rate on a page that refuses to print one.
  #
  # It prints on a blend as well as on an all-online sample — a blend is the same distortion in
  # smaller proportion — so both are asserted, and the paper-only case asserts its absence.
  test "the panel says the online placements come from a leaderboard of best finishes" do
    archetype = quiet_archetype(700, name: "Leaderboard Archetype")
    2.times { |i| listed_standing_for(archetype, 700 + i, online: true) }

    get archetype_path(archetype)

    assert_response :success
    assert_select ".archetype-fact-muted", text: /leaderboard of best finishes/
  end

  test "the leaderboard note prints on a blended sample too" do
    archetype = quiet_archetype(710, name: "Blended Leaderboard Archetype")
    2.times { |i| listed_standing_for(archetype, 710 + i) }
    2.times { |i| listed_standing_for(archetype, 715 + i, online: true) }

    get archetype_path(archetype)

    assert_response :success
    assert_select ".archetype-fact-muted", text: /leaderboard of best finishes/
  end

  # And never where there is no online row to qualify: a sentence about an absent source reads as
  # a warning about nothing, the rule the online counter beside it already follows.
  test "the leaderboard note is withheld from an all-paper sample" do
    archetype = quiet_archetype(720, name: "Paper Only Archetype")
    2.times { |i| listed_standing_for(archetype, 720 + i) }

    get archetype_path(archetype)

    assert_response :success
    assert_no_match(/leaderboard of best finishes/, response.body)
  end

  # Performance reads `@scope.standings`, so it narrows with the venue without a line of its own —
  # and the division breakdown is what proves it did rather than a counter that could agree by
  # coincidence: the importer writes `division: "open"` on an online row and an age division on a
  # paper one, so the blended sample shows an Open row and the paper one must not.
  test "the performance panel narrows with the venue" do
    archetype = quiet_archetype(670, name: "Divided Archetype")
    2.times { |i| listed_standing_for(archetype, 670 + i) }
    3.times { |i| open_division_standing_for(archetype, 680 + i) }

    get archetype_path(archetype)

    assert_select ".data-table-cell", text: "Open"
    # Ui::Stat prints the value and its label as two elements, so the section's text runs them
    # together — "5standings5events5lists".
    assert_select ".deck-show-stats", text: /\A5\s*standings/

    get archetype_path(archetype, venue: "paper")

    assert_response :success
    assert_select ".data-table-cell", text: "Open", count: 0
    assert_select ".deck-show-stats", text: /\A2\s*standings/
  end

  test "show 404s on an unknown archetype" do
    get archetype_path(id: 999_999)

    assert_response :not_found
  end

  # An unknown or malformed ?pool= falls back to the default rather than 404ing — the fallback
  # lives in Archetypes::MetagameScope, and this is the request that proves the controller hands
  # the raw param straight to it instead of casting it first.
  test "show survives a malformed pool parameter" do
    get archetype_path(archetypes(:standings_marker), pool: [ "junk" ])

    assert_response :success
  end

  test "a visitor is sent to sign in for both pages" do
    sign_out @user

    get archetypes_path
    assert_redirected_to new_user_session_path

    get archetype_path(archetypes(:ogerpon))
    assert_redirected_to new_user_session_path
  end

  private

  # Helpers below `private`, and last in the file: a `test` declared under `private` is defined
  # private and never runs.

  def position_of(rows, text)
    index = rows.index { |row| row.include?(text) }
    assert_not_nil index, "expected a row naming #{text.inspect}"
    index
  end

  # An archetype nothing else in the suite references, with a card of its own — the
  # (primary_fingerprint, secondary_fingerprint) pair is UNIQUE, so two archetypes cannot share a
  # single member card.
  def quiet_archetype(index, name: "Quiet Archetype #{index}")
    card = Card.create!(
      name: "Quiet Pokémon #{index}", set_name: "QA#{index}", set_number: "1",
      card_type: "Pokémon", hp: 60, rarity: "Common", type_symbol: "Colorless", retreat_cost: 1
    )
    Archetype.create!(primary_card: card, name: name, custom_name: "1")
  end

  # One recorded standing, at an event of its own and with a field list of its own: ownerless and
  # shared, which is what an import actually produces (Deck refuses an ownerless deck that is not
  # shared, and refuses a physical one).
  # Every third row is online, so the flat-cost test above actually walks the `online?` branch the
  # note hangs off. Without one it never did: `online_note` returned early on all eight rows, and a
  # per-row query put behind that branch later — the obvious home for a venue split — would have
  # kept `assert_equal small, large` green while the page N+1'd.
  def record_standing_for(archetype, index)
    tournament = Tournament.create!(
      name: "Quiet Cup #{index}", date: Date.new(2026, 4, 1) + index, tier: "league_cup",
      format: "standard", standard_pool: standard_pools(:twm_por), created_by: @user,
      online: (index % 3).zero?
    )
    field_list = Deck.create!(
      name: "Quiet Field List #{index}", shared: true, standard_pool: standard_pools(:twm_por)
    )
    tournament.standings.create!(
      player_name: "Quiet Player #{index}", placement: 1,
      # What the importer writes for each venue: online play has no age divisions.
      division: tournament.online? ? "open" : "masters",
      archetype: archetype, deck: field_list, created_by: @user
    )
  end

  def catalogued_archetype(index)
    record_standing_for(quiet_archetype(index), index)
  end

  # One standing of one archetype, with a card, an event and a field list of its own — distinct
  # associations per row, so no two rows issue identical SQL that the per-request query cache
  # would serve and count_queries would not see. Unlike record_standing_for it takes an existing
  # archetype: the report is one archetype's, and every row has to land in it.
  #
  # The pool is the shared fixture on purpose. A pool per row would make each event its own
  # sample, and MetagameScope's default — the most recent pool — would then always hold exactly
  # one list however many rows exist, which is a flat cost proving nothing.
  # `online:` writes the event the way the import does — anchored to the same pool as the paper
  # ones, and `tier: "other"` — because the point of the two figures it feeds is that an online
  # event is indistinguishable from a paper one on both axes this page groups by.
  # `card_set:` is what makes the pinned 17 defensive rather than decorative. A belongs_to whose
  # FK is NULL emits no query, so a card built without one lets an implementation reaching for
  # `card.card_set.code` instead of `set_name` — the obvious "improvement" on a line that names a
  # printing — cost nothing here and one query per card in production. Measured: with the sets
  # attached such a read reports "query count grew with the sample: 20 -> 27" and fails five
  # tests; without them the same N+1 leaves every flat-cost test green. One set per card, so no
  # two rows issue identical SQL the per-request query cache would serve.
  def listed_standing_for(archetype, index, online: false)
    card = Card.create!(
      name: "Report Pokémon #{index}", set_name: "RP#{index}", set_number: "1",
      card_type: "Pokémon", hp: 60, rarity: "Common", type_symbol: "Colorless", retreat_cost: 1,
      card_set: CardSet.create!(code: "RP#{index}", name: "Report Set #{index}")
    )
    tournament = Tournament.create!(
      name: "Report Cup #{index}", date: Date.new(2026, 4, 1) + index,
      tier: online ? "other" : "league_cup", online: online,
      format: "standard", standard_pool: standard_pools(:twm_por), created_by: @user
    )
    field_list = Deck.create!(
      name: "Report Field List #{index}", shared: true, standard_pool: standard_pools(:twm_por)
    )
    field_list.deck_cards.create!(card: card, quantity: 2)
    tournament.standings.create!(
      player_name: "Report Player #{index}", division: "masters", placement: index + 1,
      archetype: archetype, deck: field_list, created_by: @user
    )
  end

  # One list holding two printings of one card *name* under two different fingerprints — the
  # `split?` shape of a NameGroup, which no request test could produce before: differing `hp` is
  # what makes `compute_fingerprint` land on two values rather than folding them into one row.
  # Returns the two cards, in the order the report sorts them (by inclusion, then set number
  # numerically — equal here, so 7 before 77).
  def split_name_standing_for(archetype, index)
    cards = [ [ "7", 60 ], [ "77", 90 ] ].map do |set_number, hp|
      Card.create!(
        name: "Owl Of Two Printings", set_name: "SP#{index}", set_number: set_number,
        card_type: "Pokémon", hp: hp, rarity: "Common", type_symbol: "Colorless", retreat_cost: 1,
        card_set: CardSet.create!(code: "SP#{index}#{set_number}", name: "Split Set #{set_number}")
      )
    end
    assert_equal 2, cards.map(&:fingerprint).uniq.size, "sanity: the two printings must not fold"

    tournament = Tournament.create!(
      name: "Split Name Cup #{index}", date: Date.new(2026, 4, 1) + index, tier: "league_cup",
      format: "standard", standard_pool: standard_pools(:twm_por), created_by: @user
    )
    field_list = Deck.create!(
      name: "Split Name List #{index}", shared: true, standard_pool: standard_pools(:twm_por)
    )
    cards.each { |card| field_list.deck_cards.create!(card: card, quantity: 1) }
    tournament.standings.create!(
      player_name: "Split Name Player #{index}", division: "masters", placement: 1,
      archetype: archetype, deck: field_list, created_by: @user
    )

    cards
  end

  # An online standing carrying the division the online importer actually writes. Neither
  # `listed_standing_for` nor `record_standing_for` can produce it: the first hardcodes "masters"
  # and the second derives `online` from the index, and the venue tests need both halves chosen
  # rather than computed.
  def open_division_standing_for(archetype, index)
    tournament = Tournament.create!(
      name: "Open Cup #{index}", date: Date.new(2026, 4, 1) + index, tier: "other", online: true,
      format: "standard", standard_pool: standard_pools(:twm_por), created_by: @user
    )
    field_list = Deck.create!(
      name: "Open Field List #{index}", shared: true, standard_pool: standard_pools(:twm_por)
    )
    tournament.standings.create!(
      player_name: "Open Player #{index}", division: "open", placement: 1,
      archetype: archetype, deck: field_list, created_by: @user
    )
  end

  # A fresh label per standing, not one shared across all of them — see the flat-cost test above
  # for why that distinctness is load-bearing.
  def label_card(standing)
    card = standing.deck.deck_cards.first.card
    label = CardLabel.create!(slug: "label-#{standing.id}", name: "Label #{standing.id}",
                               family: "type", position: standing.id)
    label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")
    standing
  end

  # A curated role on the standing's card, which is the row the report reads — the suggester and
  # the admin screen are two ways of writing it and the report is indifferent to which. A distinct
  # role per call, like `label_card`'s distinct labels: the flat-cost test needs role mode to
  # render several sections before its count says anything.
  def role_card(standing, slug, name, position)
    card = standing.deck.deck_cards.first.card
    role = CardLabel.create!(slug: slug, name: name, family: "role", position: position)
    role.assignments.create!(fingerprint: card.fingerprint, card: card, source: "curated")
    standing
  end

  # Enough archetypes to push the catalog onto a second page, without any of them carrying a
  # standing — pagination is about the row count, not about what the rows say.
  def fill_a_page
    ArchetypesController::PER_PAGE.times { |i| quiet_archetype(100 + i) }
  end
end
