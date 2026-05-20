import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { cardId: Number }

  async add(event) {
    const button = event.currentTarget
    const originalLabel = button.textContent
    button.disabled = true

    const token = document.querySelector('meta[name="csrf-token"]').content
    const response = await fetch("/api/collections", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      credentials: "same-origin",
      body: JSON.stringify({ collection: { card_id: this.cardIdValue, quantity: 1 } })
    })

    if (response.ok) {
      const data = await response.json()
      button.textContent = `Added (${data.quantity} in collection)`
    } else {
      button.textContent = "Failed to add"
    }

    setTimeout(() => {
      button.textContent = originalLabel
      button.disabled = false
    }, 1500)
  }
}
