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
  def record_standing_for(archetype, index)
    tournament = Tournament.create!(
      name: "Quiet Cup #{index}", date: Date.new(2026, 4, 1) + index, tier: "league_cup",
      format: "standard", standard_pool: standard_pools(:twm_por), created_by: @user
    )
    field_list = Deck.create!(
      name: "Quiet Field List #{index}", shared: true, standard_pool: standard_pools(:twm_por)
    )
    tournament.standings.create!(
      player_name: "Quiet Player #{index}", division: "masters", placement: 1,
      archetype: archetype, deck: field_list, created_by: @user
    )
  end

  def catalogued_archetype(index)
    record_standing_for(quiet_archetype(index), index)
  end

  # Enough archetypes to push the catalog onto a second page, without any of them carrying a
  # standing — pagination is about the row count, not about what the rows say.
  def fill_a_page
    ArchetypesController::PER_PAGE.times { |i| quiet_archetype(100 + i) }
  end
end
