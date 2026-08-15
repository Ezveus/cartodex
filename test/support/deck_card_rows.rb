# Scopes for the deck show page's card rows, shared by the system tests that drive them.
#
# The two steppers in a row look alike and read alike, so addressing them by text alone is a trap:
# the allocation stepper's "−" is a minus sign and the quantity stepper's "-" an ASCII hyphen. That
# is why these are three scopes rather than one `click_on` per test — a test that reached for the
# wrong dash would fail somewhere unrelated, or worse, silently drive the other control.
module DeckCardRows
  # The real/proxy stepper.
  def within_allocation_of(card_name, &block)
    within(row_of(card_name)) { within(".deck-card-alloc", &block) }
  end

  # The total-quantity stepper.
  def within_quantity_of(card_name, &block)
    within(row_of(card_name)) { within(".deck-card-qty-controls", &block) }
  end

  def row_of(card_name)
    find("li.deck-card-item", text: card_name)
  end
end
