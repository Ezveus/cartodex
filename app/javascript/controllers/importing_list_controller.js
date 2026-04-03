import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["list"]

  listTargetConnected() {
    this.observer = new MutationObserver(() => this.#toggle())
    this.observer.observe(this.listTarget, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  #toggle() {
    this.element.style.display = this.listTarget.children.length > 0 ? "block" : "none"
  }
}
