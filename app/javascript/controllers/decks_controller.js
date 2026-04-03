import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["count"]

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
