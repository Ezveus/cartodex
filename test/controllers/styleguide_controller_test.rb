require "test_helper"

class StyleguideControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "renders" do
    get styleguide_path

    assert_response :success
  end

  # The archetype sample block is the one place the two-select state can be seen at all — a real
  # archetype needs two pools *and* both venues to render it. Asserted rather than left to the
  # stub raising, because it will not: `Struct.new(keyword_init: true)` raises on an *extra*
  # keyword but stores `nil` for a *missing* one (measured), so a member added to
  # `MetagameScope::Result` and forgotten in `sg_metagame_scope` silently renders one select with
  # every test on this page still green.
  test "the archetype sample block renders both of its selects" do
    get styleguide_path

    assert_response :success
    assert_select "select[name=pool]", minimum: 1
    assert_select "select[name=venue]", minimum: 1
  end

  # The page renders the MCP token panel twice. With the panel's ids hardcoded,
  # both copies answered to #mcp-token and to the same #lifetime field, so the
  # second panel's label focused the first panel's select — invalid HTML, on the
  # page that is supposed to be the reference for it.
  test "the two MCP token panels carry distinct ids" do
    get styleguide_path

    assert_response :success
    ids = css_select("section.settings-section[id^='sg-mcp-token']").map { |section| section["id"] }

    assert_equal 2, ids.size, "sanity: the styleguide shows both states of the panel"
    assert_equal ids.uniq, ids, "duplicate section ids: #{ids.inspect}"

    field_ids = css_select("select[name=lifetime]").map { |select| select["id"] }

    assert_equal field_ids.uniq, field_ids, "duplicate lifetime field ids: #{field_ids.inspect}"
    assert_equal field_ids.sort, css_select("label[for^=sg-mcp-token]").map { |l| l["for"] }.sort,
      "each label must point at its own panel's select"
  end

  # General guard, independent of the MCP-token-specific check above: no two
  # elements anywhere on the reference page may share an id. Narrowing the
  # test above to the token panels lost this page-wide coverage; restored here
  # as its own assertion so it isn't accidentally scoped away again.
  test "no element on the styleguide page shares an id with another" do
    get styleguide_path

    assert_response :success
    ids = css_select("[id]").map { |element| element["id"] }

    assert_equal ids.uniq, ids, "duplicate ids on the page: #{ids.tally.select { |_, n| n > 1 }.keys}"
  end

  # The page renders the spotlight input and, separately, an open results panel. Rendering
  # ResultsView for the demo would have put a second turbo-frame#search_results on the page.
  test "the spotlight demo does not duplicate the results frame" do
    get styleguide_path

    assert_response :success
    assert_select "turbo-frame#search_results", count: 1
    ids = css_select("[role=option]").map { |option| option["id"] }

    assert_equal ids.uniq, ids, "duplicate option ids: #{ids.inspect}"
  end

  # The stale-anchor notice refuses to render on an unsaved record, so a plain Deck.new shows
  # nothing and the section would have looked like a styleguide entry while documenting an empty
  # div. Both branches are asserted because the component picks between them by comparing the
  # pools' release dates, and neither string may name a record type — a defect that shipped once.
  test "the styleguide renders both branches of the stale-anchor notice" do
    get styleguide_path

    assert_response :success
    notices = css_select(".standard-pool-notice")

    assert_equal 2, notices.size, "expected the stale branch and the wrong-pool branch"
    assert_match(/released since/, notices.first.text)
    assert_match(/is the pool that applies/, notices.last.text)
    notices.each do |notice|
      assert_no_match(/deck|tournament/i, notice.text,
        "the notice is shared by decks and tournaments, so it may not name either")
    end
  end

  # The deck row replaced the printing picker, and its demo is built from hand-made state structs
  # rather than from a deck: shown expanded, so every part of the row is on the page at once — the
  # summary line, a sub-row per printing in the deck with its ⇄, an owned printing at 0 copies and
  # the "Other printings" disclosure.
  test "the deck row demo shows an expanded card with every kind of sub-row" do
    get styleguide_path

    assert_response :success
    assert_select ".printing-picker-menu", count: 0
    assert_select ".sg-deck-row-demo li.deck-fingerprint" do
      assert_select ".deck-card-line .deck-card-total", text: "3"
      assert_select ".deck-printings-toggle[aria-expanded=true]"
      assert_select ".deck-printing-list:not([hidden]) > li.deck-printing-row .deck-card-item", count: 2
      assert_select ".deck-printing-move", minimum: 2
      assert_select ".deck-printing-owned", minimum: 3
      assert_select ".deck-card-collect", count: 1
      assert_select ".deck-printings-others-toggle[aria-expanded=false]"
    end
  end
end
