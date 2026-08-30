import { Controller } from "@hotwired/stimulus"
import { requestJson } from "helpers/api"

export default class extends Controller {
  static targets = [
    "dialog", "archetypeInput", "archetypeId", "archetypeResults",
    "notesInput", "createSection", "primaryInput", "primaryId",
    "primaryResults", "secondaryInput", "secondaryId", "secondaryResults",
    "tournamentSelect"
  ]
  static values = { deckId: Number }

  open() {
    this.dialogTarget.showModal()
  }

  close() {
    this.dialogTarget.close()
    this.#reset()
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

  // --- Card search for create ---

  searchPrimary() {
    this.#searchCard(this.primaryInputTarget, this.primaryResultsTarget, "primary")
  }

  searchSecondary() {
    this.#searchCard(this.secondaryInputTarget, this.secondaryResultsTarget, "secondary")
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

    const result = this.#fieldValue("result")
    if (!result) return

    let archetypeId = this.archetypeIdTarget.value

    // If create section is visible and no archetype selected, create one first
    if (!archetypeId && this.createSectionTarget.style.display !== "none" && this.primaryIdTarget.value) {
      archetypeId = await this.#createArchetype()
      if (!archetypeId) return
    }

    const data = await requestJson(`/api/decks/${this.deckIdValue}/results`, {
      method: "POST",
      body: {
        deck_result: {
          result,
          match_format: this.#fieldValue("match_format"),
          score: this.#fieldValue("score") || null,
          archetype_id: archetypeId || null,
          tournament_id: this.hasTournamentSelectTarget ? (this.tournamentSelectTarget.value || null) : null,
          notes: this.notesInputTarget.value,
          played_at: new Date().toISOString()
        }
      },
      failure: "Couldn't log this result"
    })
    if (!data) return

    this.close()
    this.#updateStats(data.deck_stats)
  }

  // --- Private ---

  async #createArchetype() {
    const archetype = await requestJson("/api/archetypes", {
      method: "POST",
      body: {
        primary_card_id: this.primaryIdTarget.value,
        secondary_card_id: this.secondaryIdTarget.value || null
      },
      failure: "Couldn't create the archetype"
    })

    return archetype ? archetype.id : null
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
        <span class="archetype-search-pokemon">${this.#formatCard(a.primary_card)}${a.secondary_card ? ' / ' + this.#formatCard(a.secondary_card) : ''}</span>
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

  #searchCard(inputTarget, resultsTarget, prefix) {
    clearTimeout(this[`${prefix}Timeout`])
    const query = inputTarget.value.trim()

    if (query.length < 2) {
      resultsTarget.innerHTML = ""
      return
    }

    this[`${prefix}Timeout`] = setTimeout(async () => {
      const response = await fetch(`/api/cards?q=${encodeURIComponent(query)}`, {
        credentials: "same-origin"
      })
      if (!response.ok) return
      // Every type, and every printing: an archetype may designate a Trainer, and
      // which printing it designates is the user's choice to see.
      const cards = await response.json()

      resultsTarget.innerHTML = cards.map(card => `
        <div class="archetype-search-item"
             data-action="click->result-modal#select${prefix === 'primary' ? 'Primary' : 'Secondary'}"
             data-card-id="${card.id}"
             data-card-name="${this.#escape(card.name)}">
          <strong>${this.#escape(card.name)}</strong>
          <span class="archetype-search-pokemon">${this.#escape(card.card_type)} · ${this.#escape(card.set_name)} ${this.#escape(card.set_number)}</span>
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
    this.archetypeIdTarget.value = ""
    this.archetypeInputTarget.value = ""
    this.archetypeResultsTarget.innerHTML = ""
    this.notesInputTarget.value = ""
    if (this.hasTournamentSelectTarget) this.tournamentSelectTarget.value = ""
    this.#resetResultFields()
    this.#hideCreateSection()
  }

  // The result/format/score live in a nested match-result controller.
  #fieldValue(name) {
    const input = this.element.querySelector(`[name="deck_result[${name}]"]`)
    return input ? input.value : ""
  }

  #resetResultFields() {
    const el = this.element.querySelector('[data-controller~="match-result"]')
    if (!el) return
    const ctrl = this.application.getControllerForElementAndIdentifier(el, "match-result")
    if (ctrl) ctrl.reset()
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
