import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["total", "sectionTotal"]

  updateTotals(event) {
    const { delta } = event.detail

    // Update global total
    const totalEl = this.totalTarget
    totalEl.textContent = parseInt(totalEl.textContent) + delta

    // Update section total (find the closest .deck-section h2)
    const section = event.target.closest(".deck-section")
    if (section) {
      const h2 = section.querySelector("h2")
      h2.textContent = h2.textContent.replace(/\((\d+)\)/, (_, n) => `(${parseInt(n) + delta})`)
    }
  }
}
