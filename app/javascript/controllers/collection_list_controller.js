import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "empty", "unique", "copies"]

  changed(event) {
    const { delta, removed, added } = event.detail

    if (this.hasCopiesTarget) {
      this.copiesTarget.textContent = (parseInt(this.copiesTarget.textContent, 10) || 0) + delta
    }

    if (this.hasUniqueTarget) {
      const current = parseInt(this.uniqueTarget.textContent, 10) || 0
      if (removed) {
        this.uniqueTarget.textContent = current - 1
      } else if (added) {
        this.uniqueTarget.textContent = current + 1
      }
    }

    if (this.hasGridTarget && this.gridTarget.querySelectorAll(".collection-tile").length === 0) {
      if (this.hasEmptyTarget) this.emptyTarget.style.display = ""
    }
  }
}
