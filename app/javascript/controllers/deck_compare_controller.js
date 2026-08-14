import { Controller } from "@hotwired/stimulus"

// Lets the user pick 2 to 4 decks on the index and jump to the compare page.
// Shows an action bar while any deck is selected and caps the selection at 4.
export default class extends Controller {
  static targets = ["checkbox", "bar", "count", "button"]
  static values = { compareUrl: String, max: { type: Number, default: 4 } }

  connect() {
    this.update()
  }

  toggle() {
    this.update()
  }

  // Also wired to turbo:frame-load on the deck_results frame: filtering swaps the
  // checkboxes in unchecked while the bar (outside the frame) survives, so its count
  // has to be recomputed against the new DOM. Target getters query live, so the
  // freshly inserted checkboxes are already visible here.
  update() {
    const selected = this.#selected()
    const count = selected.length

    if (this.hasCountTarget) this.countTarget.textContent = count

    this.checkboxTargets.forEach((cb) => {
      if (!cb.checked) cb.disabled = count >= this.maxValue
    })

    if (this.hasBarTarget) this.barTarget.classList.toggle("is-visible", count > 0)
    if (this.hasButtonTarget) this.buttonTarget.disabled = count < 2 || count > this.maxValue
  }

  compare(event) {
    event.preventDefault()
    const ids = this.#selected()
    if (ids.length < 2 || ids.length > this.maxValue) return

    const params = new URLSearchParams()
    ids.forEach((id) => params.append("ids[]", id))
    window.location.href = `${this.compareUrlValue}?${params.toString()}`
  }

  clear() {
    this.checkboxTargets.forEach((cb) => {
      cb.checked = false
      cb.disabled = false
    })
    this.update()
  }

  #selected() {
    return this.checkboxTargets.filter((cb) => cb.checked).map((cb) => cb.value)
  }
}
