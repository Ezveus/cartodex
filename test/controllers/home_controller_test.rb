require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
  end

  test "dashboard renders the spotlight search" do
    get dashboard_path

    assert_response :success
    assert_select "form[action=?] input[name=q][role=combobox]", search_path
  end

  test "the spotlight form targets the results frame" do
    get dashboard_path

    assert_select "form[data-turbo-frame=search_results]"
  end

  test "the spotlight ships an empty results frame" do
    get dashboard_path

    assert_select "turbo-frame#search_results"
    assert_select "a[role=option]", count: 0
  end

  test "the combobox points at the frame it controls" do
    get dashboard_path

    assert_select "input[role=combobox][aria-controls=search_results][aria-expanded=false]"
  end

  test "the spotlight passes the service's minimum query length to Stimulus" do
    get dashboard_path

    assert_select "[data-dashboard-search-min-length-value=?]", Search::Global::MIN_QUERY_LENGTH.to_s
  end

  test "a visitor gets search, a showcase and a way in — and nothing personal" do
    sign_out @user
    shared = decks(:two)
    shared.update!(user: users(:two), shared: true, name: "Showcased")

    get dashboard_path

    assert_response :success
    assert_select ".spotlight"
    assert_select ".dashboard-showcase-deck-name", text: "Showcased"
    assert_select ".dashboard-showcase .badge-format"
    assert_select "a[href=?]", new_user_session_path
    assert_select ".dashboard-card", count: 0
    assert_select "#scanner-modal", count: 0
    assert_select "h1", text: /@/, count: 0
    # The decks Stimulus controller fetches /api/decks on connect; a visitor must not carry it.
    assert_select "[data-controller~=decks]", count: 0
  end

  test "the showcase never lists a private deck" do
    sign_out @user
    decks(:two).update!(user: users(:two), shared: false, name: "Private")

    get dashboard_path

    assert_select ".dashboard-showcase-deck-name", text: "Private", count: 0
  end

  test "the showcase is loaded once, not asked about and then loaded" do
    sign_out @user
    decks(:two).update!(user: users(:two), shared: true)

    sql = capture_queries { get dashboard_path }

    assert_response :success
    # The view asks `any?` before iterating; on an unloaded relation that is a
    # SELECT 1 … LIMIT 1 beside the query that follows it, on the app's landing page.
    assert_empty sql.grep(/SELECT 1 AS one/),
      "expected no existence probe beside the showcase query"
  end

  # Same shape as the deck index's guard: each showcased deck gets a pool of its own, because
  # decks sharing a pool id issue identical SQL that the per-request query cache serves and
  # count_queries does not count — which would hide the very N+1 this is for. The badge on each
  # showcase row names the pool, and StandardPool#name reads both of its card-set bounds.
  test "the showcase costs the same whether it lists one deck or many" do
    sign_out @user
    Deck.update_all(shared: false)
    users(:two).decks.create!(name: "Shared 0", shared: true, standard_pool: pool_of_its_own(0))

    get dashboard_path # warm the session and the set/pool lookups

    small = count_queries { get dashboard_path }

    (1..4).each { |i| users(:two).decks.create!(name: "Shared #{i}", shared: true, standard_pool: pool_of_its_own(i)) }

    large = count_queries { get dashboard_path }

    assert_response :success
    assert_equal small, large, "query count grew with the showcase: #{small} -> #{large}"
  end

  test "root is the dashboard for everyone" do
    sign_out @user
    get root_path
    assert_response :success

    sign_in users(:one)
    get root_path
    assert_response :success
    assert_select ".dashboard-card"
  end

  private

  # A pool nothing else shares, so that N showcased decks have N pool names to resolve.
  # Dated well before twm_por, so StandardPool.current is untouched.
  def pool_of_its_own(index)
    set = CardSet.create!(code: "S#{index}", name: "Showcase Set #{index}", release_date: Date.new(2025, 1, 1))
    StandardPool.create!(
      first_card_set: card_sets(:twm), last_card_set: set, regulation_marks: %w[G H],
      released_on: Date.new(2025, 1, 1) + index, legal_on: Date.new(2025, 2, 1) + index
    )
  end
end
