import { Controller } from "@hotwired/stimulus"

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
        const { error } = await response.json()
        this.#showFlash("alert", error || "Import failed.")
      }
    } catch (e) {
      this.#showFlash("alert", "Import request failed.")
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

  #showFlash(type, message) {
    const container = document.getElementById("flash-messages")
    if (!container) return
    const div = document.createElement("div")
    div.className = `flash flash-${type}`
    div.dataset.controller = "flash"
    div.textContent = message
    container.appendChild(div)
  }

  #escapeHtml(text) {
    const div = document.createElement("div")
    div.textContent = text
    return div.innerHTML
  }
}
