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

  // The click action sits on the whole row, because the row is the tap target we want. But the row
  // also holds the quantity and allocation steppers, and a tap on one of those bubbles up here —
  // so pressing "+" both changed the card and opened the viewer on top of it. Anything already
  // interactive keeps its own click: a rule rather than a list of the controls that exist today,
  // since the row is where new ones get added.
  //
  // data-action is in the list because most clickable things here are not native controls — this
  // app writes them as a <div> or <span> with an action on it. Two bounds on that: the row itself
  // carries one, so it has to be excluded or the viewer would never open again, and closest()
  // climbs past the row, so an ancestor <a> or <label> would otherwise disable the viewer
  // page-wide.
  #fromControl(event) {
    const control = event.target.closest("button, a, input, select, textarea, label, [data-action]")

    return Boolean(control) && control !== event.currentTarget && event.currentTarget.contains(control)
  }

  open(event) {
    if (!this.isMobile) return
    if (this.#fromControl(event)) return

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
