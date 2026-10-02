import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, text: String }

  connect() {
    // Read once: a click landing while "Copied!" or a notice is showing would otherwise take that
    // text for the label and restore it, leaving the button stuck on it. This does not cover a
    // Turbo snapshot taken while that text is showing: restored from the cache, the element
    // reconnects with it as its content, and it becomes the label.
    this.label = this.element.textContent
  }

  disconnect() {
    clearTimeout(this.restoreTimer)
  }

  async copy() {
    const original = this.label

    try {
      const { text, notice } = this.hasTextValue
        ? { text: this.textValue }
        : await (await fetch(this.urlValue, { credentials: "same-origin" })).json()

      // The server had nothing to copy and says why (a wishlist with nothing left to buy).
      // Leave the clipboard as it was rather than empty it.
      if (notice) {
        this.element.textContent = notice
        this.restore(original, 3000)
        return
      }

      await navigator.clipboard.writeText(text)

      this.element.textContent = "Copied!"
      this.restore(original, 2000)
    } catch (e) {
      console.error("Clipboard copy failed:", e)
      // Say so. navigator.clipboard is undefined on any non-secure origin, so
      // this fires for a self-hosted install reached over plain http — and the
      // button this controller now serves reveals a token exactly once. A user
      // who believes the copy worked navigates away and has to rotate, breaking
      // whatever client was already configured.
      this.element.textContent = "Copy failed — select the value and copy it"
      this.restore(original, 5000)
    }
  }

  restore(label, delay) {
    clearTimeout(this.restoreTimer)
    this.restoreTimer = setTimeout(() => { this.element.textContent = label }, delay)
  }
}
