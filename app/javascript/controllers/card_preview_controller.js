import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image"]

  show(event) {
    const url = event.currentTarget.dataset.cardPreviewUrl
    if (url) {
      this.imageTarget.src = url
      this.imageTarget.style.display = "block"
    }
  }
}
