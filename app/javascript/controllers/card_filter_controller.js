import { Controller } from "@hotwired/stimulus"

// Auto-submits the cards filter form so results update live.
// Text input is debounced; selects submit immediately.
export default class extends Controller {
  static targets = ["clear"]
  static values = { delay: { type: Number, default: 300 } }

  disconnect() {
    clearTimeout(this.timeout)
  }

  submit() {
    clearTimeout(this.timeout)
    this.#syncClear()
    this.element.requestSubmit()
  }

  debounce() {
    clearTimeout(this.timeout)
    this.#syncClear()
    this.timeout = setTimeout(() => this.element.requestSubmit(), this.delayValue)
  }

  // On the decks page the results land in a Turbo Frame, so the server re-renders the grid but
  // never this form: a "Clear" link decided server-side would still be showing after the user
  // emptied the last field, and still missing after they typed in the first. Sync it here, from
  // the fields themselves, and immediately — the request behind it is debounced, this isn't.
  // The cards page uses the same controller without the target; hence the guard.
  #syncClear() {
    if (!this.hasClearTarget) return

    this.clearTarget.hidden = !this.#anyFilterSet()
  }

  #anyFilterSet() {
    return Array.from(new FormData(this.element).values()).some((value) => String(value).trim() !== "")
  }
}
