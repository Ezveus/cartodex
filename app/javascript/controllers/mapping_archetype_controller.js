import { Controller } from "@hotwired/stimulus"
import { requestJson } from "helpers/api"

// One line of the event import's "Decks in this event" table: create the archetype a Limitless
// deck is when the catalogue has none, without leaving the preview. Re-running the preview
// re-fetches the event, which is what opening the admin creator in another tab used to cost.
//
// Creation goes through POST /api/archetypes, the deck form's own endpoint — idempotent on the
// fingerprint pair and race-safe — so this adds no write path. Nothing is stored as a *mapping*
// here: the new archetype is only selected, and the confirm form stores it like any other choice.
export default class extends Controller {
  static targets = ["select", "createSection", "createButton", "primaryId", "secondaryId"]
  // The level the server rendered the line at: decide, check or confirmed.
  static values = { attention: String }

  toggle() {
    this.createSectionTarget.hidden = !this.createSectionTarget.hidden
  }

  // The section sits inside the form that stores every mapping and enqueues the run, and Enter in
  // a text field submits its form. Here that would be a click on "Confirm mappings and import".
  swallowEnter(event) {
    event.preventDefault()
  }

  // Typing in a card search forgets the card it held. card-select only ever *writes* its hidden id
  // — on a pick — so a pre-filled card whose text was erased stayed behind it and rode the POST: the
  // admin cleared the secondary and got an archetype with one anyway. A pick after typing writes
  // the id back, since card-select#select runs on the click, after every keystroke.
  forget(event) {
    const field = event.target.closest("[data-controller~='card-select']")
      ?.querySelector("[data-card-select-target='hiddenField']")
    if (field) field.value = ""
  }

  // The row says what the confirm POST will do with the line, re-read on every change. Empty is
  // undecided whatever the line was: on a confirmed line it *retracts* the stored mapping and on a
  // proposal it stores nothing, so either way the deck's rows are blocked — and a row still wearing
  // its quiet confirmed look over that was the page saying the opposite. The server's own value
  // restores the server's level; anything else is the admin's answer, and quiet.
  answered() {
    const value = this.selectTarget.value
    const initial = [...this.selectTarget.options].find(option => option.defaultSelected)?.value ?? ""
    const state = value === "" ? "decide" : value === initial ? this.attentionValue : "answered"
    const level = state === "answered" ? this.attentionValue : state

    for (const each of ["decide", "check", "confirmed"]) {
      this.element.classList.toggle(`standings-import-mapping--${each}`, each === level)
    }
    this.element.classList.toggle("standings-import-mapping--answered", state === "answered")
  }

  // Disabled for the length of the request, as the archetype picker's own button is: to say the
  // click landed, and to spend one POST rather than one per impatient click.
  async create() {
    if (!this.primaryIdTarget.value || this.createButtonTarget.disabled) return
    this.createButtonTarget.disabled = true

    try {
      const archetype = await requestJson("/api/archetypes", {
        method: "POST",
        body: {
          primary_card_id: this.primaryIdTarget.value,
          secondary_card_id: this.secondaryIdTarget.value || null
        },
        failure: "Couldn't create the archetype"
      })
      if (!archetype) return

      // Every line's select, not only this one: two Limitless decks can be one new archetype, and
      // the endpoint answering with an archetype that already existed leaves nothing to add.
      document.querySelectorAll("select[data-mapping-archetype-target='select']")
        .forEach(select => this.#offer(select, archetype))
      this.selectTarget.value = String(archetype.id)
      this.answered()
      this.createSectionTarget.hidden = true
    } finally {
      // finally, not after the await: requestJson answers null on every failure it reports, and a
      // button left disabled on the way out of one of those returns is dead for the life of the page.
      this.createButtonTarget.disabled = false
    }
  }

  // Inserted in name order, after "— Leave unmapped —", which is how the server printed the list.
  #offer(select, archetype) {
    const value = String(archetype.id)
    if ([...select.options].some(option => option.value === value)) return

    const option = new Option(archetype.name, value)
    const next = [...select.options].find(existing => existing.value !== "" && existing.text > archetype.name)
    select.add(option, next || null)
  }
}
