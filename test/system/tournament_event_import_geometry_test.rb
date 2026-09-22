require "application_system_test_case"

# The mapping table at phone width. A deck whose representative list could not be read says so with
# the page and the rank in the message — and a URL is one unbreakable token inside an inline-block
# badge, whose min-content width is therefore the token's. Measured before the fix: nine of the
# fifteen lines this capture produces pushed the document to 487px against a 390px viewport, and
# they were the only elements on the page to overflow it at all.
#
# Text assertions cannot see this: the badge renders either way, in the wrong place.
class TournamentEventImportGeometryTest < ApplicationSystemTestCase
  drive_at 390, 844

  PAGES = {
    "https://limitlesstcg.com/tournaments/577" => "tournament_577_masters",
    "https://limitlesstcg.com/tournaments/577/SR" => "tournament_577_senior",
    "https://limitlesstcg.com/tournaments/577/JR" => "tournament_577_junior",
    "https://limitlesstcg.com/tournaments/577/decklists" => "tournament_577_masters_decklists",
    "https://limitlesstcg.com/tournaments/577/SR/decklists" => "tournament_577_senior_decklists"
  }.freeze
  EMPTY_PAGE = "<html><body></body></html>".freeze

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    login_as @admin, scope: :user

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

  teardown { HttpFetcher.define_singleton_method(:call, @original_http_fetcher_call) }

  test "no mapping line pushes the document past the viewport at 390px" do
    visit preview_admin_standings_imports_path(source: "event", tournament_id: "577")
    assert_selector ".standings-import-mappings"

    measured = evaluate_script(<<~JS)
      (() => {
        const badges = [ ...document.querySelectorAll(".standings-import-mappings .badge") ];
        return {
          innerWidth: window.innerWidth,
          scrollWidth: document.documentElement.scrollWidth,
          badges: badges.length,
          widest: Math.max(0, ...badges.map((b) => b.getBoundingClientRect().right)),
          overflowing: badges.filter((b) => b.getBoundingClientRect().right > window.innerWidth).length
        };
      })()
    JS

    assert_operator measured["badges"], :>, 0, "the capture must produce mapping lines to measure"
    assert_equal 0, measured["overflowing"],
      "#{measured["overflowing"]} of #{measured["badges"]} badges reach past #{measured["innerWidth"]}px " \
      "(widest right edge #{measured["widest"]})"
    assert_operator measured["scrollWidth"], :<=, measured["innerWidth"],
      "the document scrolls sideways at #{measured["innerWidth"]}px"
  end
end
