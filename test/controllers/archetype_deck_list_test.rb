require "test_helper"

# /archetypes/:slug is the archetype's deck list, and /archetypes/:slug/analysis its metagame
# report. ArchetypesControllerTest carries the report's own tests (moved onto the analysis path);
# this file carries everything the move itself decided: what the front page lists and how, what
# the two pages link to, the legacy redirect, and the policy each action asks.
#
# Membership (Archetypes::DeckList's rule A) is proved in its service test; here it is only
# rendered.
class ArchetypeDeckListTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @archetype = fresh_archetype("Listed Archetype")
  end

  test "the deck list is the first thing on the page, and the report is not on it" do
    record(@archetype, deck: field_list(name: "Listed Field List"))

    get archetype_path(@archetype)

    assert_response :success
    assert_select "h1", text: @archetype.name
    assert_select ".archetype-public-decks .deck-item h2", text: "Listed Field List"
    assert_select "a[href=?]", analysis_archetype_path(@archetype), text: "Analysis"
    # Nothing of the report survives on the front page.
    assert_select ".archetype-card-row", count: 0
    assert_select "select[name=pool]", count: 0
    assert_no_match "Recorded in Cartodex", response.body
  end

  test "a field list is captioned with its event inside its own link, and names no archetype badge" do
    tagged_elsewhere = fresh_archetype("Detector Guess")
    record(@archetype, deck: field_list(name: "Captioned List", archetype: tagged_elsewhere),
                       event: event(name: "EUIC 2026"), placement: 12)
    member_deck(users(:two), @archetype, shared: true, name: "Member List")

    get archetype_path(@archetype)

    cards = Nokogiri::HTML5(response.body).css(".deck-item")
    captioned = cards.find { |node| node.at_css("h2")&.text == "Captioned List" }
    assert_equal "EUIC 2026 — 12th · Masters", captioned.at_css("a.deck-item-link p.deck-caption")&.text
    # Scoped to the deck cards: the header's own badge names the archetype too.
    cards.each do |node|
      assert_nil node.at_css(".deck-badges .badge-archetype"), "a deck card on this page carries an archetype badge"
      assert_no_match(/#{tagged_elsewhere.name}|#{@archetype.name}/, node.at_css(".deck-badges").text)
    end
  end

  test "a signed-in reader's own decks come first, private and shared, and leave the public list" do
    other = fresh_archetype("Another Archetype")
    member_deck(users(:one), @archetype, shared: false, name: "Zeta", physical: true)
    member_deck(users(:one), @archetype, shared: true, name: "Alpha")
    member_deck(users(:one), other, shared: true, name: "Beta")
    record(@archetype, deck: field_list(name: "Public List"))
    sign_in users(:one)

    get archetype_path(@archetype)

    doc = Nokogiri::HTML5(response.body)
    sections = doc.css("section.archetype-decks").map { |node| node.at_css("h2").text }
    assert_equal [ "Your decks", "Decks" ], sections

    own = doc.css(".archetype-own-decks .deck-item").map { |n| [ n.at_css("h2").text, n.at_css(".deck-caption")&.text ] }
    assert_equal [ [ "Alpha", "Shared" ], [ "Zeta", "Private" ] ], own
    assert_equal [ "Public List" ], doc.css(".archetype-public-decks .deck-item h2").map(&:text)

    # public_listing: true for the reader's own decks too — no collection badges, no compare
    # checkbox whose controller this page does not carry.
    assert_select ".deck-item .deck-compare-checkbox", count: 0
    assert_select ".archetype-own-decks .deck-badges", text: /Physical/, count: 0
  end

  test "a visitor, and a member with no deck of this archetype, get no \"Your decks\" section" do
    member_deck(users(:one), @archetype, shared: false, name: "Private One")
    record(@archetype, deck: field_list)

    get archetype_path(@archetype)
    assert_select ".archetype-own-decks", count: 0
    assert_select ".deck-item h2", text: "Private One", count: 0

    sign_in users(:two)
    get archetype_path(@archetype)
    assert_select ".archetype-own-decks", count: 0
    assert_select ".deck-item h2", text: "Private One", count: 0
  end

  test "an empty list points at the analysis only when the archetype has recorded results" do
    get archetype_path(@archetype)
    assert_select ".empty-state", text: "No public deck of this archetype yet."
    assert_select ".empty-state a", count: 0

    record(@archetype) # a placement, with no list typed
    get archetype_path(@archetype)
    assert_select ".empty-state a[href=?]", analysis_archetype_path(@archetype)
  end

  # Full visits, not a frame: a frame-navigated action under a rate_limit swallows its 429.
  test "the pager navigates the page, clamps its number, and survives a malformed one" do
    25.times { |i| record(@archetype, deck: field_list(name: "Paged #{i}")) }

    get archetype_path(@archetype, page: 99)
    assert_response :success
    assert_select ".archetype-public-decks .deck-item", count: 1
    # The layout carries frames of its own; what matters is that none holds the list.
    assert_select "turbo-frame .cards-pagination", count: 0
    assert_select "turbo-frame .deck-item", count: 0
    assert_select ".cards-pagination a", minimum: 1
    assert_select ".cards-pagination a[data-turbo-action]", count: 0
    assert_select ".cards-pagination a[href=?]", archetype_path(@archetype, page: 1)

    get archetype_path(@archetype, page: [ "1" ])
    assert_response :success
    assert_select ".archetype-public-decks .deck-item", count: 24
  end

  test "each report parameter alone sends the front page on to the analysis, carrying all it was given" do
    ArchetypesController::LEGACY_REPORT_PARAMS.each do |name|
      get archetype_path(@archetype, name => "x")

      assert_response :moved_permanently
      assert_equal analysis_archetype_url(@archetype, name => "x"), response.location
    end

    get archetype_path(@archetype, pool: "1", venue: "paper", group: "role", page: "2")
    location = URI(response.location)
    assert_equal analysis_archetype_path(@archetype), location.path
    assert_equal({ "pool" => "1", "venue" => "paper", "group" => "role" }, Rack::Utils.parse_query(location.query))
  end

  test "a malformed report parameter still redirects rather than raising" do
    [ { pool: [ "junk" ] }, { venue: [ "x" ] }, { group: { "a" => "b" } } ].each do |params|
      get archetype_path(@archetype, params)

      assert_response :moved_permanently
      assert_equal analysis_archetype_path(@archetype), URI(response.location).path
      assert_includes response.location, params.keys.first.to_s
    end
  end

  # A URL helper reads `host` and `only_path` out of the options it is given.
  test "the redirect never carries a parameter it was not built for" do
    # Spelled as a string: archetype_path would read these options itself.
    get "/archetypes/#{@archetype.slug}?pool=1&only_path=false&host=evil.example&id=other"

    location = URI(response.location)
    assert_equal "www.example.com", location.host
    assert_equal analysis_archetype_path(@archetype), location.path
    assert_equal({ "pool" => "1" }, Rack::Utils.parse_query(location.query))
  end

  test "a page parameter alone renders the list" do
    get archetype_path(@archetype, page: 2)

    assert_response :success
  end

  test "the front page advertises the archetype's banner and itself as canonical" do
    get archetype_path(@archetype)

    doc = Nokogiri::HTML(response.body)
    assert_includes doc.at_css("meta[property='og:image']")["content"], "/og/archetypes/#{@archetype.slug}"
    assert_equal archetype_url(@archetype.slug), doc.at_css("meta[property='og:url']")["content"]
  end

  test "the analysis links back to the list, and its report controls stay on the analysis" do
    parent = fresh_archetype("Parent Archetype")
    @archetype.update!(parent: parent)
    child = fresh_archetype("Child Archetype")
    child.update!(parent: @archetype)
    2.times { |i| record(@archetype, deck: listed_field_list(i), event: event(pool: i.zero? ? :twm_por : :twm_asc)) }

    get analysis_archetype_path(@archetype)

    assert_response :success
    assert_select "a[href=?]", archetype_path(@archetype), text: "Decks"
    assert_select "form.deck-filters[action=?]", analysis_archetype_path(@archetype)
    modes = css_select("a.archetype-report-mode").map { |a| a["href"] }
    assert_equal 2, modes.size
    modes.each { |href| assert href.start_with?("#{analysis_archetype_path(@archetype)}?"), href }
    # Identity's links go to another archetype, whose front page is its list.
    assert_select "a[href=?]", archetype_path(parent)
    assert_select "a[href=?]", archetype_path(child)
    assert_select "a[href=?]", analysis_archetype_path(parent), count: 0
    assert_select "a[href=?]", analysis_archetype_path(child), count: 0
  end

  test "the analysis resolves by slug only, and answers the static 404 otherwise" do
    get analysis_archetype_path(id: @archetype.id)
    assert_response :not_found

    get "/archetypes/no-such-archetype/analysis"
    assert_response :not_found
    assert_equal Rails.public_path.join("404.html").read, response.body
  end

  # Both predicates answer `true`, so only a refusal tells them apart.
  test "each page asks its own policy question, and the redirect waits for the answer" do
    with_refused(:analysis?) do
      get analysis_archetype_path(@archetype)
      assert_response :not_found
      get archetype_path(@archetype)
      assert_response :success
    end

    with_refused(:show?) do
      get archetype_path(@archetype, pool: "1")
      assert_response :not_found
      get analysis_archetype_path(@archetype)
      assert_response :success
    end
  end

  # Counted outside the query cache: every field list below shares nothing with another — its own
  # archetype tag, event and pool alternate — but a repeated identical SELECT would be served from
  # the cache and SQLCounter would not see it (the trap docs/architecture/deck-odds.md records).
  test "the front page costs the same whatever it lists, to a visitor and to an owner" do
    grow(2)
    get archetype_path(@archetype) # warm
    small = uncached_count { get archetype_path(@archetype) }
    grow(8, from: 2)
    large = uncached_count { get archetype_path(@archetype) }

    assert_select ".archetype-public-decks .deck-item", count: 10
    assert_equal small, large, "the visitor's page grew with the list: #{small} -> #{large}"
    # Measured at 11: the archetype and its member card, the count, the page, then one preload
    # each for the pools, their bounds (both in one card_sets read), the deck cards, the decks'
    # own archetypes and their member cards, the standings and their events. Every archetype here
    # has no secondary card, which is what leaves the secondary preloads without a query to issue.
    assert_equal 11, small, "the visitor's page moved off its measured cost"

    sign_in users(:one)
    member_deck(users(:one), @archetype, shared: true, name: "Own 0")
    get archetype_path(@archetype)
    few = uncached_count { get archetype_path(@archetype) }
    (1..4).each { |i| member_deck(users(:one), @archetype, shared: i.odd?, name: "Own #{i}", pool: i.odd? ? :twm_asc : :twm_por) }
    many = uncached_count { get archetype_path(@archetype) }

    assert_select ".archetype-own-decks .deck-item", count: 5
    # At most equal, not equal: the preloader reuses records the public list already loaded — the
    # decks' pools and archetypes — so four more own decks measured 18 -> 16. An N+1 is the only
    # way up.
    assert_operator many, :<=, few, "the owner's page grew with their own decks: #{few} -> #{many}"
  end

  private

  def fresh_archetype(name)
    @next = @next.to_i + 1
    card = Card.create!(name: "List Pokémon #{@next}", set_name: "LP#{@next}", set_number: "1",
                        card_type: "Pokémon", hp: 60, rarity: "Common", type_symbol: "Colorless",
                        retreat_cost: 1)
    Archetype.create!(primary_card: card, name: name, custom_name: "1")
  end

  def event(name: nil, pool: :twm_por, date: Date.new(2026, 4, 1))
    @next = @next.to_i + 1
    Tournament.create!(name: name || "List Cup #{@next}", date: date, tier: "league_cup", format: "standard",
                       standard_pool: standard_pools(pool), created_by: users(:one))
  end

  def record(archetype, deck: nil, event: event(), placement: nil)
    @next = @next.to_i + 1
    event.standings.create!(player_name: "List Player #{@next}", division: "masters", placement: placement,
                            archetype: archetype, deck: deck, created_by: users(:one))
  end

  def field_list(name: nil, archetype: nil, pool: :twm_por)
    @next = @next.to_i + 1
    Deck.create!(name: name || "List Field List #{@next}", shared: true, archetype: archetype,
                 standard_pool: standard_pools(pool))
  end

  # A field list holding one card, so the report has a list to speak for and renders its controls.
  def listed_field_list(index)
    deck = field_list
    card = Card.create!(name: "Listed Card #{index}", set_name: "LC#{index}", set_number: "1",
                        card_type: "Pokémon", hp: 60, rarity: "Common", type_symbol: "Colorless",
                        retreat_cost: 1)
    deck.deck_cards.create!(card: card, quantity: 2)
    deck
  end

  def member_deck(user, archetype, shared:, name:, physical: false, pool: :twm_por)
    Deck.create!(user: user, name: name, shared: shared, physical: physical, archetype: archetype,
                 standard_pool: standard_pools(pool))
  end

  def grow(count, from: 0)
    (from...(from + count)).each do |i|
      tag = fresh_archetype("Tag #{i}")
      pool = i.odd? ? :twm_asc : :twm_por
      record(@archetype, deck: field_list(archetype: tag, pool: pool), event: event(pool: pool), placement: i + 1)
    end
  end

  def uncached_count(&block)
    ActiveRecord::Base.uncached { capture_queries(&block).size }
  end

  def with_refused(predicate)
    ArchetypePolicy.alias_method(:"original_#{predicate}", predicate)
    ArchetypePolicy.define_method(predicate) { false }
    yield
  ensure
    ArchetypePolicy.alias_method(predicate, :"original_#{predicate}")
    ArchetypePolicy.remove_method(:"original_#{predicate}")
  end
end
