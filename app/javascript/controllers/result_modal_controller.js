import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "dialog", "resultInput", "archetypeInput", "archetypeId", "archetypeResults",
    "notesInput", "resultBtn", "createSection", "primaryInput", "primaryId",
    "primaryResults", "secondaryInput", "secondaryId", "secondaryResults"
  ]
  static values = { deckId: Number }

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
    this.#reset()
  }

  selectResult(event) {
    this.resultBtnTargets.forEach(btn => btn.classList.remove("active"))
    event.currentTarget.classList.add("active")
    this.resultInputTarget.value = event.currentTarget.dataset.result
  }

  // --- Archetype search ---

  searchArchetypes() {
    clearTimeout(this.searchTimeout)
    const query = this.archetypeInputTarget.value.trim()
    this.archetypeIdTarget.value = ""

    if (query.length < 2) {
      this.archetypeResultsTarget.innerHTML = ""
      return
    }

    this.searchTimeout = setTimeout(() => this.#fetchArchetypes(query), 300)
  }

  selectArchetype(event) {
    this.archetypeIdTarget.value = event.currentTarget.dataset.archetypeId
    this.archetypeInputTarget.value = event.currentTarget.dataset.archetypeName
    this.archetypeResultsTarget.innerHTML = ""
    this.#hideCreateSection()
  }

  showCreateForm() {
    this.archetypeResultsTarget.innerHTML = ""
    this.createSectionTarget.style.display = "block"
  }

  cancelCreate() {
    this.#hideCreateSection()
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

  // --- Submit ---

  async submit(event) {
    event.preventDefault()

    const result = this.resultInputTarget.value
    if (!result) return

    let archetypeId = this.archetypeIdTarget.value

    // If create section is visible and no archetype selected, create one first
    if (!archetypeId && this.createSectionTarget.style.display !== "none" && this.primaryIdTarget.value) {
      archetypeId = await this.#createArchetype()
      if (!archetypeId) return
    }

    const token = document.querySelector('meta[name="csrf-token"]').content
    const body = {
      deck_result: {
        result,
        archetype_id: archetypeId || null,
        notes: this.notesInputTarget.value,
        played_at: new Date().toISOString()
      }
    }

    const response = await fetch(`/api/decks/${this.deckIdValue}/results`, {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      credentials: "same-origin",
      body: JSON.stringify(body)
    })

    if (response.ok) {
      const data = await response.json()
      this.close()
      this.#updateStats(data.deck_stats)
    }
  }

  // --- Private ---

  async #createArchetype() {
    const token = document.querySelector('meta[name="csrf-token"]').content
    const body = {
      primary_pokemon_id: this.primaryIdTarget.value,
      secondary_pokemon_id: this.secondaryIdTarget.value || null
    }

    const response = await fetch("/api/archetypes", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": token },
      credentials: "same-origin",
      body: JSON.stringify(body)
    })

    if (response.ok || response.status === 201) {
      const archetype = await response.json()
      return archetype.id
    }
    return null
  }

  async #fetchArchetypes(query) {
    const response = await fetch(`/api/archetypes?q=${encodeURIComponent(query)}`, {
      credentials: "same-origin"
    })

    if (!response.ok) return
    const archetypes = await response.json()
    this.#renderArchetypeResults(archetypes, query)
  }

  #renderArchetypeResults(archetypes, query) {
    let html = archetypes.map(a => `
      <div class="archetype-search-item"
           data-action="click->result-modal#selectArchetype"
           data-archetype-id="${a.id}"
           data-archetype-name="${this.#escape(a.name)}">
        <strong>${this.#escape(a.name)}</strong>
        <span class="archetype-search-pokemon">${this.#escape(a.primary_pokemon)}${a.secondary_pokemon ? ' / ' + this.#escape(a.secondary_pokemon) : ''}</span>
      </div>
    `).join("")

    html += `
      <div class="archetype-search-item archetype-create-item"
           data-action="click->result-modal#showCreateForm">
        <strong>+ Create new archetype</strong>
      </div>
    `

    this.archetypeResultsTarget.innerHTML = html
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

      resultsTarget.innerHTML = unique.map(card => `
        <div class="archetype-search-item"
             data-action="click->result-modal#select${prefix === 'primary' ? 'Primary' : 'Secondary'}"
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

  #updateStats(stats) {
    const container = document.querySelector(".deck-show-stats")
    if (!container) return
    const values = container.querySelectorAll(".stat-value")
    if (values[1]) values[1].textContent = stats.wins
    if (values[2]) values[2].textContent = stats.losses
    if (values[3]) values[3].textContent = stats.draws
    if (values[4]) values[4].textContent = stats.timeouts
  }

  #reset() {
    this.resultInputTarget.value = ""
    this.archetypeIdTarget.value = ""
    this.archetypeInputTarget.value = ""
    this.archetypeResultsTarget.innerHTML = ""
    this.notesInputTarget.value = ""
    this.resultBtnTargets.forEach(btn => btn.classList.remove("active"))
    this.#hideCreateSection()
  }

  #escape(text) {
    const div = document.createElement("div")
    div.textContent = text || ""
    return div.innerHTML
  }
}
