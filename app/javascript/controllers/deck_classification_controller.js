import { Controller } from "@hotwired/stimulus"

// Toggles the conditional classification fields on the deck form: the custom
// format name only applies when the format is "other".
export default class extends Controller {
  static targets = ["format", "otherField"]

  connect() {
    this.toggleOther()
  }

  toggleOther() {
    if (!this.hasOtherFieldTarget || !this.hasFormatTarget) return
    this.otherFieldTarget.style.display = this.formatTarget.value === "other" ? "" : "none"
  }
}
