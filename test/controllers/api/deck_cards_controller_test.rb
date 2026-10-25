require "test_helper"

class Api::DeckCardsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @card = cards(:honedge)
    @user.collections.find_or_initialize_by(card: @card).update!(quantity: 3)
    @deck = @user.decks.create!(name: "Phys", physical: true, standard_pool: standard_pools(:twm_por))
  end

  test "deck_card_json includes owned_copies and proxies" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 2)

    get api_deck_cards_path(@deck)

    json = JSON.parse(response.body)
    row = json.find { |r| r["card"]["id"] == @card.id }
    assert_equal 2, row["owned_copies"]
    assert_equal 1, row["proxies"]
  end

  test "create on a physical deck greedily backs reals via CardAdder" do
    post api_deck_cards_path(@deck),
      params: { deck_card: { card_id: @card.id, quantity: 2 } }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 2, json["quantity"]
    assert_equal 2, json["owned_copies"], "should back 2 reals from the 3 owned"
    assert_equal 0, json["proxies"]
  end

  test "update owned_copies routes through OwnedCopiesSetter" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { owned_copies: 1 } }, as: :json

    assert_response :success
    assert_equal 1, JSON.parse(response.body)["owned_copies"]
  end

  test "update owned_copies beyond availability returns 422" do
    @deck.deck_cards.create!(card: @card, quantity: 5, owned_copies: 0)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { owned_copies: 5 } }, as: :json

    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].present?
  end

  test "update quantity routes through DeckCardQuantitySetter and can remove" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 2)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { quantity: 0 } }, as: :json

    assert_response :success
    assert JSON.parse(response.body)["removed"]
    assert_nil @deck.deck_cards.find_by(card: @card)
  end

  # The deck page's steppers send a step, resolved against the stored row: a stale tab's "−" must
  # not reach the setter as an absolute value that reads as an increase.
  test "update quantity_delta steps from the stored quantity" do
    @deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 0)

    patch api_deck_card_path(@deck, @card), params: { deck_card: { quantity_delta: -1 } }, as: :json

    assert_response :success
    assert_equal [ 1, 0 ], JSON.parse(response.body).values_at("quantity", "owned_copies"),
                 "a step down drops a proxy and claims nothing"

    patch api_deck_card_path(@deck, @card), params: { deck_card: { quantity_delta: -1 } }, as: :json

    assert JSON.parse(response.body)["removed"]
    assert_nil @deck.deck_cards.find_by(card: @card)
  end

  test "update quantity_delta + claims greedily from the stored value" do
    @deck.deck_cards.create!(card: @card, quantity: 1, owned_copies: 0)

    patch api_deck_card_path(@deck, @card), params: { deck_card: { quantity_delta: 1 } }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [ 2, 2 ], json.values_at("quantity", "owned_copies")
  end

  test "update owned_copies_delta steps from the stored real count, and is refused past its bound" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 0)

    patch api_deck_card_path(@deck, @card), params: { deck_card: { owned_copies_delta: 1 } }, as: :json

    assert_response :success
    assert_equal 1, JSON.parse(response.body)["owned_copies"]

    @deck.deck_cards.find_by!(card: @card).update!(owned_copies: 0)
    patch api_deck_card_path(@deck, @card), params: { deck_card: { owned_copies_delta: -1 } }, as: :json

    assert_response :unprocessable_entity
    assert_equal 0, @deck.deck_cards.find_by!(card: @card).owned_copies
  end

  # The deck page edits cards in place, so a write that flips the deck's proxy state has to say so
  # in its own response — nothing else will tell the header before the next full load.

  test "update owned_copies reports the deck gaining proxies" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { owned_copies: 1 } }, as: :json

    assert_response :success
    assert JSON.parse(response.body)["deck"]["has_proxies"]
  end

  test "update owned_copies reports the deck losing its last proxy" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 1)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { owned_copies: 3 } }, as: :json

    assert_response :success
    assert_not JSON.parse(response.body)["deck"]["has_proxies"]
  end

  # Removing the deck's only unbacked card retires the badge, and the row is gone by then — this is
  # the case a body-less 204 could not report.
  test "removing the last unbacked card reports the deck losing its proxies" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 2, owned_copies: 0)

    patch api_deck_card_path(@deck, cards(:doublade)),
      params: { deck_card: { quantity: 0 } }, as: :json

    assert_response :success
    assert_not JSON.parse(response.body)["deck"]["has_proxies"]
  end

  test "a quantity bump that outruns the owned copies reports the new proxies" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 3)

    patch api_deck_card_path(@deck, @card),
      params: { deck_card: { quantity: 4 } }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 1, json["proxies"]
    assert json["deck"]["has_proxies"]
  end

  test "create reports the deck's proxy state" do
    post api_deck_cards_path(@deck),
      params: { deck_card: { card_id: @card.id, quantity: 4 } }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal 1, json["proxies"], "only 3 are owned"
    assert json["deck"]["has_proxies"]
  end

  # deck_card_json is shared with #index, which renders one row per card; folding the deck-wide
  # state into it would cost a query per row.
  test "index does not carry the deck state on every row" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 2)

    get api_deck_cards_path(@deck)

    assert_not JSON.parse(response.body).first.key?("deck")
  end

  # — The fingerprint payload (docs/superpowers/plans/2026-10-24-deck-fingerprint-rows.md, "API") —
  # Every write answers with what deck_rows_controller.js needs to redraw the card in place: the
  # card's state, its rows rendered by the page's own components, where they go, and the counts.

  test "a write answers with the card's state, its row and every section's counts" do
    @deck.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)

    patch api_deck_card_path(@deck, @card), params: { deck_card: { quantity: 2 } }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal 2, json["quantity"], "the row's own keys stay"
    assert_equal "honedge_fp", json["fingerprint_key"]
    assert_equal({ "has_proxies" => false, "total" => 2 }, json["deck"])

    fingerprint = json["fingerprint"]
    assert_equal [ "honedge_fp", "Honedge", 2, 2, 0 ],
                 fingerprint.values_at("key", "name", "quantity", "owned_copies", "proxies")
    printing = fingerprint["printings"].sole
    assert_equal({ "card_id" => @card.id, "set_name" => "POR", "set_number" => "56", "group" => "deck",
                   "quantity" => 2, "owned_copies" => 2, "proxies" => 0, "owned" => 3, "available" => 3,
                   "max_owned" => 2, "over_allocated" => false, "move_from_card_id" => nil,
                   "can_add_to_collection" => false }, printing)

    # B8, type view: the row key is the fingerprint key, and its HTML is the page's own row.
    row = json["rows"].sole
    assert_equal [ "honedge_fp", "pokemon" ], row.values_at("key", "section")
    html = Nokogiri::HTML5.fragment(row["html"])
    assert html.at_css("li.deck-fingerprint[data-row-key=honedge_fp][data-fingerprint-key=honedge_fp]")
    assert_equal "2", html.at_css(".deck-card-item .deck-card-qty").text

    section = json["sections"].sole
    assert_equal [ "pokemon", nil, 2, 1, [ "honedge_fp" ] ], section.values_at("key", "parent", "total", "unique", "rows")
    assert Nokogiri::HTML5.fragment(section["html"]).at_css("div.deck-section[data-section-key=pokemon] > ul.deck-card-list:empty")
  end

  # The search adds a card the deck has no section for yet: the answer carries that section's empty
  # shell and its parent's, and every section in page order so the browser can place them.
  # Writing a Pokémon still moves nothing in the Trainer and Energy headings, but the answer says
  # every section's counts: the page rewrites them all, and a section left out would keep whatever
  # it last showed.
  test "a write answers every section's counts, not only the sections it places a row in" do
    @deck.deck_cards.create!(card: @card, quantity: 1)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 2)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 4)

    patch api_deck_card_path(@deck, @card), params: { deck_card: { quantity_delta: 1 } }, as: :json

    sections = JSON.parse(response.body)["sections"].index_by { |section| section["key"] }
    assert_equal %w[pokemon trainer trainer-other energy], sections.keys
    assert_equal [ 2, 1 ], sections["pokemon"].values_at("total", "unique")
    assert_equal [ 2, 1, "trainer" ], sections["trainer-other"].values_at("total", "unique", "parent")
    assert_equal [ 4, 1 ], sections["energy"].values_at("total", "unique")
    assert_not sections["energy"].key?("html"), "a section holding no row of this answer carries no shell"
  end

  test "the answer's rows are the written card's alone, not its section's" do
    @deck.deck_cards.create!(card: @card, quantity: 1)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

    patch api_deck_card_path(@deck, @card), params: { deck_card: { quantity_delta: 1 } }, as: :json

    json = JSON.parse(response.body)
    assert_equal [ "honedge_fp" ], json["rows"].map { |row| row["key"] }
    assert_equal %w[doublade_fp honedge_fp], json["sections"].sole["rows"]
  end

  # The answer is read from a fresh load of the deck, its cards and their sets preloaded: the row it
  # hands back is the very row a reload renders, and its cost does not grow with the deck.
  test "the answer's row is the page's own row, at a cost that does not grow with the deck" do
    @deck.deck_cards.create!(card: @card, quantity: 1)
    write = -> { patch api_deck_card_path(@deck, @card, group: "set"), params: { deck_card: { quantity_delta: 1 } }, as: :json }

    # The first request signs in from the test helper; every later one reads the user off the
    # session, which costs a query of its own.
    write.call
    small = count_queries { write.call }
    answered = JSON.parse(response.body)["rows"].sole["html"]
    get deck_path(@deck, group: "set")
    rendered = css_select("li[data-row-key='printing:#{@card.id}']").sole.to_html
    assert_equal Nokogiri::HTML5.fragment(rendered).to_html, Nokogiri::HTML5.fragment(answered).to_html

    [ cards(:doublade), cards(:trainer_card), cards(:basic_psychic_energy), cards(:froakie_cri),
      cards(:bosss_orders_meg) ].each { |card| @deck.deck_cards.create!(card: card, quantity: 1) }
    large = count_queries { write.call }

    assert_equal small, large
  end

  test "adding a card the deck has no section for answers with its shell and the page order" do
    @deck.deck_cards.create!(card: @card, quantity: 1)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 1)
    boss = cards(:trainer_card)

    post api_deck_cards_path(@deck), params: { deck_card: { card_id: boss.id, quantity: 1 } }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal %w[pokemon trainer trainer-other energy], json["sections"].map { |section| section["key"] }
    pokemon, trainer, other, energy = json["sections"]

    # Only the sections this answer places a row in — and their parent — carry rows and a shell.
    [ pokemon, energy ].each { |section| assert_nil section["html"], section["key"] }
    assert_equal [ nil, nil, [] ], trainer.values_at("total", "unique", "rows")
    group = Nokogiri::HTML5.fragment(trainer["html"]).at_css("div.deck-section-group[data-section-key=trainer]")
    assert_equal "Trainer", group.at_css("> h2").text
    assert_empty group.css("[data-section-key], ul")

    assert_equal [ "trainer", 1, 1, [ boss.fingerprint_key ] ], other.values_at("parent", "total", "unique", "rows")
    shell = Nokogiri::HTML5.fragment(other["html"]).at_css("div.deck-section.deck-subsection[data-section-key=trainer-other]")
    assert_equal "Other (1 — 1 unique)", shell.at_css("> h3").text
    assert shell.at_css("> ul.deck-card-list:empty")
    assert_equal [ boss.fingerprint_key, "trainer-other" ], json["rows"].sole.values_at("key", "section")
  end

  # B8, set view: one row per printing in the deck, each placed in its own set's section.
  test "the set view's answer carries a row per printing in each one's set section" do
    pre = cards(:budew_pre)
    asc = cards(:budew_asc)
    @deck.deck_cards.create!(card: asc, quantity: 2)

    post api_deck_cards_path(@deck, group: "set"), params: { deck_card: { card_id: pre.id, quantity: 1 } }, as: :json

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "budew_shared", json["fingerprint_key"]
    assert_equal [ [ "printing:#{asc.id}", "set-#{asc.card_set_id}" ], [ "printing:#{pre.id}", "set-code-pre" ] ],
                 json["rows"].map { |row| row.values_at("key", "section") }
    assert_equal [ "set-#{asc.card_set_id}", "set-code-pre" ], json["sections"].map { |section| section["key"] }
    pre_section = json["sections"].last
    assert_equal [ 1, 1, "card", [ "printing:#{pre.id}" ] ], pre_section.values_at("total", "unique", "noun", "rows")
    assert Nokogiri::HTML5.fragment(pre_section["html"])
                   .at_css("div.deck-section.deck-set-section[data-section-key=set-code-pre][data-set-code=PRE]")
    row = Nokogiri::HTML5.fragment(json["rows"].last["html"])
    assert row.at_css("li.deck-printing-row[data-row-key='printing:#{pre.id}'][data-fingerprint-key=budew_shared] .deck-card-name")
  end

  # B8: DELETE now answers like every other write, because the page needs the section emptied.
  test "destroy answers with the card gone and its section dropped" do
    @deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    delete api_deck_card_path(@deck, @card), as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert json["removed"]
    assert_nil json["fingerprint"]
    assert_equal [], json["rows"]
    assert_equal [], json["sections"]
    assert_equal({ "has_proxies" => false, "total" => 0 }, json["deck"])
    assert_nil @deck.deck_cards.find_by(card: @card)
  end

  test "destroying one of two printings answers with the other's quantity" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)

    delete api_deck_card_path(@deck, cards(:budew_pre)), as: :json

    json = JSON.parse(response.body)
    assert json["removed"]
    assert_equal 2, json["fingerprint"]["quantity"]
    assert_equal [ "budew_shared" ], json["rows"].map { |row| row["key"] }
    assert_equal [ [ "pokemon", 2, 1 ] ], json["sections"].map { |section| section.values_at("key", "total", "unique") }
  end

  test "destroy 404s on a card the deck does not hold" do
    delete api_deck_card_path(@deck, @card), as: :json

    assert_response :not_found
  end

  test "a quantity set to zero answers with removed and the payload" do
    @deck.deck_cards.create!(card: @card, quantity: 1)

    patch api_deck_card_path(@deck, @card), params: { deck_card: { quantity: 0 } }, as: :json

    json = JSON.parse(response.body)
    assert json["removed"]
    assert_equal [ "honedge_fp", nil, [] ], json.values_at("fingerprint_key", "fingerprint", "rows")
  end

  # A body of the wrong shape is a malformed request, answered 400, never a NoMethodError 500.
  test "create answers 400 to a deck_card that is not a hash" do
    assert_no_difference "::DeckCard.count" do
      post api_deck_cards_path(@deck), params: { deck_card: "x" }, as: :json
    end
    assert_response :bad_request
  end

  test "update answers 400 to a deck_card that is not a hash" do
    @deck.deck_cards.create!(card: @card, quantity: 2)

    patch api_deck_card_path(@deck, @card), params: { deck_card: "x" }, as: :json

    assert_response :bad_request
    assert_equal 2, @deck.deck_cards.find_by!(card: @card).quantity
  end

  test "move answers 400 to a move that is not a hash" do
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)

    post move_api_deck_card_path(@deck, cards(:budew_pre)), params: { move: "x" }, as: :json

    assert_response :bad_request
    assert_equal 2, @deck.deck_cards.find_by!(card: cards(:budew_asc)).quantity
  end

  # — ⇄ —

  test "move takes one copy off the source printing and lands it on this one" do
    pre = cards(:budew_pre)
    asc = cards(:budew_asc)
    @deck.deck_cards.create!(card: asc, quantity: 3, owned_copies: 0)

    post move_api_deck_card_path(@deck, pre), params: { move: { from_card_id: asc.id } }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [ pre.id, 1 ], [ json["card"]["id"], json["quantity"] ]
    assert_equal 2, @deck.deck_cards.find_by!(card: asc).quantity
    printings = json["fingerprint"]["printings"].index_by { |printing| printing["card_id"] }
    assert_equal [ 2, 1 ], [ printings[asc.id]["quantity"], printings[pre.id]["quantity"] ]
    assert_equal 3, json["deck"]["total"]
    # Two printings in the deck now: one summary row whose sub-rows each carry a ⇄ to the other.
    row = Nokogiri::HTML5.fragment(json["rows"].sole["html"])
    assert_equal "3", row.at_css(".deck-card-total").text
    assert_equal [ "Move one copy here from ASC 16", "Move one copy here from PRE 4" ],
                 row.css(".deck-printing-move").map { |button| button["title"] }.sort
  end

  test "move refuses the same printing and a card that is not another printing" do
    asc = cards(:budew_asc)
    @deck.deck_cards.create!(card: asc, quantity: 2)

    post move_api_deck_card_path(@deck, asc), params: { move: { from_card_id: asc.id } }, as: :json
    assert_response :unprocessable_entity
    assert JSON.parse(response.body)["errors"].present?

    post move_api_deck_card_path(@deck, @card), params: { move: { from_card_id: asc.id } }, as: :json
    assert_response :unprocessable_entity
    assert_equal 2, @deck.deck_cards.find_by!(card: asc).quantity
  end

  test "move 404s when the source is not in the deck" do
    post move_api_deck_card_path(@deck, cards(:budew_pre)), params: { move: { from_card_id: cards(:budew_asc).id } }, as: :json

    assert_response :not_found
  end

  # A request of its own: the 404 above ends without writing the session, so a second request in
  # the same test would arrive signed out.
  test "move 404s on a deck that is not the member's" do
    theirs = users(:two).decks.create!(name: "Theirs", standard_pool: standard_pools(:twm_por))
    theirs.deck_cards.create!(card: cards(:budew_asc), quantity: 2)
    post move_api_deck_card_path(theirs, cards(:budew_pre)), params: { move: { from_card_id: cards(:budew_asc).id } }, as: :json
    assert_response :not_found
  end

  # The page leaves an over-allocated row's real "−" enabled, so the API has to take it: 3 real
  # with 1 owned used to answer 422 at every step.
  test "a real − on an over-allocated row is accepted" do
    @user.collections.find_by!(card: @card).update!(quantity: 1)
    @deck.deck_cards.create!(card: @card, quantity: 3).update_column(:owned_copies, 3)

    patch api_deck_card_path(@deck, @card), params: { deck_card: { owned_copies_delta: -1 } }, as: :json

    assert_response :success
    assert_equal [ 2, 1 ], JSON.parse(response.body).values_at("owned_copies", "proxies")
  end

  # A count is read as an integer or refused: `to_i` took 1.5 as 1 and "abc" as 0 (a 200 that did
  # something nobody asked for), and 10**20 reached the integer column and raised a 500.
  test "a step or a count that is not a sane integer is refused and writes nothing" do
    @deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 1)

    %i[quantity_delta owned_copies_delta quantity owned_copies].each do |key|
      [ 10**20, -10**20, 1.5, "1.5", "abc", "", nil, true, [ 1 ] ].each do |value|
        patch api_deck_card_path(@deck, @card), params: { deck_card: { key => value } }, as: :json

        assert_includes [ 400, 422 ], response.status, "#{key}: #{value.inspect} answered #{response.status}"
      end
    end
    assert_equal [ 2, 1 ], @deck.deck_cards.find_by!(card: @card).values_at(:quantity, :owned_copies)
  end

  test "a count sent as a decimal string, as a form posts it, is still taken" do
    @deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 1)

    patch api_deck_card_path(@deck, @card), params: { deck_card: { quantity_delta: "-1" } }

    assert_response :success
    assert_equal 1, @deck.deck_cards.find_by!(card: @card).quantity
  end

  test "create refuses a quantity that is not a sane integer" do
    [ 10**20, 1.5, "abc" ].each do |value|
      post api_deck_cards_path(@deck), params: { deck_card: { card_id: @card.id, quantity: value } }, as: :json

      assert_includes [ 400, 422 ], response.status, "#{value.inspect} answered #{response.status}"
    end
    assert_not @deck.deck_cards.exists?(card: @card)
  end

  # A refusal usually means the page is stale — another tab, or another deck claiming the copies —
  # so it answers the card's fresh state beside the reason, and the page redraws from it rather than
  # keeping an enabled real + and a collection offer the server has just refused.
  test "a refused write answers its reason and the card's fresh payload" do
    @deck.deck_cards.create!(card: @card, quantity: 3, owned_copies: 1)
    # Another deck claims the two free copies after the page rendered its real + enabled.
    other = @user.decks.create!(name: "Other", physical: true, standard_pool: standard_pools(:twm_por))
    other.deck_cards.create!(card: @card, quantity: 2, owned_copies: 2)

    patch api_deck_card_path(@deck, @card), params: { deck_card: { owned_copies_delta: 1 } }, as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal [ "owned_copies must be between 0 and 1" ], json["errors"]
    assert_equal "honedge_fp", json["fingerprint_key"]
    printing = json["fingerprint"]["printings"].sole
    assert_equal [ 1, 1, 1 ], printing.values_at("owned_copies", "available", "max_owned")
    html = Nokogiri::HTML5.fragment(json["rows"].sole["html"])
    assert html.at_css("[data-focus-key=real-plus-#{@card.id}][disabled]"), "the fresh row disables the real +"
    assert_equal({ "has_proxies" => true, "total" => 3 }, json["deck"])
  end

  test "a refused collection add answers the card's fresh payload too" do
    asc = cards(:budew_asc)
    @deck.deck_cards.create!(card: asc, quantity: 1, owned_copies: 1)

    post collection_copy_api_deck_card_path(@deck, asc), as: :json

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_equal [ "no proxy left to back" ], json["errors"]
    assert_equal [ "budew_shared" ], json["rows"].map { |row| row["key"] }
  end

  # A refusal the model raises is a refusal like any other: its reason and the card's fresh state.
  test "a create the model refuses answers its errors and the card's fresh payload" do
    @deck.deck_cards.create!(card: @card, quantity: 1)
    invalid = DeckCard.new(deck: @deck, card: @card, quantity: 0).tap(&:validate)
    Decks::CardAdder.define_singleton_method(:call) { |**| raise ActiveRecord::RecordInvalid, invalid }

    begin
      post api_deck_cards_path(@deck), params: { deck_card: { card_id: @card.id, quantity: 1 } }, as: :json
    ensure
      Decks::CardAdder.singleton_class.send(:remove_method, :call)
    end

    assert_response :unprocessable_entity
    json = JSON.parse(response.body)
    assert_includes json["errors"], "Quantity must be greater than 0"
    assert_equal "honedge_fp", json["fingerprint_key"]
    assert_equal [ "honedge_fp" ], json["rows"].map { |row| row["key"] }
  end

  # An add adds: a negative quantity went through Decks::CardAdder and took copies away (201, 3 → 2),
  # and 0 reached the model as a quantity of 0.
  test "create refuses a quantity below 1 and writes nothing" do
    @deck.deck_cards.create!(card: @card, quantity: 3)

    [ -1, 0 ].each do |quantity|
      post api_deck_cards_path(@deck), params: { deck_card: { card_id: @card.id, quantity: quantity } }, as: :json

      assert_response :unprocessable_entity
      assert_equal [ "quantity must be an integer between 1 and 9999" ], JSON.parse(response.body)["errors"]
    end
    assert_equal 3, @deck.deck_cards.find_by!(card: @card).quantity
  end

  # Each pair used to be resolved by taking the step and dropping the count without a word.
  test "a write carrying two counts is refused rather than resolved by precedence" do
    @deck.deck_cards.create!(card: @card, quantity: 2, owned_copies: 1)

    [
      { quantity_delta: 1, quantity: 1 },
      { owned_copies_delta: -1, owned_copies: 0 },
      { quantity: 3, owned_copies: 0 }
    ].each do |attributes|
      patch api_deck_card_path(@deck, @card), params: { deck_card: attributes }, as: :json

      assert_response :unprocessable_entity, attributes.inspect
      assert_match(/exactly one of/, JSON.parse(response.body)["errors"].sole)
    end
    assert_equal [ 2, 1 ], @deck.deck_cards.find_by!(card: @card).values_at(:quantity, :owned_copies)
  end

  # — "+ add to my collection and use it here" —

  test "collection_copy adds one copy to the collection and backs one proxy with it" do
    asc = cards(:budew_asc)
    @deck.deck_cards.create!(card: asc, quantity: 2, owned_copies: 0)

    assert_difference -> { @user.collections.where(card: asc).sum(:quantity) }, 1 do
      post collection_copy_api_deck_card_path(@deck, asc), as: :json
    end

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal [ 1, 1 ], json.values_at("owned_copies", "proxies")
    printing = json["fingerprint"]["printings"].find { |entry| entry["card_id"] == asc.id }
    assert_equal [ 1, 1 ], printing.values_at("owned", "owned_copies")
    assert json["deck"]["has_proxies"]
  end

  # With a free copy the click still adds one, then backs greedily: the free copy and the new one.
  test "collection_copy with a free copy adds one and backs every proxy it can" do
    asc = cards(:budew_asc)
    @user.collections.find_by!(card: asc).update!(quantity: 1)
    @deck.deck_cards.create!(card: asc, quantity: 3, owned_copies: 0)

    assert_difference -> { @user.collections.where(card: asc).sum(:quantity) }, 1 do
      post collection_copy_api_deck_card_path(@deck, asc), as: :json
    end

    assert_response :success
    assert_equal [ 2, 1 ], JSON.parse(response.body).values_at("owned_copies", "proxies")
  end

  test "collection_copy refuses with nothing to back and on a deck that is not physical" do
    asc = cards(:budew_asc)
    @user.collections.find_by!(card: asc).update!(quantity: 1)

    # No proxy left to back.
    @deck.deck_cards.create!(card: @card, quantity: 1, owned_copies: 1)
    post collection_copy_api_deck_card_path(@deck, @card), as: :json
    assert_response :unprocessable_entity

    live = @user.decks.create!(name: "Live", standard_pool: standard_pools(:twm_por))
    live.deck_cards.create!(card: asc, quantity: 1)
    post collection_copy_api_deck_card_path(live, asc), as: :json
    assert_response :unprocessable_entity
    assert_equal 1, @user.collections.find_by!(card: asc).quantity, "no refusal may write the collection"
  end

  test "collection_copy 404s on a card the deck does not hold" do
    post collection_copy_api_deck_card_path(@deck, cards(:budew_asc)), as: :json

    assert_response :not_found
  end

  # — "Other printings", fetched the first time the page opens them —

  def reprint(card, set_name:, set_number:, card_set: nil)
    Card.create!(
      name: card.name, card_type: card.card_type, hp: card.hp, type_symbol: card.type_symbol,
      retreat_cost: card.retreat_cost, stage: card.stage, card_set: card_set,
      set_name: set_name, set_number: set_number, rarity: "Common"
    ).tap { |twin| twin.update_column(:fingerprint, card.fingerprint) }
  end

  # ASC 16 is in the deck; TWM 3 is owned; POR 3 (2026) and PRE 4 (no imported set) are neither.
  def budew_with_other_printings
    asc = cards(:budew_asc)
    twm = reprint(asc, set_name: "TWM", set_number: "3", card_set: card_sets(:twm))
    reprint(asc, set_name: "POR", set_number: "3", card_set: card_sets(:por))
    @user.collections.create!(card: twm, quantity: 1)
    @deck.deck_cards.create!(card: asc, quantity: 2)
    asc
  end

  # The owned TWM 3 is rendered with the page, in the expansion itself: the answer is only the
  # printings nobody holds — neither in the deck nor in the collection.
  test "other_printings answers the sub-rows of the printings neither in the deck nor owned" do
    asc = budew_with_other_printings

    get other_printings_api_deck_card_path(@deck, asc), as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_equal "budew_shared", json["fingerprint_key"]
    html = Nokogiri::HTML5.fragment(json["html"])
    rows = html.element_children
    assert rows.all? { |node| node.matches?("li.deck-printing-row") }, "the answer is the sub-rows alone"
    assert_equal [ "POR 3", "PRE 4" ], rows.map { |row| row.at_css(".deck-card-set").text }
    assert_empty html.css(".deck-printing-owned")
    assert_empty html.css("[data-row-key]"), "a sub-row is no row of its own"
    rows.each do |row|
      assert_equal "Move one copy here from ASC 16", row.at_css("button.deck-printing-move")["title"]
      # A printing the deck does not play has no copy to take away.
      assert row.at_css("[data-focus-key^=qty-minus-][disabled]")
    end
  end

  # Keyed on the card's fingerprint, so any printing of it names the list — the page sends its row's
  # display card, which a write elsewhere may have taken out of the deck since.
  test "other_printings answers for any printing of a card the deck plays" do
    budew_with_other_printings

    get other_printings_api_deck_card_path(@deck, cards(:budew_pre)), as: :json

    assert_response :success
    assert_equal "budew_shared", JSON.parse(response.body)["fingerprint_key"]
  end

  test "other_printings 404s on a card the deck does not play in any printing" do
    budew_with_other_printings

    get other_printings_api_deck_card_path(@deck, cards(:doublade)), as: :json

    assert_response :not_found
  end

  test "other_printings 404s on another member's deck, and a visitor is refused" do
    theirs = users(:two).decks.create!(name: "Theirs", standard_pool: standard_pools(:twm_por))
    theirs.deck_cards.create!(card: cards(:budew_asc), quantity: 2)

    get other_printings_api_deck_card_path(theirs, cards(:budew_asc)), as: :json
    assert_response :not_found

    sign_out @user
    get other_printings_api_deck_card_path(theirs, cards(:budew_asc)), as: :json
    assert_response :unauthorized
  end

  # Every printing outside the deck in a set of its own, half of them owned (and so not in the
  # answer): a per-printing read of `card_set` or of the collection would issue distinct SQL per row.
  test "other_printings costs the same however many printings it renders" do
    asc = budew_with_other_printings
    get other_printings_api_deck_card_path(@deck, asc), as: :json
    small = count_queries { get other_printings_api_deck_card_path(@deck, asc), as: :json }

    4.times do |index|
      set = CardSet.create!(code: "RP#{index}", name: "Reprint #{index}", release_date: Date.new(2020, 1, index + 1))
      twin = reprint(asc, set_name: set.code, set_number: index.to_s, card_set: set)
      @user.collections.create!(card: twin, quantity: 1) if index.even?
    end
    large = count_queries { get other_printings_api_deck_card_path(@deck, asc), as: :json }

    assert_equal 4, Nokogiri::HTML5.fragment(JSON.parse(response.body)["html"]).css("li.deck-printing-row").size
    assert_equal small, large, "query count grew with the printings rendered: #{small} -> #{large}"
  end

  # A write re-renders the whole card's row, and the page puts back every disclosure that was open
  # in it: the answer renders the owned printings as the page does, and the other printings outright
  # rather than pending, so a list the member had opened comes back open and current, and one never
  # opened needs no fetch later.
  test "a write's row renders the other printings rather than leaving them to be fetched" do
    asc = budew_with_other_printings

    patch api_deck_card_path(@deck, asc), params: { deck_card: { quantity_delta: 1 } }, as: :json

    assert_response :success
    html = Nokogiri::HTML5.fragment(JSON.parse(response.body)["rows"].sole["html"])
    expansion = html.at_css("ul#deck-printings-budew_shared")
    assert_equal [ "TWM 3" ], expansion.css("> li.deck-printing-row .deck-card-set").map(&:text)
    list = html.at_css("ul#deck-printings-others-budew_shared[hidden]")
    assert_equal [ "POR 3", "PRE 4" ], list.css("> li.deck-printing-row .deck-card-set").map(&:text)
    assert_nil list["data-deck-rows-pending"]
    toggle = html.at_css(".deck-printings-others-toggle")
    assert_equal "Other printings (2)", toggle.text
    assert_equal "disclosure#toggle", toggle["data-action"], "nothing left to fetch"
  end
end
