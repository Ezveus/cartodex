import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["qty"]
  static values = { cardId: Number, quantity: Number }

  increment() {
    this.#update(this.quantityValue + 1)
  }

  decrement() {
    if (this.quantityValue <= 1) return
    this.#update(this.quantityValue - 1)
  }

  async remove() {
    const response = await fetch(`/api/collections/${this.cardIdValue}`, {
      method: "DELETE",
      headers: this.#headers(),
      credentials: "same-origin"
    })

    if (!response.ok) return
    this.element.remove()
  }

  async #update(newQuantity) {
    const response = await fetch(`/api/collections/${this.cardIdValue}`, {
      method: "PATCH",
      headers: this.#headers(),
      credentials: "same-origin",
      body: JSON.stringify({ collection: { quantity: newQuantity } })
    })

    if (!response.ok) return

    this.quantityValue = newQuantity
    this.qtyTarget.textContent = newQuantity
  }

  #headers() {
    const token = document.querySelector('meta[name="csrf-token"]').content
    return { "Content-Type": "application/json", "X-CSRF-Token": token }
  }
}
