require "test_helper"

# The owner's deck page grouped by set (`?group=set`). Decks::SetGroupsTest holds the ordering rule
# over every edge case; this file holds what only a request sees — which page honours the
# parameter, what each link carries, and what the set view costs.
class DeckSetGroupingTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = @user.decks.create!(name: "Sets", standard_pool: standard_pools(:twm_por))
    sign_in @user
  end

  # POR (2026-01-16) is newer than ASC (2025-11-07) while "ASC" < "POR": release order and code
  # order disagree. PAL is added before CRI: insertion order and the alphabet disagree too.
  def fill_deck
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 2)        # POR 57
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 1)       # ASC 16
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 3)    # PAL 172, no set
    @deck.deck_cards.create!(card: cards(:froakie_cri), quantity: 1)     # CRI 20, no set
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)         # POR 56
    # POR 10 with no card_set: it joins the POR section, and ahead of 56 and 57.
    @deck.deck_cards.create!(card: trainer("Unlinked POR", set_name: "POR", set_number: "10"), quantity: 1)
  end

  def trainer(name, set_name:, set_number:, card_set: nil)
    Card.create!(name: name, card_type: "Trainer", subtype: "Item", rarity: "Common",
                 set_name: set_name, set_number: set_number, card_set: card_set)
  end

  # A card in a set of its own, so each one costs a distinct `card_sets` row: rows sharing an id
  # issue identical SQL, which the query cache serves and count_queries does not count.
  def card_in_new_set(index)
    set = CardSet.create!(code: "ZS#{index}", name: "Set #{index}", release_date: Date.new(2020, 1, index + 1))
    trainer("Set card #{index}", set_name: "ZS#{index}", set_number: "1", card_set: set)
  end

  def section_codes = css_select(".deck-set-section").map { |s| s["data-set-code"] }

  # Nothing on Card ties `set_name` to its linked set's code, and `Cards::Fetcher` takes the former
  # from a URL segment: a linked section is coded by the set, which is what it is keyed and titled on.
  test "a linked section is coded by its set even when the card's set_name says otherwise" do
    @deck.deck_cards.create!(card: trainer("Odd code", set_name: "PORX", set_number: "1", card_set: card_sets(:por)),
                             quantity: 1)

    get deck_path(@deck, group: "set")

    assert_select ".deck-set-section[data-section-key=?]", "set-#{card_sets(:por).id}" do |sections|
      assert_equal "POR", sections.sole["data-set-code"]
    end
  end

  test "the set view lists sections newest set first, then unlinked codes, with copies in each heading" do
    fill_deck

    get deck_path(@deck, group: "set")

    assert_response :success
    assert_equal %w[POR ASC CRI PAL], section_codes
    assert_select ".deck-set-section[data-set-code=POR] h2", text: "Perfect Order (POR) · 4 cards"
    assert_select ".deck-set-section[data-set-code=ASC] h2", text: "Ascended Heroes (ASC) · 1 card"
    assert_select ".deck-set-section[data-set-code=PAL] h2", text: "PAL · 3 cards"
    assert_equal %w[POR\ 10 POR\ 56 POR\ 57],
                 css_select(".deck-set-section[data-set-code=POR] .deck-card-set").map { |e| e.text.squish }
    # The type view's headings are gone, not doubled.
    assert_select "h2", text: /Pokémon \(/, count: 0
    assert_select ".deck-show-main[data-deck-group=set]"
  end

  # B9: the heading's two figures are what deck_rows_controller.js rewrites after a write, and the
  # section key is how it finds the section — the set's id when the printing is linked to one, the
  # code otherwise, since an unlinked code has no row to take an id from.
  test "a set section carries its key and the spans the page rewrites in place" do
    fill_deck

    get deck_path(@deck, group: "set")

    assert_select ".deck-set-section[data-set-code=POR][data-section-key=?]", "set-#{card_sets(:por).id}" do
      assert_select "> h2 [data-section-total]", text: "4"
      assert_select "> h2 [data-section-noun]", text: "cards"
      assert_select "> ul.deck-card-list > li.deck-printing-row", count: 3
    end
    assert_select ".deck-set-section[data-set-code=ASC][data-section-key=?]", "set-#{card_sets(:asc).id}" do
      assert_select "> h2 [data-section-noun]", text: "card"
    end
    assert_select ".deck-set-section[data-set-code=PAL][data-section-key=set-code-pal]"
    assert_select ".deck-set-section[data-set-code=CRI][data-section-key=set-code-cri]"
  end

  # B2, set view: one row per printing, so a card played in two sets is a row in each, both
  # answering to the card's fingerprint for the rows a write replaces.
  test "the set view renders a card split across two sets as a row in each" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)

    get deck_path(@deck, group: "set")

    rows = css_select("li.deck-printing-row[data-row-key^='printing:']")
    assert_equal [ "printing:#{cards(:budew_asc).id}", "printing:#{cards(:budew_pre).id}" ], rows.map { |row| row["data-row-key"] }
    assert_equal [ "budew_shared" ], rows.map { |row| row["data-fingerprint-key"] }.uniq
    assert_select ".deck-set-section[data-section-key=?] li.deck-printing-row .deck-card-name", "set-#{card_sets(:asc).id}", text: "Budew"
    assert_select ".deck-set-section[data-section-key=set-code-pre] li.deck-printing-row .deck-card-item .deck-card-qty", text: "1"
    assert_select "li.deck-fingerprint", count: 0
    assert_select ".deck-printings-toggle", count: 0
  end

  def reprint(card, set_name:, set_number:, card_set: nil)
    Card.create!(
      name: card.name, card_type: card.card_type, hp: card.hp, type_symbol: card.type_symbol,
      retreat_cost: card.retreat_cost, stage: card.stage, card_set: card_set,
      set_name: set_name, set_number: set_number, rarity: "Common"
    ).tap { |twin| twin.update_column(:fingerprint, card.fingerprint) }
  end

  # The set view is one row per printing, and a printing's row is where its printing changes: it
  # expands onto the card's owned printings outside the deck, then "Other printings", fetched — and
  # every ⇄ in it moves a copy off this row's own printing, the one the member opened.
  test "a set-view row expands onto the owned printings, then the fetched others, each ⇄ taking from it" do
    asc = cards(:budew_asc)
    por = reprint(asc, set_name: "POR", set_number: "3", card_set: card_sets(:por))
    @user.collections.create!(card: por, quantity: 1)
    @deck.deck_cards.create!(card: asc, quantity: 2)
    row_key = "printing:#{asc.id}"

    get deck_path(@deck, group: "set")

    assert_select "li.deck-printing-row[data-row-key=?]", row_key do
      assert_select "> .deck-card-line .deck-printings-toggle[aria-expanded=false][aria-controls=?]",
                    "deck-printings-printing-#{asc.id}", text: "All printings (3)"
      assert_select "> ul#deck-printings-printing-#{asc.id}[hidden]" do
        assert_select "> li.deck-printing-row:not([data-row-key])", count: 1 do
          assert_select ".deck-card-set", text: "POR 3"
          assert_select ".deck-printing-owned", text: "1 owned · 1 free"
          assert_select "button.deck-printing-move[title='Move one copy here from ASC 16']" \
                        "[data-deck-rows-url-param=?]", move_api_deck_card_path(@deck, por, group: "set")
        end
        assert_select "> li.deck-printing-others" do
          assert_select ".deck-printings-others-toggle[data-deck-rows-url-param=?]",
                        other_printings_api_deck_card_path(@deck, asc, group: "set"), text: "Other printings (1)"
          assert_select "ul#deck-printings-others-printing-#{asc.id}[data-deck-rows-pending]:empty"
        end
      end
    end
  end

  # With two printings in the deck the type view's rule — the other in-deck printing — would make the
  # ⇄ under ASC's row move a copy off PRE. In the set view each row's expansion moves off itself.
  test "each set-view row's ⇄ moves from that row's printing" do
    asc = cards(:budew_asc)
    por = reprint(asc, set_name: "POR", set_number: "3", card_set: card_sets(:por))
    @user.collections.create!(card: por, quantity: 1)
    @deck.deck_cards.create!(card: asc, quantity: 1)
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 3)

    get deck_path(@deck, group: "set")

    { asc => "ASC 16", cards(:budew_pre) => "PRE 4" }.each do |card, label|
      assert_select "#deck-printings-printing-#{card.id} button.deck-printing-move[data-focus-key=move-#{por.id}]" do |buttons|
        assert_equal "Move one copy here from #{label}", buttons.sole["title"]
        assert_equal({ "move" => { "from_card_id" => card.id } }, JSON.parse(buttons.sole["data-deck-rows-body-param"]))
      end
    end
  end

  test "the default view is the type view, its links carrying no group" do
    fill_deck

    get deck_path(@deck)

    assert_response :success
    assert_select ".deck-set-section", 0
    assert_select "h2", text: "Pokémon (5 — 4 unique)"
    assert_select ".deck-show-main[data-deck-group]", 0
    assert_select "[data-section-noun]", 0
    assert_select "a[href=?]", edit_deck_path(@deck), text: "Edit"
    assert_mode_links current: "Type"
  end

  test "an unknown group value falls back to the type view" do
    fill_deck

    get deck_path(@deck, group: "junk")

    assert_select ".deck-set-section", 0
    assert_select "h2", text: "Pokémon (5 — 4 unique)"
    assert_mode_links current: "Type"
  end

  test "the set view marks its own link current and carries the view on Edit" do
    fill_deck

    get deck_path(@deck, group: "set")

    assert_mode_links current: "Set"
    assert_select "a[href=?]", edit_deck_path(@deck, group: "set"), text: "Edit"
  end

  test "a full-page edit honours the view, and its form and Cancel carry it" do
    fill_deck

    get edit_deck_path(@deck, group: "set")

    assert_response :success
    assert_equal %w[POR ASC CRI PAL], section_codes
    assert_select "form.deck-header-form[action=?]", deck_path(@deck, group: "set")
    assert_select "a[href=?]", deck_path(@deck, group: "set"), text: "Cancel"
    # The mode links point at the show page, never at /edit.
    assert_mode_links current: "Set"

    get edit_deck_path(@deck)

    assert_select "form.deck-header-form[action=?]", deck_path(@deck)
    assert_select "a[href=?]", deck_path(@deck), text: "Cancel"
  end

  test "a refused save from the set view re-renders a Cancel that keeps it" do
    patch deck_path(@deck, group: "set"), params: { deck: { name: "" } }

    assert_response :unprocessable_entity
    assert_select "a[href=?]", deck_path(@deck, group: "set"), text: "Cancel"
    assert_select "form.deck-header-form[action=?]", deck_path(@deck, group: "set")
  end

  test "a printing whose number has no digit still renders in the set view" do
    @deck.deck_cards.create!(card: trainer("Lettered", set_name: "LTR", set_number: "SV"), quantity: 1)
    @deck.deck_cards.create!(card: trainer("Numbered", set_name: "LTR", set_number: "2"), quantity: 1)

    get deck_path(@deck, group: "set")

    assert_response :success
    assert_equal %w[LTR\ 2 LTR\ SV], css_select(".deck-card-set").map { |e| e.text.squish }
  end

  test "the set view's cost does not grow with the number of sets" do
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 1)
    2.times { |i| @deck.deck_cards.create!(card: card_in_new_set(i), quantity: 1) }
    get deck_path(@deck, group: "set") # warm the session

    small = count_queries { get deck_path(@deck, group: "set") }
    2.upto(3) { |i| @deck.deck_cards.create!(card: card_in_new_set(i), quantity: 1) }
    large = count_queries { get deck_path(@deck, group: "set") }

    assert_equal 5, section_codes.size
    assert_equal small, large, "query count grew with the number of sets: #{small} -> #{large}"
  end

  test "the full-page edit's set view does not grow with the number of sets either" do
    2.times { |i| @deck.deck_cards.create!(card: card_in_new_set(i), quantity: 1) }
    get edit_deck_path(@deck, group: "set")

    small = count_queries { get edit_deck_path(@deck, group: "set") }
    2.upto(3) { |i| @deck.deck_cards.create!(card: card_in_new_set(i), quantity: 1) }
    large = count_queries { get edit_deck_path(@deck, group: "set") }

    assert_equal small, large, "query count grew with the number of sets: #{small} -> #{large}"
  end

  # The preload is the set view's alone: `card_preloads(:type)` is empty, so the type view pays nothing for it.
  test "the set view costs exactly one statement more than the type view" do
    fill_deck
    get deck_path(@deck)

    by_type = count_queries { get deck_path(@deck) }
    by_set = count_queries { get deck_path(@deck, group: "set") }

    assert_equal 1, by_set - by_type
  end

  test "the public page ignores the parameter: no control, no sections, no extra query" do
    fill_deck
    @deck.update!(shared: true)

    [ -> { sign_out :user }, -> { sign_in users(:two) } ].each do |as_reader|
      as_reader.call
      get deck_path(@deck)

      plain = count_queries { get deck_path(@deck) }
      grouped = count_queries { get deck_path(@deck, group: "set") }

      assert_response :success
      assert_select ".deck-group-modes", 0
      assert_select ".deck-set-section", 0
      assert_equal plain, grouped
    end
  end

  private

  def assert_mode_links(current:)
    assert_select "a.deck-group-mode[href=?]", deck_path(@deck), text: "Type"
    assert_select "a.deck-group-mode[href=?]", deck_path(@deck, group: "set"), text: "Set"
    assert_select "a.deck-group-mode[aria-current=page]", count: 1, text: current
    assert_select "a.deck-group-mode--current", count: 1, text: current
  end
end
