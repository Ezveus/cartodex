require "application_system_test_case"

# The admin screen that turns a Limitless results page into public standings rows, driven the way
# an admin actually reaches it: through the admin navbar, which below 768px is behind a hamburger.
#
# What only a browser can check here is that the form and the plan are one page — the preview is a
# GET, so the plan comes back with the form still filled in above it, which is what lets an admin
# read "this event has no Standard pool" and narrow the run without retyping anything. A POST would
# have rendered nothing at all (Turbo refuses a non-redirected 200 answering a form POST), and no
# request test can see that.
#
# The results page is stubbed at HttpFetcher, in this process: a system test boots Puma in-process,
# so the singleton the test replaces is the one the server calls. Nothing here leaves the machine.
class StandingsImportTest < ApplicationSystemTestCase
  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    login_as @admin, scope: :user

    @archetype = archetypes(:standings_marker)

    @original_http_fetcher_call = HttpFetcher.method(:call)
    html = File.read(Rails.root.join("test/fixtures/files/limitless_deck_results.html"))
    HttpFetcher.define_singleton_method(:call) { |_url| html }
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
    Tournaments::EventDecklists.define_method(:call, @decklists_restore) if @decklists_restore
  end

  test "an admin reaches the screen from the navbar and previews a run" do
    visit admin_root_path

    # Not a plain click: below the breakpoint the nav link is display:none until the hamburger
    # opens the menu, and Capybara will not click what it cannot see.
    click_nav_link "Limitless import"
    assert_current_path new_admin_standings_import_path

    fill_in "Limitless deck id", with: "280"
    select @archetype.name, from: "Archetype"
    fill_in "Only these events (optional)", with: "NAIC"
    click_on "Preview"

    # The event heading, with the (SR) and (JR) halves folded into it: three Limitless headings,
    # one catalog event.
    assert_selector "h3", text: "NAIC 2026, New Orleans"

    # The two derived values a wrong guess makes permanent, both on screen before anything runs.
    assert_text "International Championship"
    assert_selector "[data-label=Division]", text: "senior"
    assert_selector "[data-label=Division]", text: "junior"

    # The filter really filtered: Worlds and Antwerp are on the same page and neither is here.
    assert_no_selector "h3", text: "World Championships 2026"

    # The form is still above the plan, still carrying what produced it — the whole reason the
    # preview is a GET onto the same screen rather than a page of its own.
    assert_field "Limitless deck id", with: "280"
    assert_field "Only these events (optional)", with: "NAIC"

    # Present, and named with the count it will write. Not clicked: enqueuing the run is a
    # different test's job, and this one has nothing to say about what the job does.
    assert_button "Import 4 rows as #{@archetype.name}"
  end

  # The online source on the same screen. Worth a browser and not just a request test for the
  # reason the paper one is: the source select and the three fields it governs are all rendered
  # together and come back filled in above the plan, and an admin who picked "online" has to see
  # the run they described rather than retype it.
  #
  # It also puts the leaderboard's one genuinely deceptive column in front of a human. The fixture
  # row for "Moujii's Dojo" carries data-place="4" and really finished 2nd; a parser that read the
  # attribute would render "4" here and nothing else in the app would ever disagree with it.
  test "an admin previews an online run, and the plan shows real finishes rather than leaderboard ranks" do
    html = File.read(Rails.root.join("test/fixtures/files/limitless_online_results.html"))
    HttpFetcher.define_singleton_method(:call) { |_url| html }

    visit new_admin_standings_import_path

    select "Online best finishes — play.limitlesstcg.com/decks/<slug>", from: "Source"
    fill_in "Leaderboard slug (online)", with: "raging-bolt-ogerpon"
    fill_in "Rotation (online)", with: "2026"
    fill_in "Set (online)", with: card_sets(:por).code
    select @archetype.name, from: "Archetype"
    click_on "Preview"

    # Every row of an online event is "open": online play has no age divisions, and writing
    # "masters" would be a lie Archetypes::Performance#by_division reports as fact.
    assert_selector "[data-label=Division]", text: "open", minimum: 1
    assert_no_selector "[data-label=Division]", text: "masters"

    # The trap, on screen: six rows carry data-place 1..6, and two of them finished 2nd.
    assert_selector "[data-label=Placement]", text: "2", minimum: 1
    assert_no_selector "[data-label=Placement]", text: "6"

    # The form still carries what produced the plan, source included.
    assert_field "Leaderboard slug (online)", with: "raging-bolt-ogerpon"
    assert_field "Set (online)", with: card_sets(:por).code

    # The count the admin approves is the plan's, before de-duplication — which happens in the run,
    # because the plan never fetches a decklist and a preview must not be 21 HTTP requests.
    assert_button "Import 6 rows as #{@archetype.name}"
  end

  # A plan with nothing to write offers no button at all. "Regional Antwerp" predates every
  # Standard pool in the fixtures, so its only row is blocked — and an admin who can click a
  # button that writes nothing learns that the button sometimes does nothing, which is the wrong
  # thing to learn about a control that publishes to a catalog every member reads.
  test "an event no Standard pool covers is shown blocked, with no way to run it" do
    visit new_admin_standings_import_path

    fill_in "Limitless deck id", with: "280"
    select @archetype.name, from: "Archetype"
    fill_in "Only these events (optional)", with: "Antwerp"
    click_on "Preview"

    assert_selector ".standings-import-event--blocked"
    assert_text "no Standard pool covers 2024-11-02"
    assert_no_selector "form.standings-import-confirm"
  end

  # The event source's arbitration table, driven the way it has to be used: a deck the catalogue
  # has no archetype for — Beedrill on event 578, here the fixture's Dhelmise (374) — is created
  # from its own line and selected there, without leaving the preview. Only a browser can check
  # it: the section is revealed, filled and posted by JavaScript, and this repository has no JS
  # test infrastructure.
  test "an admin creates a missing archetype from its line and the confirmation stores it" do
    stub_event(list: "4 Dhelmise TST 901\n4 Teal Mask Ogerpon ex TWM 25\n")
    dhelmise = Card.create!(name: "Dhelmise", card_type: "Pokémon", set_name: "TST", set_number: "901",
      rarity: "Rare", hp: 130, type_symbol: "Grass", retreat_cost: 3)

    imports_before = Import.pluck(:id)
    visit preview_admin_standings_imports_path(source: "event", tournament_id: "577")

    row = find(".standings-import-mapping", text: "374")
    # The lines that need a human come first: the first row on the table is one of them.
    assert_selector ".data-table-body > .data-table-row:first-child.standings-import-mapping--decide"
    assert row[:class].include?("standings-import-mapping--decide")

    within(row) do
      click_on "+ New archetype"
      primary = find(".standings-import-mapping-create input[type=text]", match: :first)
      assert_equal dhelmise.printing_label, primary.value

      # Enter in a search box would otherwise be a click on "Confirm mappings and import". A path
      # check right after the key is racy — the old page is still current while a submit is in
      # flight — so a listener records whether the form was ever submitted, and the search's own
      # debounced answer is what the test waits on before reading it.
      page.execute_script(<<~JS)
        window.__submitted = false
        document.querySelector("form.standings-import-confirm")
          .addEventListener("submit", () => { window.__submitted = true })
      JS
      all(".standings-import-mapping-create input[type=text]").each { |input| input.send_keys(:enter) }
      primary.send_keys(:backspace)
      assert_selector ".archetype-search-item, .archetype-search-empty", match: :first
    end
    assert_equal false, page.evaluate_script("window.__submitted")
    assert_equal imports_before, Import.pluck(:id)
    within(row) do
      primary = find(".standings-import-mapping-create input[type=text]", match: :first)
      primary.fill_in(with: "Dhelmise")
      find(".archetype-search-item", text: "TST 901").click
    end

    within(row) { click_on "Create & select" }

    within(row) { assert_no_selector ".standings-import-mapping-create", visible: true }
    created = Archetype.find_by!(primary_card: dhelmise)
    assert_equal created.id.to_s, row.find("select").value
    assert row[:class].include?("standings-import-mapping--answered")
    # Offered on every other line too: two decks can be one new archetype.
    other = find(".standings-import-mapping", text: "284/3")
    names = other.find("select").all("option", visible: :all).map(&:text)
    assert_includes names, created.name
    assert_equal [ "— Leave unmapped —", *Archetype.order(:name).pluck(:name) ], names

    click_on "Confirm mappings and import"
    assert_current_path admin_imports_path

    assert_equal created, LimitlessArchetypeMapping.find_by!(limitless_deck_id: 374, limitless_variant: nil).archetype
  end

  # What the pre-fill is: a proposal the admin may correct. A result picked from the search is what
  # gets created, and a card whose text was erased is not — card-select never clears the id it
  # wrote, so without mapping-archetype#forget an erased secondary still rode the POST.
  test "a pre-filled card can be replaced from the search, and an erased one is not posted" do
    stub_event(list: "4 Dhelmise TST 901\n")
    Card.create!(name: "Dhelmise", card_type: "Pokémon", set_name: "TST", set_number: "901",
      rarity: "Rare", hp: 130, type_symbol: "Grass", retreat_cost: 3)
    budew = cards(:budew_asc)

    visit preview_admin_standings_imports_path(source: "event", tournament_id: "577")
    row = find(".standings-import-mapping", text: "374")

    within(row) do
      click_on "+ New archetype"
      primary, secondary = all(".standings-import-mapping-create input[type=text]").to_a
      primary.fill_in(with: "Budew")
      find(".archetype-search-item", text: "ASC 16").click
      assert_equal budew.printing_label, primary.value

      secondary.fill_in(with: "Teal Mask")
      find(".archetype-search-item", text: "TWM 25").click
      secondary.fill_in(with: "")

      click_on "Create & select"
    end

    within(row) { assert_no_selector ".standings-import-mapping-create", visible: true }
    created = Archetype.find(row.find("select").value)
    assert_equal budew, created.primary_card
    assert_nil created.secondary_card
  end

  # The line's own state, driven by hand: nothing is answered on load, a choice quiets the row, and
  # "— Leave unmapped —" brings the rail back. Read off the computed style, not the class — the
  # class is only true if the stylesheet lets it win.
  test "a line goes quiet once answered by hand, and loud again when unanswered" do
    stub_event(list: "4 Teal Mask Ogerpon ex TWM 25\n")
    visit preview_admin_standings_imports_path(source: "event", tournament_id: "577")

    assert_no_selector ".standings-import-mapping--answered"
    row = find(".standings-import-mapping", text: "339")
    confirmed = find(".standings-import-mapping--confirmed", match: :first)
    decide_background = style(row, "backgroundColor")
    assert_not_equal style(confirmed, "backgroundColor"), decide_background

    row.find("select").select(@archetype.name)
    assert row.matches_css?(".standings-import-mapping--answered")
    assert_equal "rgb(255, 255, 255)", style(row, "backgroundColor")
    assert_equal "rgb(46, 158, 91)", style(row, "borderLeftColor")

    row.find("select").select("— Leave unmapped —")
    assert row.matches_css?(".standings-import-mapping--decide:not(.standings-import-mapping--answered)")
    assert_equal decide_background, style(row, "backgroundColor")
  end

  # The endpoint answers an archetype that already exists with that archetype. Nothing is added
  # then — every select already offers it — and the lists stay in name order either way.
  test "creating an archetype that exists selects it without offering it twice" do
    stub_event(list: "4 Teal Mask Ogerpon ex TWM 25\n")
    existing = archetypes(:ogerpon)
    visit preview_admin_standings_imports_path(source: "event", tournament_id: "577")
    row = find(".standings-import-mapping", text: "339")

    within(row) do
      click_on "+ New archetype"
      find(".standings-import-mapping-create input[type=text]", match: :first).fill_in(with: "Teal Mask")
      find(".archetype-search-item", text: "TWM 25").click
      click_on "Create & select"
    end

    within(row) { assert_no_selector ".standings-import-mapping-create", visible: true }
    assert_equal existing.id.to_s, row.find("select").value
    all(".standings-import-mapping select").each do |select|
      assert_equal 1, select.all("option[value='#{existing.id}']", visible: :all).size
    end
  end

  private

  def style(node, property)
    page.evaluate_script("getComputedStyle(arguments[0])[arguments[1]]", node, property)
  end

  EVENT_PAGES = {
    "https://limitlesstcg.com/tournaments/577" => "tournament_577_masters",
    "https://limitlesstcg.com/tournaments/577/SR" => "tournament_577_senior",
    "https://limitlesstcg.com/tournaments/577/JR" => "tournament_577_junior"
  }.freeze

  # The division pages from disk, and every list answered with `list` — the list is read for what
  # deck it is, and this test is about one deck.
  def stub_event(list:)
    StandardPool.create!(
      first_card_set: CardSet.create!(code: "TEF", name: "Temporal Forces", release_date: Date.new(2024, 3, 22)),
      last_card_set: CardSet.create!(code: "PBL", name: "Pitch Black", release_date: Date.new(2026, 8, 1)),
      regulation_marks: %w[H I J], released_on: Date.new(2026, 8, 1), legal_on: Date.new(2026, 8, 15)
    )
    HttpFetcher.define_singleton_method(:call) { |url|
      page = EVENT_PAGES[url]
      page ? File.read(Rails.root.join("test/fixtures/files/limitless/#{page}.html")) : "<html><body></body></html>"
    }
    @decklists_restore = Tournaments::EventDecklists.instance_method(:call)
    Tournaments::EventDecklists.define_method(:call) { |_key| list }
  end
end
