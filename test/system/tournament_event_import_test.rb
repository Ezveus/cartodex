require "application_system_test_case"

# Importing one whole real-world event off Limitless: three division pages, 24 rows here and 575
# on the measured event, carrying 15 distinct decks that no single archetype describes.
#
# What only a browser can check is that the arbitration and the plan are one page. The admin reads
# a line per deck, picks what the proposal got wrong, and submits *that* — so the selects, the
# labels travelling beside them and the plan they will change all have to be inside one form, at
# both sides of the 768px breakpoint.
#
# Everything is stubbed at HttpFetcher, in this process: a system test boots Puma in-process, so
# the singleton this replaces is the one the server calls. Nothing here leaves the machine.
class TournamentEventImportTest < ApplicationSystemTestCase
  PAGES = {
    "https://limitlesstcg.com/tournaments/577" => "tournament_577_masters",
    "https://limitlesstcg.com/tournaments/577/SR" => "tournament_577_senior",
    "https://limitlesstcg.com/tournaments/577/JR" => "tournament_577_junior",
    "https://limitlesstcg.com/tournaments/577/decklists" => "tournament_577_masters_decklists",
    "https://limitlesstcg.com/tournaments/577/SR/decklists" => "tournament_577_senior_decklists"
  }.freeze
  # 577 publishes no Junior lists. A division with no block is ordinary, not an error.
  EMPTY_PAGE = "<html><body></body></html>".freeze

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    login_as @admin, scope: :user

    # The event publishes its own card pool code, "TEF-PBL", which is StandardPool#name byte for
    # byte; the fixtures hold TWM-ASC and TWM-POR, so without this every row is blocked for want
    # of an anchor and the screen has nothing to arbitrate.
    StandardPool.create!(
      first_card_set: CardSet.create!(code: "TEF", name: "Temporal Forces", release_date: Date.new(2024, 3, 22)),
      last_card_set: CardSet.create!(code: "PBL", name: "Pitch Black", release_date: Date.new(2026, 8, 1)),
      regulation_marks: %w[H I J], released_on: Date.new(2026, 8, 1), legal_on: Date.new(2026, 8, 15)
    )

    @original_http_fetcher_call = HttpFetcher.method(:call)
    HttpFetcher.define_singleton_method(:call) { |url|
      page = PAGES[url]
      page ? File.read(Rails.root.join("test/fixtures/files/limitless/#{page}.html")) : EMPTY_PAGE
    }
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call)
  end

  test "an admin previews a whole event, arbitrates one of its decks and confirms the run" do
    visit new_admin_standings_import_path

    select "One whole event — limitlesstcg.com/tournaments/<id>", from: "Source"
    fill_in "Limitless tournament id (event)", with: "577"
    click_on "Preview"

    # One event out of three division pages, with the plan underneath.
    assert_selector "h3", text: "Regional Baltimore, MD"
    assert_selector "[data-label=Division]", text: "senior"
    assert_selector "[data-label=Division]", text: "junior"

    # A line per distinct deck, named the way Limitless names it — and a deck the store already
    # answers for is shown as settled rather than asked about again.
    assert_selector "[data-label=Deck]", text: "Basic Box"
    assert_selector "[data-label=Proposal]", text: /confirmed/i, minimum: 1

    # The arbitration is the admin's, so the select has to be theirs to change.
    select archetypes(:standings_marker).name, from: "mappings[339][archetype_id]"

    # The form still carries what produced the plan, so nothing has to be retyped.
    assert_field "Limitless tournament id (event)", with: "577"

    assert_difference -> { LimitlessArchetypeMapping.count }, 1 do
      click_on "Confirm mappings and import"
      assert_current_path admin_imports_path
    end

    mapping = LimitlessArchetypeMapping.find_by(limitless_deck_id: 339, limitless_variant: nil)
    assert_equal archetypes(:standings_marker), mapping.archetype
    # The label is stored from the form, because #create never fetches and nothing else on the
    # POST could say what deck 339 is called.
    assert_equal "Basic Box", mapping.label
  end
end
