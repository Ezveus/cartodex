import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, text: String }

  async copy() {
    const original = this.element.textContent

    try {
      const { text, notice } = this.hasTextValue
        ? { text: this.textValue }
        : await (await fetch(this.urlValue, { credentials: "same-origin" })).json()

      // The server had nothing to copy and says why (a wishlist with nothing left to buy).
      // Leave the clipboard as it was rather than empty it.
      if (notice) {
        this.element.textContent = notice
        setTimeout(() => { this.element.textContent = original }, 3000)
        return
      }

      await navigator.clipboard.writeText(text)

      this.element.textContent = "Copied!"
      setTimeout(() => { this.element.textContent = original }, 2000)
    } catch (e) {
      console.error("Clipboard copy failed:", e)
      // Say so. navigator.clipboard is undefined on any non-secure origin, so
      // this fires for a self-hosted install reached over plain http — and the
      // button this controller now serves reveals a token exactly once. A user
      // who believes the copy worked navigates away and has to rotate, breaking
      // whatever client was already configured.
      this.element.textContent = "Copy failed — select the value and copy it"
      setTimeout(() => { this.element.textContent = original }, 5000)
    }
  }
}
