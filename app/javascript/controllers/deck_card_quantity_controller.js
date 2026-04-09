import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { deckId: Number, cardId: Number, quantity: Number }

  increment() {
    this.#updateQuantity(this.quantityValue + 1)
  }

  decrement() {
    this.#updateQuantity(this.quantityValue - 1)
  }

  async #updateQuantity(newQuantity) {
    const token = document.querySelector('meta[name="csrf-token"]').content

    const response = await fetch(`/api/decks/${this.deckIdValue}/cards/${this.cardIdValue}`, {
      method: "PATCH",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      credentials: "same-origin",
      body: JSON.stringify({ deck_card: { quantity: newQuantity } })
    })

    if (response.ok) {
      window.Turbo.visit(window.location.href, { action: "replace" })
    }
  }
}
