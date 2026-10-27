require "test_helper"

# The deck page's image view (`?view=images`), on the owner's page and the public one. See
# docs/superpowers/specs/2026-10-27-deck-image-view-design.md.
class DeckImageViewTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = @user.decks.create!(name: "Pictures", shared: true, physical: true, standard_pool: standard_pools(:twm_por))
    sign_in @user
  end

  # Budew in two printings, so a type-view row expands into two tiles; a Trainer beside the Pokémon
  # and four set codes, so both groupings span several sections.
  def fill_deck
    [ cards(:doublade), cards(:honedge), cards(:budew_asc), cards(:budew_pre), cards(:trainer_card) ].each do |card|
      card.update!(image_url: "https://example.test/#{card.set_name}-#{card.set_number}.png")
    end
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 2)
    @deck.deck_cards.create!(card: cards(:honedge), quantity: 3, owned_copies: 0)
    @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 1)
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 4)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 2)
  end

  def tile_counts
    css_select(".deck-card-tile .deck-card-item").map do |item|
      [ item["data-card-preview-url"], item.at_css(".deck-card-qty").text ]
    end
  end

  test "the list stays the default and an unknown view is the list" do
    fill_deck

    get deck_path(@deck)
    assert_select ".deck-card-tile", count: 0
    assert_select ".deck-fingerprint"

    get deck_path(@deck, view: "grid")
    assert_select ".deck-card-tile", count: 0
    assert_select ".deck-fingerprint"
  end

  # The tile is what deck_image_export_controller.js#collectCards reads: one `.deck-card-item` per
  # in-deck printing, its preview URL, and a `.deck-card-qty` holding the bare number — `parseInt`
  # of "×4" is NaN, and the export would drop the card in silence.
  test "the owner's image view draws one tile per in-deck printing, readable by the image export" do
    fill_deck

    get deck_path(@deck, view: "images")

    assert_response :success
    expected = @deck.deck_cards.map { |dc| [ image_card_path(dc.card), dc.quantity.to_s ] }
    assert_equal expected.sort, tile_counts.sort
    assert_select ".deck-card-item", count: 5
    assert_select ".deck-card-tile img.deck-card-tile-image[loading=lazy]", count: 5
    assert_select "img[src=?]", cards(:budew_pre).image_url
  end

  test "the owner's image view is read-only" do
    fill_deck

    get deck_path(@deck, view: "images")

    assert_select ".deck-card-search", count: 0
    assert_select ".deck-fingerprint", count: 0
    assert_select ".deck-card-alloc", count: 0
    assert_select ".deck-card-tile button", count: 0
    assert_select "[data-deck-rows-target=sections]", count: 0
    # The header's in-place edit is not a row control and stays.
    assert_select "turbo-frame#deck-header"
  end

  # Same sections, same order, same counts as the list: Decks::Layout places both.
  test "the image view keeps the list's sections, in either grouping" do
    fill_deck

    { nil => ".deck-section", "set" => ".deck-set-section" }.each do |group, selector|
      get deck_path(@deck, group: group)
      list = css_select(selector).map { |s| [ s["data-section-key"], s.at_css("[data-section-total]")&.text ] }

      get deck_path(@deck, group: group, view: "images")
      grid = css_select(selector).map { |s| [ s["data-section-key"], s.at_css("[data-section-total]")&.text ] }

      assert_operator list.size, :>, 1, "#{group.inspect}: the deck must span several sections to compare orders"
      assert_equal list, grid, "#{group.inspect}: the grid's sections differ from the list's"
    end
  end

  test "a card with no image prints as a named placeholder, never a broken image" do
    fill_deck
    cards(:honedge).update_column(:image_url, nil)

    get deck_path(@deck, view: "images")

    assert_select ".deck-card-tile img", count: 4
    assert_select ".deck-card-tile-placeholder", count: 1, text: /Honedge/
  end

  # Each control keeps the other one's parameter, so either can be changed from anywhere.
  test "the view and group links each keep the other parameter" do
    fill_deck

    get deck_path(@deck, group: "set", view: "images")

    assert_select ".deck-group-modes a[href=?]", deck_path(@deck, view: "images"), text: "Type"
    assert_select ".deck-group-modes a[href=?][aria-current=page]", deck_path(@deck, group: "set", view: "images"), text: "Set"
    assert_select ".deck-group-modes a[href=?]", deck_path(@deck, group: "set"), text: "List"
    assert_select ".deck-group-modes a[href=?][aria-current=page]", deck_path(@deck, group: "set", view: "images"), text: "Images"
  end

  test "a visitor gets the image view, grouped by type and with no collection figure" do
    fill_deck
    sign_out :user

    get deck_path(@deck, group: "set", view: "images")

    assert_response :success
    expected = @deck.deck_cards.map { |dc| [ image_card_path(dc.card), dc.quantity.to_s ] }
    assert_equal expected.sort, tile_counts.sort
    assert_select ".deck-set-section", count: 0
    assert_select ".deck-card-alloc, .deck-card-owned, .deck-printing-owned", count: 0
    assert_select ".deck-group-modes a[href=?]", deck_path(@deck), text: "List"
    assert_select ".deck-group-modes a", text: "Set", count: 0
  end

  test "the public list links to the image view" do
    fill_deck
    sign_out :user

    get deck_path(@deck)

    assert_select ".deck-card-tile", count: 0
    assert_select ".deck-group-modes a[href=?]", deck_path(@deck, view: "images"), text: "Images"
  end

  # The grid needs the deck's own rows alone: Decks::FingerprintStates.deck_only, no catalogue read
  # and no availability. Measured: 15 for the list, 11 for the grid.
  test "the owner's image view costs less than the list" do
    fill_deck
    get deck_path(@deck)

    list = count_queries { get deck_path(@deck) }
    grid = count_queries { get deck_path(@deck, view: "images") }

    assert_equal 15, list
    assert_equal 11, grid
  end

  # deck_only on both: the public grid reads exactly what the public list reads.
  test "the visitor's image view costs what the public list costs" do
    fill_deck
    sign_out :user
    get deck_path(@deck)

    list = count_queries { get deck_path(@deck) }
    grid = count_queries { get deck_path(@deck, view: "images") }

    assert_equal list, grid
  end

  def current_modes(selector = "a[aria-current=page]")
    css_select(".deck-group-modes #{selector}").map { |a| a.text.strip }
  end

  # Selected by text, a count of current links cannot see a second one marked current beside it.
  test "each control marks exactly its own current mode" do
    fill_deck

    get deck_path(@deck)
    assert_equal %w[Type List], current_modes
    assert_equal %w[Type List], current_modes("a.deck-group-mode--current")

    get deck_path(@deck, group: "set", view: "images")
    assert_equal %w[Set Images], current_modes
    assert_equal %w[Set Images], current_modes("a.deck-group-mode--current")

    sign_out :user
    get deck_path(@deck, view: "images")
    assert_equal %w[Images], current_modes
  end

  # A set-view row is one printing: Budew ASC and Budew PRE each get one tile, in their own set's
  # section — never both printings in both sections.
  test "the set view draws each printing once, in its own set's section" do
    fill_deck

    get deck_path(@deck, group: "set", view: "images")

    assert_select ".deck-card-item", count: 5
    { cards(:budew_asc) => "1", cards(:budew_pre) => "4" }.each do |card, count|
      assert_select ".deck-set-section[data-set-code=?] .deck-card-item", card.set_name, count: 1 do |items|
        assert_equal card.id.to_s, items.sole["data-card-preview-card-id"]
        assert_equal count, items.sole.at_css(".deck-card-qty").text
      end
    end
  end

  # A type-view row's tiles come in FingerprintStates.deck_only's order — set code, then number —
  # on both pages, so the owner's grid and the visitor's read alike. POR is the newer set and sorts
  # after ASC: a catalogue (release) order would put it first.
  test "a card's tiles follow the set-code order on both pages" do
    asc = cards(:budew_asc)
    por = Card.create!(name: asc.name, card_type: asc.card_type, hp: asc.hp, type_symbol: asc.type_symbol,
                       retreat_cost: asc.retreat_cost, stage: asc.stage, card_set: card_sets(:por),
                       set_name: "POR", set_number: "3", rarity: "Common")
    por.update_column(:fingerprint, asc.fingerprint)
    @deck.deck_cards.create!(card: por, quantity: 1)
    @deck.deck_cards.create!(card: asc, quantity: 2)

    [ -> {}, -> { sign_out :user } ].each do |as_reader|
      as_reader.call
      get deck_path(@deck, view: "images")
      assert_equal [ asc.id, por.id ].map(&:to_s),
                   css_select(".deck-card-tile .deck-card-item").map { |i| i["data-card-preview-card-id"] }
    end
  end

  # Nothing remembers the view: the next plain request is the list again.
  test "the view is not stored" do
    fill_deck

    [ -> {}, -> { sign_out :user } ].each do |as_reader|
      as_reader.call
      get deck_path(@deck, view: "images")
      get deck_path(@deck)
      assert_select ".deck-card-tile", count: 0
      assert_select ".deck-fingerprint"
    end
  end

  # Editing happens on the list: the Edit link, the header form and its Cancel keep the grouping
  # and drop the view, and a full-page edit asked for in the image view draws the rows.
  test "the edit links do not carry the view, and a full-page edit is the list" do
    fill_deck

    get deck_path(@deck, group: "set", view: "images")
    assert_equal [ edit_deck_path(@deck, group: "set") ],
                 css_select("a").select { |a| a.text.strip == "Edit" }.map { |a| a["href"] }

    get edit_deck_path(@deck, group: "set", view: "images")
    assert_select ".deck-card-tile", count: 0
    assert_select "[data-deck-rows-target=sections]"
    assert_select "form.deck-header-form[action=?]", deck_path(@deck, group: "set")
    assert_select "a[href=?]", deck_path(@deck, group: "set"), text: "Cancel"
  end

  # Clicking a tile opens the card preview, as clicking a row does, on both pages.
  test "a tile opens the card preview" do
    fill_deck

    [ -> {}, -> { sign_out :user } ].each do |as_reader|
      as_reader.call
      get deck_path(@deck, view: "images")
      assert_select ".deck-show-container[data-controller~=card-preview]"
      css_select(".deck-card-tile .deck-card-item").each do |item|
        assert_includes item["data-action"], "mouseenter->card-preview#show"
        assert_includes item["data-action"], "click->card-preview#open"
        assert_match(/\A\d+\z/, item.at_css(".deck-card-qty").text)
      end
    end
  end

  # One card per new set, so each printing is distinct SQL the query cache cannot hide.
  test "the owner's image view costs the same however many cards and sets the deck holds" do
    add_card = lambda do |index|
      set = CardSet.create!(code: "IG#{index}", name: "Grid #{index}", release_date: Date.new(2020, 1, index))
      card = Card.create!(name: "Grid card #{index}", card_type: "Trainer", subtype: "Item", rarity: "Common",
                          set_name: set.code, set_number: "1", card_set: set,
                          image_url: "https://example.test/#{index}.png")
      @deck.deck_cards.create!(card: card, quantity: 1)
    end
    (1..2).each(&add_card)

    [ nil, "set" ].each do |group|
      get deck_path(@deck, group: group, view: "images")
      small = count_queries { get deck_path(@deck, group: group, view: "images") }
      (3..6).each(&add_card) if group.nil?
      (7..10).each(&add_card) if group == "set"
      large = count_queries { get deck_path(@deck, group: group, view: "images") }
      assert_equal small, large, "#{group.inspect}: the grid's cost grew with the deck: #{small} -> #{large}"
    end
  end
end
