require "application_system_test_case"

# The deck page's image view. What the server renders is held by test/controllers/deck_image_view_test.rb;
# what only a browser sees: the tiles laid out as a grid with the count on the art, and the image
# export reading them through its real collectCards.
class DeckImageViewSystemTest < ApplicationSystemTestCase
  # A 1×1 PNG, so every tile's art actually loads and is laid out as an image, not as alt text.
  PIXEL = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==".freeze

  setup do
    @user = users(:one)
    @deck = @user.decks.create!(name: "Pictures", shared: true, standard_pool: standard_pools(:twm_por))
    { doublade: 2, honedge: 3, budew_asc: 1, budew_pre: 4 }.each do |name, quantity|
      cards(name).update!(image_url: PIXEL)
      @deck.deck_cards.create!(card: cards(name), quantity: quantity)
    end
    login_as @user, scope: :user
  end

  test "the View links switch between the rows and the tiles, keeping the grouping" do
    visit deck_path(@deck, group: "set")
    assert_selector ".deck-fingerprint, .deck-printing-row"
    assert_no_selector ".deck-card-tile"

    within(".deck-group-modes", text: "View") { click_on "Images" }

    assert_selector ".deck-card-tile", count: 4
    assert_selector ".deck-set-section"
    assert_no_selector ".deck-card-search"
    assert_current_path deck_path(@deck, group: "set", view: "images")

    within(".deck-group-modes", text: "View") { click_on "List" }
    assert_no_selector ".deck-card-tile"
    assert_selector ".deck-card-search"
    # The tiles' "×" and their grid are scoped to the image view: the list's counts stay bare and
    # its rows stacked.
    assert_equal "none", page.evaluate_script(
      "getComputedStyle(document.querySelector('.deck-card-item .deck-card-qty'), '::before').content"
    )
    assert_equal "block", page.evaluate_script("getComputedStyle(document.querySelector('.deck-card-list')).display")
  end

  # Geometry, not text: a tile rendered as a stacked row would still carry every class asserted on.
  test "the tiles sit side by side, each with its count on the art" do
    visit deck_path(@deck, view: "images")
    assert_selector ".deck-card-tile-image", count: 4

    boxes = page.evaluate_script(<<~JS)
      Array.from(document.querySelectorAll(".deck-card-tile")).map(tile => {
        const art = tile.querySelector(".deck-card-tile-image").getBoundingClientRect()
        const badge = tile.querySelector(".deck-card-qty").getBoundingClientRect()
        return { top: art.top, left: art.left, width: art.width, height: art.height,
                 badge: { top: badge.top, left: badge.left, right: badge.right, bottom: badge.bottom } }
      })
    JS

    first, second, third = boxes
    assert_in_delta first["top"], second["top"], 1, "the second tile wrapped below the first"
    assert_in_delta first["top"], third["top"], 1, "the third tile wrapped below the first"
    assert_operator second["left"], :>, first["left"] + first["width"] - 1
    boxes.each do |box|
      assert_in_delta box["width"] * 88 / 63.0, box["height"], 2, "a tile lost the card's proportions"
      badge = box["badge"]
      assert badge["left"] >= box["left"] && badge["right"] <= box["left"] + box["width"] &&
             badge["top"] >= box["top"] && badge["bottom"] <= box["top"] + box["height"],
             "a count badge sits outside its art: #{badge.inspect} vs #{box.inspect}"
    end
    # The "×" is drawn by CSS, so the export's parseInt reads a bare number.
    assert_equal "×", page.evaluate_script(
      "getComputedStyle(document.querySelector('.deck-card-tile .deck-card-qty'), '::before').content"
    ).delete('"')
  end

  # The controller the Export menu runs, imported through the page's own importmap: the grid is the
  # only list on screen, and collectCards must find every printing in it with its count.
  test "the image export reads every tile, with its count" do
    visit deck_path(@deck, view: "images")
    assert_selector ".deck-card-tile", count: 4

    cards = page.evaluate_async_script(<<~JS)
      const done = arguments[arguments.length - 1]
      import("controllers/deck_image_export_controller").then(m => done(m.collectCards(document)))
    JS

    assert_equal [ 1, 2, 3, 4 ], cards.map { |c| c["quantity"] }.sort
    assert_equal 4, cards.map { |c| c["url"] }.uniq.size
  end

  test "a visitor gets the grid" do
    logout(:user)
    visit deck_path(@deck)

    within(".deck-group-modes") { click_on "Images" }

    assert_selector ".deck-card-tile", count: 4
    assert_no_selector ".deck-set-section"
  end
end
