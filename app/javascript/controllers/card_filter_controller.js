import { Controller } from "@hotwired/stimulus"

// Auto-submits the cards filter form so results update live.
// Text input is debounced; selects submit immediately.
export default class extends Controller {
  static values = { delay: { type: Number, default: 300 } }

  disconnect() {
    clearTimeout(this.timeout)
  }

  submit() {
    clearTimeout(this.timeout)
    this.element.requestSubmit()
  }

  debounce() {
    clearTimeout(this.timeout)
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }
}
