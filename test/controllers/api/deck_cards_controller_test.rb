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

  test "collection_copy refuses with nothing to back, with a free copy, and on a deck that is not physical" do
    asc = cards(:budew_asc)
    # A free copy: the real + is the move.
    @user.collections.find_by!(card: asc).update!(quantity: 1)
    @deck.deck_cards.create!(card: asc, quantity: 2, owned_copies: 0)
    post collection_copy_api_deck_card_path(@deck, asc), as: :json
    assert_response :unprocessable_entity
    assert_match(/free copy/, JSON.parse(response.body)["errors"].sole)

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
end
