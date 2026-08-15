import { Controller } from "@hotwired/stimulus"
import { requestJson } from "helpers/api"
import { flashNotice } from "helpers/flash"

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
    const data = await requestJson("/api/collections", {
      method: "POST",
      body: { collection: { card_id: this.cardIdValue, quantity: 1 } },
      failure: "Couldn't add this card to your collection"
    })
    if (!data) return

    const previous = this.quantityValue
    this.quantityValue = data.quantity
    this.#refreshUi()
    this.#dispatchChanged({ delta: data.quantity - previous, removed: false, added: previous === 0 })
    this.#maybeFlash(`Added to collection (${data.quantity} ${data.quantity === 1 ? "copy" : "copies"})`)
  }

  async decrement() {
    if (this.quantityValue <= 1) return this.remove()

    const newQuantity = this.quantityValue - 1
    const updated = await requestJson(`/api/collections/${this.cardIdValue}`, {
      method: "PATCH",
      body: { collection: { quantity: newQuantity } },
      failure: "Couldn't update this card's quantity"
    })
    if (!updated) return

    this.quantityValue = newQuantity
    this.#refreshUi()
    this.#dispatchChanged({ delta: -1, removed: false, added: false })
  }

  async remove() {
    const previous = this.quantityValue
    const removed = await requestJson(`/api/collections/${this.cardIdValue}`, {
      method: "DELETE",
      failure: "Couldn't remove this card from your collection"
    })
    if (!removed) return

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

  #maybeFlash(message) {
    if (!this.flashOnChangeValue) return

    flashNotice(message)
  }
}
