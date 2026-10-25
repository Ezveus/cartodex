require "application_system_test_case"
require_relative "../support/deck_card_rows"

# No two things on a deck line may draw over each other. DeckRowGeometry (deck_row_narrow_test.rb)
# checks that every control stays inside its row and the screen, which a name overflowing its own
# box onto the "All printings" toggle beside it passes: both stay on screen, one on top of the
# other. This compares what is actually drawn — the text and boxes of each child of a line, through
# Range#getClientRects — pairwise, on both views and at two phone widths.
module DeckLineOverlap
  include DeckCardRows

  def self.included(base)
    base.class_eval do
      setup do
        @user = users(:one)
        @deck = @user.decks.create!(name: "Narrow lines", physical: true, standard_pool: standard_pools(:twm_por))
        # A card in two printings draws a summary line: name, "2 printings" and the toggle.
        @deck.deck_cards.create!(card: cards(:budew_asc), quantity: 2)
        @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)
        # Each held in one printing with another on record: name, set and the "All printings" toggle.
        %i[honedge doublade froakie_cri teal_mask_ogerpon_ex].each_with_index do |name, index|
          card = cards(name)
          @deck.deck_cards.create!(card: card, quantity: 1)
          # Owned, so the expanded row draws it as a sub-line with its owned note and ⇄.
          @user.collections.create!(card: reprint(card, set_name: "RPT", set_number: (900 + index).to_s), quantity: 1)
        end

        login_as @user, scope: :user
      end

      test "no two parts of a deck line overlap, in the type view" do
        visit deck_path(@deck)

        # Not vacuous: the lines measured carry the parts that collided.
        assert_selector ".deck-sections .deck-card-line .deck-printings-toggle", minimum: 5
        all(".deck-sections .deck-printings-toggle[aria-expanded='false']").each(&:click)
        assert_selector ".deck-sections .deck-printing-row .deck-printing-owned", minimum: 4
        assert_no_overlap
      end

      test "no two parts of a deck line overlap, in the set view" do
        visit deck_path(@deck, group: "set")

        # Each printing a row of its own, named beside its set.
        assert_selector ".deck-sections .deck-card-line .deck-card-set", minimum: 6
        assert_no_overlap
      end
    end
  end

  def reprint(card, set_name:, set_number:)
    Card.create!(
      name: card.name, card_type: card.card_type, hp: card.hp, type_symbol: card.type_symbol,
      retreat_cost: card.retreat_cost, stage: card.stage, set_name: set_name, set_number: set_number,
      rarity: "Common"
    ).tap { |twin| twin.update_column(:fingerprint, card.fingerprint) }
  end

  def assert_no_overlap
    assert_selector ".deck-sections .deck-card-line .deck-card-name", minimum: 5

    overlaps = page.evaluate_script(<<~JS)
      (() => {
        const rects = (element) => {
          const range = document.createRange()
          range.selectNodeContents(element)
          return [ ...range.getClientRects(), ...element.getClientRects() ].filter((rect) => rect.width > 0 && rect.height > 0)
        }
        const label = (element) => `${element.className} "${element.textContent.trim().slice(0, 24)}"`
        const found = []
        for (const line of document.querySelectorAll(".deck-sections .deck-card-line")) {
          if (line.getClientRects().length === 0) continue
          const parts = Array.from(line.children).filter((child) => child.getClientRects().length > 0)
          parts.forEach((a, i) => parts.slice(i + 1).forEach((b) => {
            for (const ra of rects(a)) for (const rb of rects(b)) {
              const x = Math.min(ra.right, rb.right) - Math.max(ra.left, rb.left)
              const y = Math.min(ra.bottom, rb.bottom) - Math.max(ra.top, rb.top)
              if (x > 0.5 && y > 0.5) found.push(`${label(a)} / ${label(b)}: ${x.toFixed(1)}px`)
            }
          }))
        }
        return [ ...new Set(found) ]
      })()
    JS

    assert_empty overlaps, "deck line parts overlap at #{page.evaluate_script('window.innerWidth')}px"
  end
end

# 344px: the phone the first narrow-row bug was reported from.
class DeckLineOverlapAt344Test < ApplicationSystemTestCase
  include DeckLineOverlap

  drive_at 344, 800
end

# 390px: the mobile sweep's nominal width, which Chrome itself floors at 500 — hence pinned here.
class DeckLineOverlapAt390Test < ApplicationSystemTestCase
  include DeckLineOverlap

  drive_at 390, 844
end
