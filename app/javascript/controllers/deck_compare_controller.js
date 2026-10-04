import { Controller } from "@hotwired/stimulus"

// The selection is kept in sessionStorage rather than in the page, so that it survives what the
// listings do to their own DOM: a filter swapping the grid frame, a pager, and above all a move
// from one listing to another — picking a shared deck on /decks/shared, then one of your own on
// /decks, is the comparison this exists for. Per tab, and gone with it. A stored key can outlive
// its deck (deleted, or made private): DecksController#compare drops it from the comparison and
// names it back in a `data-deck-compare-gone` element, which connect() prunes from the selection.
const STORAGE_KEY = "cartodex:deck-compare"

// Lets the reader pick 2 to `max` decks across the deck listings and the shared deck page, then
// jump to the compare page. Every surface is a target of this one controller:
// - `checkbox`: a deck card's box, `value` the deck key, `data-deck-name` its label in the bar;
// - `toggle`: the shared deck page's "Add to comparison" button, `data-deck-key`/`-name`;
// - `bar`, `count`, `list`, `button`: Decks::CompareBar.
export default class extends Controller {
  static targets = ["checkbox", "toggle", "bar", "count", "list", "button"]
  static values = { compareUrl: String, max: { type: Number, default: 4 } }

  connect() {
    this.selection = this.#load()
    this.#pruneGone()
    this.update()
  }

  // A deck card broadcast into the grid by an import arrives after connect. Stimulus also calls
  // this for every target present on connect — before connect() itself, hence the guard.
  checkboxTargetConnected() {
    if (this.selection) this.update()
  }

  toggle(event) {
    const box = event.target
    this.#set(box.value, box.dataset.deckName, box.checked)
  }

  toggleDeck(event) {
    const { deckKey, deckName } = event.currentTarget.dataset
    this.#set(deckKey, deckName, !this.#has(deckKey))
  }

  remove(event) {
    this.#set(event.currentTarget.dataset.deckKey, null, false)
  }

  // Also wired to turbo:frame-load on the listings' grid frames: filtering swaps the checkboxes
  // in unchecked, and only the stored selection knows which of the new ones to tick.
  update() {
    const count = this.selection.length
    const full = count >= this.maxValue

    this.checkboxTargets.forEach((box) => {
      box.checked = this.#has(box.value)
      box.disabled = !box.checked && full
    })

    this.toggleTargets.forEach((button) => {
      const selected = this.#has(button.dataset.deckKey)
      button.setAttribute("aria-pressed", String(selected))
      button.textContent = selected ? "Remove from comparison" : "Add to comparison"
      button.disabled = !selected && full
    })

    if (this.hasCountTarget) this.countTarget.textContent = count
    if (this.hasListTarget) this.#renderList()
    if (this.hasBarTarget) this.barTarget.classList.toggle("is-visible", count > 0)
    if (this.hasButtonTarget) this.buttonTarget.disabled = count < 2 || count > this.maxValue
  }

  compare(event) {
    event.preventDefault()
    if (this.selection.length < 2 || this.selection.length > this.maxValue) return

    const params = new URLSearchParams()
    this.selection.forEach(({ key }) => params.append("ids[]", key))
    window.location.href = `${this.compareUrlValue}?${params.toString()}`
  }

  clear() {
    this.selection = []
    this.#save()
    this.update()
  }

  #set(key, name, selected) {
    if (!key) return

    if (selected && !this.#has(key) && this.selection.length < this.maxValue) {
      this.selection.push({ key, name: name || key })
    } else if (!selected) {
      this.selection = this.selection.filter((entry) => entry.key !== key)
    }

    this.#save()
    this.update()
  }

  // The carrier may be this element itself (the compare page's bare instance) or inside it (the
  // compare bar on the page a refused comparison redirects to).
  #pruneGone() {
    const carriers = [this.element, ...this.element.querySelectorAll("[data-deck-compare-gone]")]
      .filter((node) => node.hasAttribute("data-deck-compare-gone"))
    if (carriers.length === 0) return

    const gone = new Set(carriers.flatMap((node) => {
      try {
        const keys = JSON.parse(node.dataset.deckCompareGone)
        return Array.isArray(keys) ? keys : []
      } catch {
        return []
      }
    }))

    this.selection = this.selection.filter(({ key }) => !gone.has(key))
    this.#save()
  }

  #has(key) {
    return this.selection.some((entry) => entry.key === key)
  }

  // Built with the DOM rather than innerHTML: a deck name is whatever its owner typed.
  #renderList() {
    const items = this.selection.map(({ key, name }) => {
      const item = document.createElement("li")
      item.className = "deck-compare-bar-item"

      const label = document.createElement("span")
      label.textContent = name
      item.append(label)

      const remove = document.createElement("button")
      remove.type = "button"
      remove.className = "deck-compare-bar-remove"
      remove.textContent = "×"
      remove.setAttribute("aria-label", `Remove ${name} from the comparison`)
      remove.dataset.deckKey = key
      remove.dataset.action = "deck-compare#remove"
      item.append(remove)

      return item
    })

    this.listTarget.replaceChildren(...items)
  }

  // Storage can throw (private windows, blocked site data) or hold anything; either way the
  // reader starts from an empty selection rather than from a broken bar.
  #load() {
    try {
      const parsed = JSON.parse(window.sessionStorage.getItem(STORAGE_KEY) || "[]")
      if (!Array.isArray(parsed)) return []
      return parsed
        .filter((entry) => entry && typeof entry.key === "string")
        .map(({ key, name }) => ({ key, name: typeof name === "string" ? name : key }))
        .slice(0, this.maxValue)
    } catch {
      return []
    }
  }

  #save() {
    try {
      window.sessionStorage.setItem(STORAGE_KEY, JSON.stringify(this.selection))
    } catch {
      // The selection still works for this page; it just will not follow the reader.
    }
  }
}
