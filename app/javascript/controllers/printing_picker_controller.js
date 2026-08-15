import { Controller } from "@hotwired/stimulus"
import { requestJson } from "helpers/api"

// Switches a deck slot from one printing of a card to another. The menu is built from the API on
// open rather than rendered with the page: what it lists depends on the user's collection and on
// this deck, and a decklist would otherwise pay for sixty menus nobody opens.
export default class extends Controller {
  static targets = ["trigger", "menu"]
  static values = { deckId: Number, cardId: Number }

  async toggle(event) {
    event.preventDefault()
    this.menuTarget.hidden ? await this.open() : this.close()
  }

  async open() {
    const printings = await requestJson(this.#url("printings"), {
      failure: "Couldn't load the other printings of this card"
    })
    if (!printings) return

    this.menuTarget.replaceChildren(...printings.map((printing) => this.#option(printing, printings)))
    this.menuTarget.hidden = false
    this.triggerTarget.setAttribute("aria-expanded", "true")
  }

  close() {
    this.menuTarget.hidden = true
    this.triggerTarget.setAttribute("aria-expanded", "false")
  }

  closeOnOutsideClick(event) {
    if (this.element.contains(event.target)) return
    this.close()
  }

  async select(event) {
    const targetCardId = Number(event.currentTarget.dataset.printingCardId)

    const data = await requestJson(this.#url("printing"), {
      method: "PATCH",
      body: { printing: { card_id: targetCardId } },
      failure: "Couldn't switch this card's printing"
    })
    if (!data) return

    this.close()
    this.#absorbMergedRow(data)
    this.#rewriteRow(data)

    // The deck's "Proxies" badge derives from this very split, and it lives outside this row.
    this.dispatch("changed", { prefix: "deck-proxies", detail: { hasProxies: data.deck.has_proxies } })
  }

  get #row() {
    return this.element.closest("li.deck-card-item")
  }

  #url(segment) {
    return `/api/decks/${this.deckIdValue}/cards/${this.cardIdValue}/${segment}`
  }

  #option(printing, printings) {
    const button = document.createElement("button")
    button.type = "button"
    button.className = "printing-option"
    button.dataset.printingCardId = printing.card_id
    button.dataset.action = "printing-picker#select"

    const set = document.createElement("span")
    set.className = "printing-option-set"
    set.textContent = `${printing.set_name} ${printing.set_number}`
    button.append(set)

    const counts = document.createElement("span")
    counts.className = "printing-option-counts"
    counts.textContent = this.#countsLabel(printing)
    button.append(counts)

    if (printing.current) {
      button.classList.add("printing-option-current")
      button.disabled = true
      button.setAttribute("aria-current", "true")
    } else {
      const warning = this.#warningLabel(printing, printings)
      if (warning) {
        const note = document.createElement("span")
        note.className = "printing-option-warning"
        note.textContent = warning
        button.append(note)
      }
    }

    const item = document.createElement("li")
    item.append(button)
    return item
  }

  #countsLabel(printing) {
    const parts = [`${printing.owned} owned`]
    if (printing.owned > 0) parts.push(`${printing.available} free`)
    if (!printing.current && printing.in_deck > 0) parts.push(`${printing.in_deck} already in deck`)
    return parts.join(" · ")
  }

  // owned_copies is per exact printing, so a swap re-derives the backing against the target and
  // can legitimately turn real copies into proxies. Said before the write rather than after.
  #warningLabel(printing, printings) {
    if (printing.real_after === null) return null

    const current = printings.find((p) => p.current)
    const lost = (current?.real_after ?? 0) - printing.real_after
    if (lost <= 0) return null

    return `⚠ ${lost} real ${lost === 1 ? "copy becomes a proxy" : "copies become proxies"}`
  }

  // The target printing may already have a row of its own: the write merged the two, so the page
  // has to lose one. Its copies live on in the row we keep, hence a delta of zero — only the
  // section's unique count moves.
  #absorbMergedRow(data) {
    if (!data.merged) return

    const merged = document.querySelector(`li.deck-card-item[data-card-preview-card-id="${data.card.id}"]`)
    if (!merged || merged === this.#row) return

    merged.dispatchEvent(new CustomEvent("deck-card-quantity:changed", {
      bubbles: true,
      detail: { delta: 0, removed: true }
    }))
    merged.remove()
  }

  // Everything in the row that names the old printing. The row is identified by card id in three
  // places — the preview, the quantity stepper and the allocation stepper — and every one of them
  // would keep writing to the printing that is no longer there.
  #rewriteRow(data) {
    const row = this.#row

    row.dataset.cardPreviewCardId = data.card.id
    if (data.image_path) {
      row.dataset.cardPreviewUrl = data.image_path
    } else {
      delete row.dataset.cardPreviewUrl
    }
    row.dataset.deckCardQuantityCardIdValue = data.card.id
    row.dataset.deckCardQuantityQuantityValue = data.quantity
    row.querySelector(".deck-card-qty").textContent = data.quantity

    this.cardIdValue = data.card.id
    this.triggerTarget.textContent = `${data.card.set_name} ${data.card.set_number} ▾`

    const allocation = row.querySelector(".deck-card-alloc")
    if (!allocation) return

    allocation.dataset.deckCardOwnedCopiesCardIdValue = data.card.id
    allocation.dataset.deckCardOwnedCopiesOwnedValue = data.owned_copies
    allocation.dataset.deckCardOwnedCopiesMaxValue = data.max_owned
    allocation.querySelector(".deck-card-alloc-label").textContent =
      `${data.owned_copies} real · ${data.proxies} proxy`
    allocation.querySelector(".deck-card-warning").hidden = !data.over_allocated
  }
}
