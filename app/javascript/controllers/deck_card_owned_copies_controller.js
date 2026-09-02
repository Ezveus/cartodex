import { Controller } from "@hotwired/stimulus"
import { requestJson } from "helpers/api"

// Adjusts a deck card's real (owned-backed) copy count via the deck-card API.
export default class extends Controller {
  static targets = ["label"]
  static values = { deckId: String, cardId: Number, owned: Number, max: Number }

  increment() {
    if (this.ownedValue >= this.maxValue) return
    this.#update(this.ownedValue + 1)
  }

  decrement() {
    if (this.ownedValue <= 0) return
    this.#update(this.ownedValue - 1)
  }

  async #update(newOwned) {
    const data = await requestJson(`/api/decks/${this.deckIdValue}/cards/${this.cardIdValue}`, {
      method: "PATCH",
      body: { deck_card: { owned_copies: newOwned } },
      failure: "Couldn't update this card's real copies"
    })
    if (!data) return

    this.ownedValue = data.owned_copies
    if (this.hasLabelTarget) {
      this.labelTarget.textContent = `${data.owned_copies} real · ${data.proxies} proxy`
    }

    // The deck's "Proxies" badge derives from this very number, and it lives outside this
    // controller's element, so the server's deck-wide answer has to be relayed to it.
    this.dispatch("changed", { prefix: "deck-proxies", detail: { hasProxies: data.deck.has_proxies } })
  }
}
