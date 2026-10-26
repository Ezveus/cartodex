# Scopes for the deck show page's rows, shared by the system tests that drive them.
#
# A row is one card (`[data-row-key]`: li.deck-fingerprint in the type view, li.deck-printing-row in
# the set view); its own line is the direct child `.deck-card-line`, and an expanded row holds one
# sub-row per printing under it, each with a line of its own. Scoping to a row is therefore not
# enough to address a stepper: a multi-printing row holds one per printing, and its own line holds
# none. These helpers scope to exactly one line.
#
# The two steppers in a line look alike and read alike, so addressing them by text alone is a trap:
# the allocation stepper's "−" is a minus sign and the quantity stepper's "-" an ASCII hyphen. That
# is why these are scopes rather than one `click_on` per test — a test that reached for the wrong
# dash would fail somewhere unrelated, or worse, silently drive the other control.
module DeckCardRows
  LINE_XPATH = "./div[contains(concat(' ', normalize-space(@class), ' '), ' deck-card-line ')]".freeze

  # The real/proxy stepper on the card's own line — a card held in one printing.
  def within_allocation_of(card_name, &block)
    within(line_of(card_name)) { within(".deck-card-alloc", &block) }
  end

  # The total-quantity stepper on the card's own line — a card held in one printing.
  def within_quantity_of(card_name, &block)
    within(line_of(card_name)) { within(".deck-card-qty-controls", &block) }
  end

  # One printing's line, wherever it is drawn: the card's own line when the deck holds that printing
  # alone, a visible sub-row otherwise. Matched on the whole set label, so "PAL 17" is not "PAL 172".
  def within_printing(set_label, &block)
    within(printing_line(set_label), &block)
  end

  def printing_line(set_label)
    settle_deck_rows
    find(".deck-sections .deck-card-set", exact_text: set_label).ancestor(".deck-card-line")
  end

  # The public page's rows carry no key, being written by nothing.
  def row_of(card_name)
    settle_deck_rows
    find(".deck-sections [data-row-key], .deck-sections li.deck-fingerprint", text: card_name)
  end

  def line_of(card_name)
    row_of(card_name).find(:xpath, LINE_XPATH)
  end

  # Opens the card's printings — the toggle on its own line.
  def expand_printings_of(card_name)
    within(line_of(card_name)) { find(".deck-printings-toggle[aria-expanded='false']").click }
    within(row_of(card_name)) { assert_selector ".deck-printings-toggle[aria-expanded='true']" }
  end

  # A write answered in place leaves both behind; any reload drops the window's, and a Turbo visit —
  # which keeps the window — drops the attribute on the list it re-renders.
  def mark_page
    execute_script(<<~JS)
      window.__noReload = 1
      document.querySelector(".deck-show-main").dataset.testMarker = "1"
    JS
  end

  def assert_page_not_reloaded
    assert_selector ".deck-show-main[data-test-marker]"
    assert_equal 1, evaluate_script("window.__noReload"), "the page reloaded"
  end

  def deck_total
    find("[data-deck-rows-target='total']").text
  end

  # A write in flight is about to replace the rows it touches, so an element found now would go
  # stale under the assertion that follows: deck_rows_controller.js marks the list aria-busy until
  # the answer is applied. A no-op on the public page, which has no writes.
  def settle_deck_rows
    assert_no_selector ".deck-sections[aria-busy='true']"
  end
end
