import { Controller } from "@hotwired/stimulus"
import { flashResponseError } from "helpers/flash"

// Adjusts a deck card's real (owned-backed) copy count via the deck-card API.
export default class extends Controller {
  static targets = ["label"]
  static values = { deckId: Number, cardId: Number, owned: Number, max: Number }

  increment() {
    if (this.ownedValue >= this.maxValue) return
    this.#update(this.ownedValue + 1)
  }

  decrement() {
    if (this.ownedValue <= 0) return
    this.#update(this.ownedValue - 1)
  }

  async #update(newOwned) {
    const token = document.querySelector('meta[name="csrf-token"]').content
    const response = await fetch(`/api/decks/${this.deckIdValue}/cards/${this.cardIdValue}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      credentials: "same-origin",
      body: JSON.stringify({ deck_card: { owned_copies: newOwned } })
    })
    if (!response.ok) return flashResponseError(response, "Couldn't update this card's real copies")

    const data = await response.json()
    this.ownedValue = data.owned_copies
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = `${data.owned_copies} real · ${data.proxies} proxy`
    }
  }
}
