import { Controller } from "@hotwired/stimulus"
import { requestJson, HandedOver } from "helpers/api"
import { flashAlert } from "helpers/flash"

export default class extends Controller {
  static targets = [
    "dialog", "archetypeInput", "archetypeId", "archetypeResults",
    "notesInput", "createSection", "primaryInput", "primaryId",
    "primaryResults", "secondaryInput", "secondaryId", "secondaryResults",
    "tournamentEntrySelect", "submitButton", "actions",
    "versionPrompt", "versionPromptText", "versionChoice"
  ]
  static values = { deckKey: String }

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
    // The printing, not the bare name: several cards share one, and the input
    // must say which of them the hidden id now holds.
    this.primaryInputTarget.value = event.currentTarget.dataset.cardLabel
    this.primaryResultsTarget.innerHTML = ""
  }

  selectSecondary(event) {
    this.secondaryIdTarget.value = event.currentTarget.dataset.cardId
    this.secondaryInputTarget.value = event.currentTarget.dataset.cardLabel
    this.secondaryResultsTarget.innerHTML = ""
  }

  // --- Submit ---

  // Disabled for the length of the submission. Nothing identifies two logged
  // results as a duplicate — two matches with the same score on the same day is
  // an ordinary evening — so a second POST is a second row, and the modal only
  // closes once the first answer is back. The button is what has to say no.
  //
  // It stays disabled past the answer in one case: the server asked which
  // version the match belongs to, and the prompt is now the only way forward.
  // cancelVersionChoice is what gives it back.
  async submit(event) {
    event.preventDefault()

    const result = this.#fieldValue("result")
    if (!result || this.submitButtonTarget.disabled) return
    this.submitButtonTarget.disabled = true
    let asking = false

    try {
      let archetypeId = this.archetypeIdTarget.value

      // If create section is visible and no archetype selected, create one first
      if (!archetypeId && this.createSectionTarget.style.display !== "none" && this.primaryIdTarget.value) {
        archetypeId = await this.#createArchetype()
        if (!archetypeId) return
      }

      // Kept whole for a resubmission, played_at included: the match was played
      // when Save was clicked, not when the question was answered.
      this.pendingResult = {
        result,
        match_format: this.#fieldValue("match_format"),
        score: this.#fieldValue("score") || null,
        archetype_id: archetypeId || null,
        tournament_entry_id: this.hasTournamentEntrySelectTarget ? (this.tournamentEntrySelectTarget.value || null) : null,
        notes: this.notesInputTarget.value,
        played_at: new Date().toISOString()
      }

      asking = await this.#post()
    } finally {
      // finally, not after the await: every failure requestJson reports comes
      // back as null and returns early, and a button left disabled on the way
      // out cannot be used to retry.
      if (!asking) this.submitButtonTarget.disabled = false
    }
  }

  // --- Version prompt ---

  // The same result again, now saying which version it belongs to. The choice
  // buttons are the double-submit guard here, for the reason Save is above:
  // "new" twice would be two results, and possibly two versions.
  async chooseVersion(event) {
    if (!this.pendingResult || this.versionChoiceTargets.some((button) => button.disabled)) return

    this.versionChoiceTargets.forEach((button) => { button.disabled = true })
    try {
      const asking = await this.#post(event.currentTarget.dataset.versionChoice)
      // Refused (a 422, a dead connection — already flashed): back to the form,
      // where whatever the server objected to can be corrected.
      if (!asking && this.dialogTarget.open) this.cancelVersionChoice()
    } finally {
      this.versionChoiceTargets.forEach((button) => { button.disabled = false })
    }
  }

  // Nothing was written: the 409 is the server refusing before any row, so
  // cancelling is only a matter of putting the form back.
  cancelVersionChoice() {
    this.pendingResult = null
    this.#hideVersionPrompt()
    this.submitButtonTarget.disabled = false
  }

  // --- Private ---

  // Posts the pending result, with the version choice once there is one.
  // Answers true when the server asked the question instead of saving, which
  // is the one outcome that leaves the modal waiting on the reader.
  async #post(versionChoice) {
    const body = { deck_result: this.pendingResult }
    if (versionChoice) body.version_choice = versionChoice

    const data = await requestJson(`/api/decks/${this.deckKeyValue}/results`, {
      method: "POST",
      body,
      failure: "Couldn't log this result",
      handOver: [409]
    })
    if (!data) return false

    if (data instanceof HandedOver) {
      if (data.body.error === "version_choice_required" && !versionChoice) {
        this.#showVersionPrompt(data.body)
        return true
      }
      // A 409 after a choice was sent would ask the same question forever.
      flashAlert("Couldn't log this result (HTTP 409)")
      return false
    }

    this.close()
    this.#updateStats(data.deck_stats)
    return false
  }

  #showVersionPrompt({ current_version: current, next_version: next }) {
    this.versionPromptTextTarget.textContent =
      `This deck's list has changed since version ${current}. Which list was this match played with?`
    const [createButton, attachButton] = this.versionChoiceTargets
    createButton.textContent = `Create version ${next}`
    attachButton.textContent = `Attach to version ${current}`

    this.actionsTarget.hidden = true
    this.versionPromptTarget.hidden = false
  }

  #hideVersionPrompt() {
    this.versionPromptTarget.hidden = true
    this.actionsTarget.hidden = false
  }

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
             data-card-label="${this.#formatCard(card)}">
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
    this.pendingResult = null
    this.#hideVersionPrompt()
    this.submitButtonTarget.disabled = false
    this.archetypeIdTarget.value = ""
    this.archetypeInputTarget.value = ""
    this.archetypeResultsTarget.innerHTML = ""
    this.notesInputTarget.value = ""
    if (this.hasTournamentEntrySelectTarget) this.tournamentEntrySelectTarget.value = ""
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
