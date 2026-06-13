import { Controller } from "@hotwired/stimulus"

// Toggles the conditional classification fields on the deck form:
//   - the "with proxies" checkbox only makes sense for a physical deck
//   - the custom format name only applies when the format is "other"
export default class extends Controller {
  static targets = ["physical", "proxiesField", "format", "otherField"]

  connect() {
    this.toggleProxies()
    this.toggleOther()
  }

  toggleProxies() {
    if (!this.hasProxiesFieldTarget || !this.hasPhysicalTarget) return
    this.proxiesFieldTarget.style.display = this.physicalTarget.checked ? "" : "none"
  }

  toggleOther() {
    if (!this.hasOtherFieldTarget || !this.hasFormatTarget) return
    this.otherFieldTarget.style.display = this.formatTarget.value === "other" ? "" : "none"
  }
}
