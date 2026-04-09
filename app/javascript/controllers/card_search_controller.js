import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "results"]
  static values = { deckId: Number }

  connect() {
    this.timeout = null
    this.handleClickOutside = this.#clickOutside.bind(this)
    document.addEventListener("click", this.handleClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.handleClickOutside)
  }

  search() {
    clearTimeout(this.timeout)
    const query = this.inputTarget.value.trim()

    if (query.length < 2) {
      this.resultsTarget.innerHTML = ""
      return
    }

    this.timeout = setTimeout(() => this.#fetchResults(query), 300)
  }

  async add(event) {
    const cardId = event.currentTarget.dataset.cardId
    const token = document.querySelector('meta[name="csrf-token"]').content

    const response = await fetch(`/api/decks/${this.deckIdValue}/cards`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      credentials: "same-origin",
      body: JSON.stringify({ deck_card: { card_id: cardId, quantity: 1 } })
    })

    if (response.ok) {
      this.inputTarget.value = ""
      this.resultsTarget.innerHTML = ""
      window.Turbo.visit(window.location.href, { action: "replace" })
    }
  }

  async #fetchResults(query) {
    const token = document.querySelector('meta[name="csrf-token"]').content
    const response = await fetch(`/api/cards?q=${encodeURIComponent(query)}`, {
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      credentials: "same-origin"
    })

    if (!response.ok) return

    const cards = await response.json()
    this.#renderResults(cards)
  }

  #renderResults(cards) {
    if (cards.length === 0) {
      this.resultsTarget.innerHTML = '<div class="card-search-empty">No cards found</div>'
      return
    }

    const html = cards.map(card => `
      <div class="card-search-result-item"
           data-card-preview-url="${this.#escape(card.image_url || '')}"
           data-card-preview-card-id="${card.id}"
           data-action="mouseenter->card-preview#show">
        <div class="card-search-result-info">
          <span class="card-search-result-name">${this.#escape(card.name)}</span>
          <span class="card-search-result-set">${this.#escape(card.set_name)} ${this.#escape(card.set_number)}</span>
          <span class="card-search-result-type">${this.#escape(card.card_type)}</span>
        </div>
        <button class="card-search-add-btn" data-action="card-search#add" data-card-id="${card.id}">+</button>
      </div>
    `).join("")

    this.resultsTarget.innerHTML = html
  }

  #clickOutside(event) {
    if (!this.element.contains(event.target)) {
      this.resultsTarget.innerHTML = ""
    }
  }

  #escape(text) {
    const div = document.createElement("div")
    div.textContent = text || ""
    return div.innerHTML
  }
}
