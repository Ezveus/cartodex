import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "hiddenField", "results"]

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

  select(event) {
    this.hiddenFieldTarget.value = event.currentTarget.dataset.cardId
    this.inputTarget.value = event.currentTarget.dataset.cardName
    this.resultsTarget.innerHTML = ""
  }

  async #fetchResults(query) {
    const response = await fetch(`/api/cards?q=${encodeURIComponent(query)}&type=Pokémon`, {
      credentials: "same-origin"
    })

    if (!response.ok) return
    const cards = await response.json()

    // Deduplicate by name, keep first match
    const seen = new Set()
    const unique = cards.filter(c => {
      if (seen.has(c.name)) return false
      seen.add(c.name)
      return true
    })

    this.#renderResults(unique)
  }

  #renderResults(cards) {
    if (cards.length === 0) {
      this.resultsTarget.innerHTML = '<div class="archetype-search-empty">No Pokémon found</div>'
      return
    }

    this.resultsTarget.innerHTML = cards.map(card => `
      <div class="archetype-search-item"
           data-action="click->pokemon-select#select"
           data-card-id="${card.id}"
           data-card-name="${this.#escape(card.name)}">
        <strong>${this.#escape(card.name)}</strong>
        <span class="archetype-search-pokemon">${this.#escape(card.set_name)} ${this.#escape(card.set_number)}</span>
      </div>
    `).join("")
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
