import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog", "resultInput", "archetypeInput", "archetypeId", "archetypeResults", "notesInput", "resultBtn"]
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

  searchArchetypes() {
    clearTimeout(this.searchTimeout)
    const query = this.archetypeInputTarget.value.trim()

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
  }

  async submit(event) {
    event.preventDefault()

    const result = this.resultInputTarget.value
    if (!result) return

    const token = document.querySelector('meta[name="csrf-token"]').content
    const body = {
      deck_result: {
        result: result,
        archetype_id: this.archetypeIdTarget.value || null,
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

  async #fetchArchetypes(query) {
    const response = await fetch(`/api/archetypes?q=${encodeURIComponent(query)}`, {
      credentials: "same-origin"
    })

    if (!response.ok) return
    const archetypes = await response.json()
    this.#renderArchetypeResults(archetypes)
  }

  #renderArchetypeResults(archetypes) {
    if (archetypes.length === 0) {
      this.archetypeResultsTarget.innerHTML = '<div class="archetype-search-empty">No archetypes found</div>'
      return
    }

    const html = archetypes.map(a => `
      <div class="archetype-search-item"
           data-action="click->result-modal#selectArchetype"
           data-archetype-id="${a.id}"
           data-archetype-name="${this.#escape(a.name)}">
        <strong>${this.#escape(a.name)}</strong>
        <span class="archetype-search-pokemon">${this.#escape(a.primary_pokemon)}${a.secondary_pokemon ? ' / ' + this.#escape(a.secondary_pokemon) : ''}</span>
      </div>
    `).join("")

    this.archetypeResultsTarget.innerHTML = html
  }

  #updateStats(stats) {
    const container = document.querySelector(".deck-show-stats")
    if (!container) return
    const values = container.querySelectorAll(".stat-value")
    // Order: cards, wins, losses, draws, timeouts
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
  }

  #escape(text) {
    const div = document.createElement("div")
    div.textContent = text || ""
    return div.innerHTML
  }
}
