require "test_helper"

# The card page's "Played in recorded lists" section, through the real request. The fixtures'
# standings carry no deck, so every pre-existing card-page test renders the empty state — the tree
# path, its links and its venue param are reached only here.
class CardUsageTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @card = Card.create!(name: "Usage Request Item", card_type: "Trainer", set_name: "CUR",
                         set_number: "1", rarity: "Uncommon", subtype: "Item")
    @archetype = Archetype.create!(primary_card: @card)
    pool = standard_pools(:twm_por)
    @paper = Tournament.create!(name: "Usage Request Paper", date: Date.new(2026, 6, 1), format: "standard",
                                standard_pool: pool, tier: "regional", created_by: users(:one))
    @online = Tournament.create!(name: "Usage Request Online", date: Date.new(2026, 6, 2), format: "standard",
                                 standard_pool: pool, tier: "other", online: true, created_by: users(:one))
    record(@paper, @card => 2)
    record(@paper, other_card => 1)
    record(@online, @card => 1)
  end

  test "a visitor and a member both get the tree, linked to the analysis it reproduces" do
    [ nil, users(:one) ].each do |user|
      sign_in user if user
      get card_path(@card)

      assert_response :success
      assert_select "#usage .card-usage-archetype > details > summary .card-usage-figures",
                    text: "All formats · 66.7% · 2 of 3 lists · 1-2 copies · most often 1 / 2 — tied"
      assert_select "#usage .card-usage-archetype a[href=?]",
                    analysis_archetype_path(@archetype, pool: "all")
      assert_select "#usage .card-usage-tournament", count: 2
      assert_select "#usage select[name=venue]"
      sign_out user if user
    end
  end

  test "a venue narrows the tree and is carried into every link" do
    get card_path(@card, venue: "online")

    assert_response :success
    assert_select "#usage select[name=venue] option[selected][value=online]"
    assert_select "#usage .card-usage-archetype > details > summary .card-usage-figures",
                  text: "All formats · 100% · 1 of 1 list · 1 copy"
    assert_select "#usage .card-usage-link" do |anchors|
      assert anchors.all? { |anchor| anchor["href"].include?("venue=online") }, anchors.map { _1["href"] }.inspect
    end
  end

  test "a malformed venue falls back to every venue rather than failing" do
    get card_path(@card, venue: [ "online" ])
    assert_response :success
    assert_select "#usage select[name=venue] option[selected][value=all]"

    get "#{card_path(@card)}?venue[x]=y"
    assert_response :success
  end

  # card_allocation_controller.js reloads this page on every collection +/- only to extract the
  # `#card-allocation` frame. Measured on the widest card, the tree was 466 KB of that 474 KB
  # response, so a frame request skips it — and its aggregate query — entirely.
  test "the allocation frame's refresh does not compute the tree" do
    sign_in users(:one)

    queries = capture_queries do
      get card_path(@card), headers: { "Turbo-Frame" => Cards::AllocationSection::FRAME_ID }
    end

    assert_response :success
    assert_select "#card-allocation"
    assert_select "#usage", count: 0
    assert_empty queries.grep(/tournament_standings/)

    get card_path(@card)
    assert_select "#usage"
  end

  private

  def other_card
    Card.create!(name: "Usage Request Filler", card_type: "Trainer", set_name: "CUR",
                 set_number: "2", rarity: "Uncommon", subtype: "Item")
  end

  def record(event, copies_by_card)
    deck = Deck.create!(name: "Usage list #{SecureRandom.hex(3)}", user: nil, shared: true,
                        physical: false, format: "glc")
    copies_by_card.each { |card, copies| deck.deck_cards.create!(card: card, quantity: copies) }
    TournamentStanding.create!(tournament: event, archetype: @archetype, deck: deck,
                               player_name: "Player #{SecureRandom.hex(3)}",
                               division: event.online? ? "open" : "masters", created_by: users(:one))
  end
end
