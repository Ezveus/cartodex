import { Controller } from "@hotwired/stimulus"

// Opens the share dialog from the deck's actions dropdown. Same shape as the open/close half
// of result_modal_controller.js; the sharing itself is a form POST, so there is nothing else
// here.
export default class extends Controller {
  static targets = ["dialog"]

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
  }
}
