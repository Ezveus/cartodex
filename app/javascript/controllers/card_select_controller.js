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
    // The printing, not the bare name: the hidden field now holds one exact
    // printing among several sharing a name, and an input showing only the name
    // would not say which one — the same label the form pre-fills on edit.
    this.inputTarget.value = event.currentTarget.dataset.cardLabel
    this.resultsTarget.innerHTML = ""
  }

  async #fetchResults(query) {
    const response = await fetch(`/api/cards?q=${encodeURIComponent(query)}`, {
      credentials: "same-origin"
    })

    if (!response.ok) return
    // No deduplication by name: which printing an archetype designates is the
    // user's choice, and collapsing them would hide every option but the first.
    this.#renderResults(await response.json())
  }

  #renderResults(cards) {
    if (cards.length === 0) {
      this.resultsTarget.innerHTML = '<div class="archetype-search-empty">No cards found</div>'
      return
    }

    this.resultsTarget.innerHTML = cards.map(card => `
      <div class="archetype-search-item"
           data-action="click->card-select#select"
           data-card-id="${card.id}"
           data-card-label="${this.#formatCard(card)}">
        <strong>${this.#escape(card.name)}</strong>
        <span class="archetype-search-pokemon">${this.#escape(card.card_type)} · ${this.#escape(card.set_name)} ${this.#escape(card.set_number)}</span>
      </div>
    `).join("")
  }

  // Mirrors Card#printing_label on the Ruby side, and archetype_picker's own
  // #formatCard: one card, one way of naming which printing it is.
  #formatCard(card) {
    return `${this.#escape(card.name)} (${this.#escape(card.set_name)} ${this.#escape(card.set_number)})`
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
