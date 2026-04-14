import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["image", "link", "modal", "modalImage", "modalLink"]

  get isMobile() {
    return window.innerWidth <= 768
  }

  show(event) {
    const { cardPreviewUrl, cardPreviewCardId } = event.currentTarget.dataset
    if (this.isMobile) return

    if (cardPreviewUrl) {
      this.imageTarget.src = cardPreviewUrl
      this.imageTarget.style.display = "block"
    }
    if (cardPreviewCardId && this.hasLinkTarget) {
      this.linkTarget.href = `/cards/${cardPreviewCardId}`
      this.linkTarget.style.display = "inline-block"
    }
  }

  open(event) {
    if (!this.isMobile) return

    const { cardPreviewUrl, cardPreviewCardId } = event.currentTarget.dataset
    if (cardPreviewUrl && this.hasModalImageTarget) {
      this.modalImageTarget.src = cardPreviewUrl
    }
    if (cardPreviewCardId && this.hasModalLinkTarget) {
      this.modalLinkTarget.href = `/cards/${cardPreviewCardId}`
    }
    if (this.hasModalTarget) {
      this.modalTarget.showModal()
    }
  }

  closeModal() {
    if (this.hasModalTarget) {
      this.modalTarget.close()
    }
  }

  backdropClose(event) {
    if (event.target === this.modalTarget) {
      this.modalTarget.close()
    }
  }
}
