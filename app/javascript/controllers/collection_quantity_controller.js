import { Controller } from "@hotwired/stimulus"
import { flashNotice, flashResponseError } from "helpers/flash"

export default class extends Controller {
  static targets = ["qty", "counter", "addButton"]
  static values = {
    cardId: Number,
    quantity: Number,
    flashOnChange: { type: Boolean, default: false }
  }

  connect() {
    this.#refreshUi()
  }

  async increment() {
    const response = await fetch("/api/collections", {
      method: "POST",
      headers: this.#headers(),
      credentials: "same-origin",
      body: JSON.stringify({ collection: { card_id: this.cardIdValue, quantity: 1 } })
    })
    if (!response.ok) return flashResponseError(response, "Couldn't add this card to your collection")

    const data = await response.json()
    const previous = this.quantityValue
    this.quantityValue = data.quantity
    this.#refreshUi()
    this.#dispatchChanged({ delta: data.quantity - previous, removed: false, added: previous === 0 })
    this.#maybeFlash(`Added to collection (${data.quantity} ${data.quantity === 1 ? "copy" : "copies"})`)
  }

  async decrement() {
    if (this.quantityValue <= 1) return this.remove()

    const newQuantity = this.quantityValue - 1
    const response = await fetch(`/api/collections/${this.cardIdValue}`, {
      method: "PATCH",
      headers: this.#headers(),
      credentials: "same-origin",
      body: JSON.stringify({ collection: { quantity: newQuantity } })
    })
    if (!response.ok) return flashResponseError(response, "Couldn't update this card's quantity")

    this.quantityValue = newQuantity
    this.#refreshUi()
    this.#dispatchChanged({ delta: -1, removed: false, added: false })
  }

  async remove() {
    const previous = this.quantityValue
    const response = await fetch(`/api/collections/${this.cardIdValue}`, {
      method: "DELETE",
      headers: this.#headers(),
      credentials: "same-origin"
    })
    if (!response.ok) return flashResponseError(response, "Couldn't remove this card from your collection")

    const detail = { delta: -previous, removed: true, added: false }
    if (this.hasAddButtonTarget) {
      this.quantityValue = 0
      this.#refreshUi()
      this.dispatch("changed", { detail, bubbles: true })
    } else {
      const parent = this.element.parentElement
      this.element.remove()
      parent?.dispatchEvent(new CustomEvent("collection-quantity:changed", { bubbles: true, detail }))
    }
    this.#maybeFlash("Removed from collection")
  }

  #refreshUi() {
    if (this.hasQtyTarget) this.qtyTarget.textContent = this.quantityValue
    const zero = this.quantityValue === 0
    if (this.hasCounterTarget) this.counterTarget.style.display = zero ? "none" : ""
    if (this.hasAddButtonTarget) this.addButtonTarget.style.display = zero ? "" : "none"
  }

  #dispatchChanged(detail) {
    this.dispatch("changed", { detail, bubbles: true })
  }

  #headers() {
    const token = document.querySelector('meta[name="csrf-token"]').content
    return { "Content-Type": "application/json", "X-CSRF-Token": token }
  }

  #maybeFlash(message) {
    if (!this.flashOnChangeValue) return

    flashNotice(message)
  }
}
