import { Controller } from "@hotwired/stimulus"

// Toggles the conditional classification fields on the deck form. Two fields
// depend on the format: the custom name applies only to "other", the Standard
// pool only to "standard" — Standard is the one rotating format.
export default class extends Controller {
  static targets = ["format", "otherField", "standardField"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasFormatTarget) return

    const format = this.formatTarget.value
    this.show(this.hasOtherFieldTarget && this.otherFieldTarget, format === "other")
    this.show(this.hasStandardFieldTarget && this.standardFieldTarget, format === "standard")
  }

  show(element, visible) {
    if (!element) return
    element.style.display = visible ? "" : "none"
  }
}
