import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["grid", "empty"]

  removed() {
    if (this.gridTarget.querySelectorAll(".collection-tile").length === 0) {
      this.emptyTarget.style.display = ""
    }
  }
}
