import { Controller } from "@hotwired/stimulus"
import { requestJson } from "helpers/api"

export default class extends Controller {
  static values = { deckId: Number, cardId: Number, quantity: Number }

  increment() {
    this.#updateQuantity(this.quantityValue + 1)
  }

  decrement() {
    if (this.quantityValue <= 0) return
    this.#updateQuantity(this.quantityValue - 1)
  }

  async #updateQuantity(newQuantity) {
    // The endpoint answers 204 when the quantity reaches zero and the row goes
    // away, which requestJson reports as a bare truthy value.
    const updated = await requestJson(`/api/decks/${this.deckIdValue}/cards/${this.cardIdValue}`, {
      method: "PATCH",
      body: { deck_card: { quantity: newQuantity } },
      failure: "Couldn't update this card's quantity"
    })
    if (!updated) return

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
