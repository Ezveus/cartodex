import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String, text: String }

  async copy() {
    try {
      const text = this.hasTextValue
        ? this.textValue
        : (await (await fetch(this.urlValue, { credentials: "same-origin" })).json()).text
      await navigator.clipboard.writeText(text)

      const original = this.element.textContent
      this.element.textContent = "Copied!"
      setTimeout(() => { this.element.textContent = original }, 2000)
    } catch (e) {
      console.error("Clipboard copy failed:", e)
    }
  }
}
