import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count", "importModal", "importName", "importDecklist", "importSubmit", "importingList"]

  connect() {
    this.loadDeckCount()
  }

  async loadDeckCount() {
    try {
      const response = await this.fetchWithToken('/api/decks')
      const data = await response.json()
      this.countTarget.textContent = data.length || 0
    } catch (error) {
      console.error('Error loading deck count:', error)
    }
  }

  async view() {
    // Will be implemented with deck list view
  }

  async create() {
    // Will be implemented with deck creation form
  }

  openImport(event) {
    event.preventDefault()
    this.importModalTarget.style.display = "block"
  }

  closeImport(event) {
    event.preventDefault()
    this.importModalTarget.style.display = "none"
  }

  async submitImport(event) {
    event.preventDefault()
    const name = this.importNameTarget.value.trim()
    const decklist = this.importDecklistTarget.value.trim()

    if (!name || !decklist) return

    this.importSubmitTarget.disabled = true
    this.importSubmitTarget.textContent = "Importing…"

    try {
      const response = await this.fetchWithToken('/api/decks/import', {
        method: 'POST',
        body: JSON.stringify({ name, decklist })
      })

      if (response.ok) {
        const { import_id } = await response.json()

        this.importModalTarget.style.display = "none"
        this.importNameTarget.value = ""
        this.importDecklistTarget.value = ""

        this.#addImportingEntry(import_id, name)
        this.#showFlash("notice", `Deck "${name}" is being imported…`)
      }
    } catch (error) {
      console.error('Error importing deck:', error)
    } finally {
      this.importSubmitTarget.disabled = false
      this.importSubmitTarget.textContent = "Import"
    }
  }

  #addImportingEntry(importId, name) {
    if (!this.hasImportingListTarget) return

    const item = document.createElement("li")
    item.id = `importing-${importId}`
    item.classList.add("importing-item")
    item.innerHTML = `<span class="importing-spinner"></span> ${this.#escapeHtml(name)}`
    this.importingListTarget.appendChild(item)
    this.importingListTarget.closest(".importing-section").style.display = "block"
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

  // Helper method to make authenticated API requests
  async fetchWithToken(url, options = {}) {
    const token = document.querySelector('meta[name="csrf-token"]').content
    const defaultOptions = {
      headers: {
        'Content-Type': 'application/json',
        'X-CSRF-Token': token
      },
      credentials: 'same-origin'
    }

    return fetch(url, { ...defaultOptions, ...options })
  }
}
