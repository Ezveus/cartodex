import { Controller } from "@hotwired/stimulus"

// Removes a flash after five seconds — unless it is persistent, which is how a message carrying a
// link (Ui::FlashMessages' announcement) stays long enough to be followed. Either kind can be
// dismissed by hand.
export default class extends Controller {
  static values = { persistent: Boolean }

  connect() {
    if (this.persistentValue) return

    this.timeout = setTimeout(() => {
      this.element.remove()
    }, 5000)
  }

  disconnect() {
    clearTimeout(this.timeout)
  }

  dismiss() {
    this.element.remove()
  }
}
