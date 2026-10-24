import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  // sectionNoun is the set view's "card"/"cards" after its count; the type view's headings have none.
  static targets = ["total", "sectionTotal", "sectionUnique", "sectionNoun"]

  updateTotals(event) {
    const { delta, removed } = event.detail

    this.totalTarget.textContent = parseInt(this.totalTarget.textContent) + delta

    const section = event.target.closest(".deck-section")
    if (!section) return

    const sectionTotal = section.querySelector('[data-deck-totals-target="sectionTotal"]')
    if (sectionTotal) {
      const total = parseInt(sectionTotal.textContent) + delta
      sectionTotal.textContent = total

      const sectionNoun = section.querySelector('[data-deck-totals-target="sectionNoun"]')
      if (sectionNoun) sectionNoun.textContent = total === 1 ? "card" : "cards"
    }

    if (removed) {
      const sectionUnique = section.querySelector('[data-deck-totals-target="sectionUnique"]')
      if (sectionUnique) {
        sectionUnique.textContent = parseInt(sectionUnique.textContent) - 1
      }
    }
  }
}
