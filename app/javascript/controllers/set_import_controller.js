import { Controller } from "@hotwired/stimulus"
import { flashAlert } from "helpers/flash"

export default class extends Controller {
  static targets = ["url", "submit", "list"]

  async import(event) {
    event.preventDefault()
    const url = this.urlTarget.value.trim()
    if (!url) return

    this.submitTarget.disabled = true
    this.submitTarget.value = "Importing…"

    try {
      const token = document.querySelector('meta[name="csrf-token"]').content
      const form = this.element.querySelector("form")
      const response = await fetch(form.action, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
        credentials: "same-origin",
        body: JSON.stringify({ url })
      })

      if (response.ok) {
        const { import_id, set_code } = await response.json()
        this.urlTarget.value = ""
        this.#addImportingEntry(import_id, set_code)
      } else {
        // This endpoint answers with a single `error`, not the `errors` array
        // the rest of the API uses, so it reads its own body rather than going
        // through helpers/api.
        const { error } = await response.json()
        flashAlert(error || "Import failed.")
      }
    } catch (e) {
      flashAlert("Import request failed.")
    } finally {
      this.submitTarget.disabled = false
      this.submitTarget.value = "Import from Limitless"
    }
  }

  #addImportingEntry(importId, name) {
    const item = document.createElement("li")
    item.id = `importing-set-${importId}`
    item.classList.add("importing-item")
    item.innerHTML = `<span class="importing-spinner"></span> ${this.#escapeHtml(name)}`
    this.listTarget.appendChild(item)
    this.listTarget.closest(".importing-section").style.display = "block"
  }

  #escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
