import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = { url: String }

  async copy() {
    try {
      const response = await fetch(this.urlValue, { credentials: "same-origin" })
      const { text } = await response.json()
      await navigator.clipboard.writeText(text)

      const original = this.element.textContent
      this.element.textContent = "Copied!"
      setTimeout(() => { this.element.textContent = original }, 2000)
    } catch (e) {
      console.error("Clipboard copy failed:", e)
    }
  }
}
