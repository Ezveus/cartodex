import { Controller } from "@hotwired/stimulus"
import { requestJson } from "helpers/api"

// Archetype picker for the deck form. Searches existing archetypes, creates new
// ones inline, and can infer one from the deck's line-up via the "Suggest"
// button. The chosen archetype's id is written to a hidden field submitted with
// the deck form.
export default class extends Controller {
  static targets = [
    "input", "archetypeId", "results", "createSection",
    "primaryInput", "primaryId", "primaryResults",
    "secondaryInput", "secondaryId", "secondaryResults"
  ]
  static values = { deckId: Number }

  connect() {
    this.handleClickOutside = this.#clickOutside.bind(this)
    document.addEventListener("click", this.handleClickOutside)
  }

  disconnect() {
    document.removeEventListener("click", this.handleClickOutside)
  }

  // --- Archetype search ---

  search() {
    clearTimeout(this.searchTimeout)
    const query = this.inputTarget.value.trim()
    this.archetypeIdTarget.value = ""

    if (query.length < 2) {
      this.resultsTarget.innerHTML = ""
      return
    }

    this.searchTimeout = setTimeout(() => this.#fetchArchetypes(query), 300)
  }

  selectArchetype(event) {
    this.archetypeIdTarget.value = event.currentTarget.dataset.archetypeId
    this.inputTarget.value = event.currentTarget.dataset.archetypeName
    this.resultsTarget.innerHTML = ""
    this.#hideCreateSection()
  }

  showCreateForm() {
    this.resultsTarget.innerHTML = ""
    this.createSectionTarget.style.display = "block"
  }

  cancelCreate() {
    this.#hideCreateSection()
  }

  // --- Suggestion from the deck line-up ---

  async suggest() {
    if (!this.deckIdValue) return

    const response = await fetch(`/api/decks/${this.deckIdValue}/suggested_archetype`, {
      credentials: "same-origin"
    })
    if (!response.ok) return
    const data = await response.json()

    if (data.matched) {
      this.archetypeIdTarget.value = data.archetype.id
      this.inputTarget.value = data.archetype.name
      this.resultsTarget.innerHTML = ""
      this.#hideCreateSection()
    } else if (data.suggested_primary) {
      this.#prefillCreate(data.suggested_primary, data.suggested_secondary)
    }
  }

  // --- Pokemon search for create ---

  searchPrimary() {
    this.#searchPokemon(this.primaryInputTarget, this.primaryResultsTarget, "primary")
  }

  searchSecondary() {
    this.#searchPokemon(this.secondaryInputTarget, this.secondaryResultsTarget, "secondary")
  }

  selectPrimary(event) {
    this.primaryIdTarget.value = event.currentTarget.dataset.cardId
    this.primaryInputTarget.value = event.currentTarget.dataset.cardName
    this.primaryResultsTarget.innerHTML = ""
  }

  selectSecondary(event) {
    this.secondaryIdTarget.value = event.currentTarget.dataset.cardId
    this.secondaryInputTarget.value = event.currentTarget.dataset.cardName
    this.secondaryResultsTarget.innerHTML = ""
  }

  async createArchetype() {
    if (!this.primaryIdTarget.value) return

    const archetype = await requestJson("/api/archetypes", {
      method: "POST",
      body: {
        primary_card_id: this.primaryIdTarget.value,
        secondary_card_id: this.secondaryIdTarget.value || null
      },
      failure: "Couldn't create the archetype"
    })
    if (!archetype) return

    this.archetypeIdTarget.value = archetype.id
    this.inputTarget.value = archetype.name
    this.#hideCreateSection()
  }

  // --- Private ---

  #prefillCreate(primary, secondary) {
    this.showCreateForm()
    this.primaryIdTarget.value = primary.id
    this.primaryInputTarget.value = primary.name
    if (secondary) {
      this.secondaryIdTarget.value = secondary.id
      this.secondaryInputTarget.value = secondary.name
    }
  }

  async #fetchArchetypes(query) {
    const response = await fetch(`/api/archetypes?q=${encodeURIComponent(query)}`, {
      credentials: "same-origin"
    })
    if (!response.ok) return
    const archetypes = await response.json()
    this.#renderArchetypeResults(archetypes)
  }

  #renderArchetypeResults(archetypes) {
    let html = archetypes.map(a => `
      <div class="archetype-search-item"
           data-action="click->archetype-picker#selectArchetype"
           data-archetype-id="${a.id}"
           data-archetype-name="${this.#escape(a.name)}">
        <strong>${this.#escape(a.name)}</strong>
        <span class="archetype-search-pokemon">${this.#formatCard(a.primary_card)}${a.secondary_card ? ' / ' + this.#formatCard(a.secondary_card) : ''}</span>
      </div>
    `).join("")

    html += `
      <div class="archetype-search-item archetype-create-item"
           data-action="click->archetype-picker#showCreateForm">
        <strong>+ Create new archetype</strong>
      </div>
    `

    this.resultsTarget.innerHTML = html
  }

  #searchPokemon(inputTarget, resultsTarget, prefix) {
    clearTimeout(this[`${prefix}Timeout`])
    const query = inputTarget.value.trim()

    if (query.length < 2) {
      resultsTarget.innerHTML = ""
      return
    }

    this[`${prefix}Timeout`] = setTimeout(async () => {
      const response = await fetch(`/api/cards?q=${encodeURIComponent(query)}&type=Pokémon`, {
        credentials: "same-origin"
      })
      if (!response.ok) return
      const cards = await response.json()

      const seen = new Set()
      const unique = cards.filter(c => {
        if (seen.has(c.name)) return false
        seen.add(c.name)
        return true
      })

      const action = prefix === "primary" ? "selectPrimary" : "selectSecondary"
      resultsTarget.innerHTML = unique.map(card => `
        <div class="archetype-search-item"
             data-action="click->archetype-picker#${action}"
             data-card-id="${card.id}"
             data-card-name="${this.#escape(card.name)}">
          <strong>${this.#escape(card.name)}</strong>
          <span class="archetype-search-pokemon">${this.#escape(card.set_name)} ${this.#escape(card.set_number)}</span>
        </div>
      `).join("")
    }, 300)
  }

  #hideCreateSection() {
    this.createSectionTarget.style.display = "none"
    this.primaryInputTarget.value = ""
    this.primaryIdTarget.value = ""
    this.primaryResultsTarget.innerHTML = ""
    this.secondaryInputTarget.value = ""
    this.secondaryIdTarget.value = ""
    this.secondaryResultsTarget.innerHTML = ""
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

  // An archetype now designates a printing, not just a name: show the set and
  // number alongside it so the picker matches what was actually chosen.
  #formatCard(card) {
    return `${this.#escape(card.name)} (${this.#escape(card.set_name)} ${this.#escape(card.set_number)})`
  }
}
