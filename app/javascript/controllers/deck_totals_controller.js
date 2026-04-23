import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["total", "sectionTotal", "sectionUnique"]

  updateTotals(event) {
    const { delta, removed } = event.detail

    this.totalTarget.textContent = parseInt(this.totalTarget.textContent) + delta

    const section = event.target.closest(".deck-section")
    if (!section) return

    const sectionTotal = section.querySelector('[data-deck-totals-target="sectionTotal"]')
    if (sectionTotal) {
      sectionTotal.textContent = parseInt(sectionTotal.textContent) + delta
    }

    if (removed) {
      const sectionUnique = section.querySelector('[data-deck-totals-target="sectionUnique"]')
      if (sectionUnique) {
        sectionUnique.textContent = parseInt(sectionUnique.textContent) - 1
      }
    }
  }
}
