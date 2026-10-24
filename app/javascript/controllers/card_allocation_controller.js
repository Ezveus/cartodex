import { Controller } from "@hotwired/stimulus"

// Reloads the card page's "Your copies" frame from the server whenever the collection counter
// changes. No arithmetic here: owned is a sum over the printing's collection rows, and only the
// server holds all of them (see Cards::AllocationSection).
export default class extends Controller {
  static values = { url: String }

  refresh() {
    // The frame is rendered inline with no src, so the first change gives it one — which loads it —
    // and every later change asks for the same URL again.
    if (this.element.getAttribute("src")) {
      this.element.reload()
    } else {
      this.element.src = this.urlValue
    }
  }
}
