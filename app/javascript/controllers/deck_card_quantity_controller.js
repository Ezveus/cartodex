import { Controller } from "@hotwired/stimulus"
import { requestJson } from "helpers/api"

export default class extends Controller {
  static values = { deckKey: String, cardId: Number, quantity: Number }

  increment() {
    this.#updateQuantity(this.quantityValue + 1)
  }

  decrement() {
    if (this.quantityValue <= 0) return
    this.#updateQuantity(this.quantityValue - 1)
  }

  async #updateQuantity(newQuantity) {
    // When the quantity reaches zero the row goes away and the endpoint answers
    // `{ removed: true }` — still carrying the deck-wide state, which the badge needs precisely
    // when the card that disappears was the deck's last unbacked one.
    const updated = await requestJson(`/api/decks/${this.deckKeyValue}/cards/${this.cardIdValue}`, {
      method: "PATCH",
      body: { deck_card: { quantity: newQuantity } },
      failure: "Couldn't update this card's quantity"
    })
    if (!updated) return

    this.dispatch("changed", { prefix: "deck-proxies", detail: { hasProxies: updated.deck.has_proxies } })

    const delta = newQuantity - this.quantityValue
    this.quantityValue = newQuantity

    if (newQuantity <= 0) {
      this.dispatch("changed", { detail: { delta, removed: true } })
      this.element.remove()
    } else {
      this.element.querySelector(".deck-card-qty").textContent = newQuantity
      this.dispatch("changed", { detail: { delta, removed: false } })
    }
  }
}
