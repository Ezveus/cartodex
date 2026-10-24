import { describe, expect, test } from "vitest"
import { collectCards } from "controllers/deck_image_export_controller"

// The image-export contract of a multi-printing row (plan B3): each in-deck printing is one
// `.deck-card-item` holding its own `.deck-card-qty`; the summary line prints the total in
// `.deck-card-total` and is not a `.deck-card-item`, so the total is never exported a second time.
const markup = `
  <ul class="deck-card-list">
    <li class="deck-fingerprint" data-row-key="fp-budew" data-fingerprint-key="fp-budew">
      <div class="deck-card-line" data-card-preview-url="/cards/asc.png">
        Budew <span class="deck-card-total">3</span>
      </div>
      <ul class="deck-printing-list" id="deck-printings-fp-budew" hidden>
        <li class="deck-printing-row">
          <div class="deck-card-line deck-card-item" data-card-preview-url="/cards/pre.png"><span class="deck-card-qty">1</span></div>
        </li>
        <li class="deck-printing-row">
          <div class="deck-card-line deck-card-item" data-card-preview-url="/cards/asc.png"><span class="deck-card-qty">2</span></div>
        </li>
      </ul>
    </li>
  </ul>`

describe("deck_image_export_controller", () => {
  test("collects each in-deck printing once, with its own count and never the row's total", () => {
    document.body.insertAdjacentHTML("beforeend", markup)

    expect(collectCards(document)).toEqual([
      { url: "/cards/pre.png", quantity: 1 },
      { url: "/cards/asc.png", quantity: 2 }
    ])
  })
})
