import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "link"]

  show(event) {
    const { cardPreviewUrl, cardPreviewCardId } = event.currentTarget.dataset
    if (cardPreviewUrl) {
      this.imageTarget.src = cardPreviewUrl
      this.imageTarget.style.display = "block"
    }
    if (cardPreviewCardId && this.hasLinkTarget) {
      this.linkTarget.href = `/cards/${cardPreviewCardId}`
      this.linkTarget.style.display = "inline-block"
    }
  }
}
