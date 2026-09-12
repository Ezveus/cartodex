require "test_helper"

# What the page says, with no browser involved. Rendered through a request rather than a bare `.call`
# because the header uses link_to and the _path helpers, which resolve through a view_context that
# does not exist outside one — see Ui::ArchetypeBadgeTest, which documents the trap.
class Decks::Odds::PageViewTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    sign_in @user
    @deck = @user.decks.create!(name: "Odds", standard_pool: standard_pools(:twm_por))
  end

  def render_page(deck = @deck)
    get odds_deck_path(deck)
    response.body
  end

  # A deck with no Basic Pokémon never terminates its mulligan loop, so every conditional
  # probability on this page is 0/0. It says so and renders nothing else.
  test "a deck with no Basic Pokemon says it cannot start a game, and shows no numbers" do
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 60)

    html = render_page

    assert_includes html, "This deck holds no Basic Pokémon, so it cannot start a game."
    assert_no_match(/odds-scenario/, html)
    assert_no_match(/data-curve/, html)
  end

  # The other unplayable state, and the one that every deck passes through in the minute after it is
  # created.
  test "a deck too small to deal says so" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 3)

    html = render_page

    assert_includes html, "This deck holds 3 cards — too few to deal an opening hand and six prizes."
    assert_no_match(/data-curve/, html)
  end

  # Not an edge case to tolerate but the normal state of a deck under construction, which is when
  # this page is most useful. The numbers are real; the notice names the gap.
  test "a deck that is not 60 cards is computed against its real size, with a notice" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 20)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 20)

    html = render_page

    assert_includes html, "These odds are computed against the 40 cards in this deck, not against 60."
    assert_includes html, "data-curve"
  end

  test "a legal deck says nothing about its size" do
    build_sixty
    html = render_page

    assert_no_match(/not against 60/, html)
  end

  # A deck of 7 to 12 cards deals a hand and no prizes: there is no honest prize section for it, and
  # no prize stepper either.
  test "a deck too small for prizes renders no prize section" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 6)

    html = render_page

    assert_includes html, "odds-scenario"
    assert_no_match(/Prize risk/, html)
    assert_no_match(/data-deck-odds-target="prizesTaken"/, html)
  end

  # A `search` count of 4 in a deck playing 12 uncurated searchers is a lie by omission, so the
  # coverage line is printed whether or not any card carries a role.
  test "the role panel says how much of the deck carries no role label" do
    draw = CardLabel.create!(slug: "draw", name: "Draw", family: "role", position: 10)
    CardLabelAssignment.create!(card_label: draw, fingerprint: "honedge_fp",
                                card: cards(:honedge), source: "curated")
    build_sixty

    html = render_page

    assert_includes html, "Draw"
    # The prescribed assertion ended this sentence with a period; the prescribed component text
    # continues it with a comma. The copy is the longer one, so the substring stops at the comma.
    assert_includes html, "56 of the 60 cards in this deck carry no role label yet,"
    assert_includes html, "A card is listed under every role it plays"
  end

  test "a deck whose cards carry no role at all still says so" do
    build_sixty
    html = render_page

    assert_includes html, "60 of the 60 cards in this deck carry no role label yet,"
  end

  # Every reactive cell ships its whole curve; the controller is an index lookup. The payload is
  # about 9 KB for a 60-card deck, measured.
  test "every reactive cell carries its curve, and the prize cells carry a seven-point one" do
    build_sixty
    html = render_page
    document = Nokogiri::HTML(html)

    seen_cells = document.css('[data-deck-odds-target="cell"]')
    prize_cells = document.css('[data-deck-odds-target="prizeCell"]')

    assert_operator seen_cells.size, :>, 0
    assert_operator prize_cells.size, :>, 0
    seen_cells.each { |cell| assert_equal 54, JSON.parse(cell["data-curve"]).size }
    prize_cells.each { |cell| assert_equal 7, JSON.parse(cell["data-curve"]).size }
  end

  # The controls' ceilings are data, not constants in the JavaScript: they are properties of this
  # deck, and a merged control could clamp neither of them.
  test "the wrapper hands the controller this deck's two ceilings" do
    build_sixty
    document = Nokogiri::HTML(render_page)
    wrapper = document.at_css('[data-controller~="deck-odds"]')

    assert_equal "47", wrapper["data-deck-odds-max-draws-value"]
    assert_equal "6", wrapper["data-deck-odds-max-prizes-value"]
    assert_equal "7", wrapper["data-deck-odds-hand-size-value"]
  end

  # …and 47 / 6 / 7 are a *60-card* deck's constants, so the test above passes against three
  # literals. Two other deck sizes are what make the three attributes follow N: a 20-card deck moves
  # max_draws off 47, and a 10-card deck deals no prizes at all.
  test "the two ceilings follow the deck rather than the reference deck" do
    twenty = deck_of([ cards(:honedge), 10 ], [ cards(:bosss_orders_meg), 10 ])
    wrapper = wrapper_of(Nokogiri::HTML(render_page(twenty)))

    # 20 - 7 hand - 6 prizes
    assert_equal "7", wrapper["data-deck-odds-max-draws-value"]
    assert_equal "6", wrapper["data-deck-odds-max-prizes-value"]
    assert_equal "7", wrapper["data-deck-odds-hand-size-value"]

    ten = deck_of([ cards(:honedge), 4 ], [ cards(:bosss_orders_meg), 6 ])
    wrapper = wrapper_of(Nokogiri::HTML(render_page(ten)))

    # Below 13 cards no prize is dealt, so the whole rest of the deck is drawable.
    assert_equal "3", wrapper["data-deck-odds-max-draws-value"]
    assert_equal "0", wrapper["data-deck-odds-max-prizes-value"]
    assert_equal "7", wrapper["data-deck-odds-hand-size-value"]
  end

  # The scenario the server renders is what a reader sees before Stimulus boots and all a reader
  # with no JavaScript ever sees. The system test looks only after connect() has rewritten every
  # cell, and the assertions above read attributes and never text — so the *index* the page opens on
  # is asserted here or nowhere. Text, not attribute, deliberately.
  test "the page opens on turn one, in the cells and in the summary" do
    build_sixty
    curve = Decks::Odds::Report.call(@deck.reload)
                               .card_rows.find { |row| row.name == "Honedge" }.accessible_curve
    document = Nokogiri::HTML(render_page)

    assert_equal Kernel.format("%.2f %%", curve[1]), seen_cell_for(document, "Honedge").text
    assert_equal "8 cards seen (7 hand + 1 drawn + 0 prizes)", summary_of(document)
  end

  # A seven-card deck has no first turn to take: its curve is one point and the summary must not
  # claim a draw the deck cannot make. Cell#view_template falls back to the last point of the curve
  # for an out-of-range index, which is exactly what hides an unclamped default here.
  test "a deck with no draw pile opens on its only point, and says it drew nothing" do
    seven = deck_of([ cards(:honedge), 4 ], [ cards(:bosss_orders_meg), 3 ])
    curve = Decks::Odds::Report.call(seven)
                               .card_rows.find { |row| row.name == "Honedge" }.accessible_curve
    document = Nokogiri::HTML(render_page(seven))

    assert_equal 1, curve.size
    assert_equal Kernel.format("%.2f %%", curve[0]), seen_cell_for(document, "Honedge").text
    assert_equal "7 cards seen (7 hand + 0 drawn + 0 prizes)", summary_of(document)
  end

  # Thirteen cards is the one size where the page's two halves could name two different scenarios:
  # max_draws is 0 while max_seen is 6, so a default index clamped against max_seen opened every
  # cell one notch ahead of the summary printed above it — 61.11 % under a line reading "0 drawn",
  # corrected to 53.33 % the instant Stimulus connected and never corrected at all for a reader
  # without it. The seven-card test above cannot see this: there the curve is one point, and
  # Cell#view_template's out-of-range fallback hides the wrong index behind the right number.
  test "a thirteen-card deck opens its cells on the same scenario its summary names" do
    thirteen = deck_of([ cards(:honedge), 4 ], [ cards(:bosss_orders_meg), 9 ])
    report = Decks::Odds::Report.call(thirteen)
    curve = report.card_rows.find { |row| row.name == "Honedge" }.accessible_curve
    document = Nokogiri::HTML(render_page(thirteen))

    assert_equal 0, report.max_draws
    assert_equal 6, report.max_seen, "a 13-card deck still deals prizes, so seen outruns drawn"
    assert_equal 7, curve.size, "and its curve has the points the prizes make reachable"

    assert_equal 0, report.default_seen
    assert_equal Kernel.format("%.2f %%", curve[0]), seen_cell_for(document, "Honedge").text
    assert_equal "7 cards seen (7 hand + 0 drawn + 0 prizes)", summary_of(document)
  end

  # The by-card table decides its header and its cells by two separate reads of `prizes?`, and
  # nothing else compares them: six headers over four cells shifts every data-label one column left
  # and mislabels the whole table on a phone, where the label is all there is.
  test "the by-card table gives every row exactly as many cells as it has headers" do
    build_sixty
    assert_card_table_columns Nokogiri::HTML(render_page), 6

    ten = deck_of([ cards(:honedge), 4 ], [ cards(:bosss_orders_meg), 6 ])
    assert_card_table_columns Nokogiri::HTML(render_page(ten)), 4
  end

  # No fixture makes a deck of nothing, and it is the state the page meets most often: the minute
  # after "New deck". Telling that reader it holds no Basic Pokémon sends them looking for the wrong
  # thing, so the size branch is tested first — which is what this pins.
  test "a deck holding nothing at all is told about its size, not about its Basic Pokemon" do
    html = render_page(deck_of)

    assert_includes html, "This deck holds 0 cards — too few to deal an opening hand and six prizes."
    assert_no_match(/no Basic Pokémon/, html)
  end

  # Five limits of the model, stated on the page rather than left to be discovered. The Iono clause
  # is the one a player would otherwise never guess: shuffling the hand back in makes already-seen
  # cards drawable again, so the page's answer is an over-estimate. The fifth was owed to two
  # reviews that found it independently — the prize columns are the one place the page prints a
  # different probability measure, unconditional where everything else is conditional, and a page
  # that does not say so invites a reader to take one for the other.
  # Asserted on phrases carrying no apostrophe and no quotation mark: Phlex escapes both, so a
  # substring holding one would be looked for in a body that does not contain it.
  test "the page states the five things the model does not do" do
    build_sixty
    html = render_page

    assert_includes html, "Draw effects are not modelled"
    assert_includes html, "are approximated upward"
    assert_includes html, "A card reached and then discarded counts as seen"
    assert_includes html, "Opponent mulligans are not modelled"
    assert_includes html, "The two prize columns answer a different question"
    assert_includes html, "prize risk is not"
  end

  # The picker's whole list ships with the page: the deck has about 25 groups and no request should
  # be needed to look at them.
  test "the combination picker ships the deck's own groups and nothing else" do
    build_sixty
    document = Nokogiri::HTML(render_page)

    options = document.css('[data-deck-combo-target="option"]').map(&:text).map(&:strip)

    # Whole labels, not name fragments: the option carries its copy count.
    assert_includes options, "Honedge (4)"
    assert_includes options, "Psychic Energy (40)"
    assert_not_includes options.join(" "), "Froakie", "a card this deck does not play is not an option"
    assert_equal 6, options.size
  end

  # The refusal the page cannot render when it happens: past the ration the response is a 429 with
  # no body in production, so nothing can be swapped into the frame at that moment. The notice
  # therefore ships hidden with the page, *outside* the frame — inside it, the first navigation
  # would take it away — and deck_combo_controller.js unhides it.
  test "the combination carries a hidden refusal notice, outside the frame" do
    build_sixty
    document = Nokogiri::HTML(render_page)

    notice = document.at_css('[data-deck-combo-target="throttled"]')

    assert_not_nil notice, "the page ships no throttle notice for the combination to reveal"
    assert notice.attributes.key?("hidden"), "the notice is not hidden until a refusal happens"
    assert_includes notice.text, "#{DecksController::ODDS_RATE_LIMIT_TO} requests a minute"
    assert_nil notice.at_xpath("ancestor::turbo-frame"),
      "a notice inside the frame is replaced by the first navigation that succeeds"
  end

  private

  # 60 cards, 12 of them Basic.
  def build_sixty
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 4)
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 4)
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 4)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 4)
    @deck.deck_cards.create!(card: cards(:basic_psychic_energy), quantity: 40)
    @deck.reload
  end

  def deck_of(*pairs)
    deck = @user.decks.create!(name: "Odds #{SecureRandom.hex(6)}",
                               standard_pool: standard_pools(:twm_por))
    pairs.each { |card, quantity| deck.deck_cards.create!(card: card, quantity: quantity) }
    deck.reload
  end

  def wrapper_of(document) = document.at_css('[data-controller~="deck-odds"]')

  def panel(document, heading)
    document.css("section.odds-panel").find { |section| section.at_css("h2")&.text == heading }
  end

  def summary_of(document) = document.at_css('[data-deck-odds-target="seenSummary"]').text

  # Scoped to the by-card panel: the prize panel holds a row for the same card, and an unscoped
  # lookup would find whichever came first.
  def seen_cell_for(document, name)
    row = panel(document, "By card").css(".data-table-row").find do |candidate|
      candidate.css(".data-table-cell").first.text == name
    end

    row.at_css('[data-deck-odds-target="cell"]')
  end

  def assert_card_table_columns(document, expected)
    section = panel(document, "By card")
    headers = section.css(".data-table-header .data-table-cell")
    cells = section.css(".data-table-row").first.css(".data-table-cell")

    assert_equal expected, headers.size
    assert_equal headers.size, cells.size
    assert_equal "Seen", headers.last.text
    assert_equal "Seen", cells.last["data-label"]
  end
end
