import { Controller } from "@hotwired/stimulus"

// A menu panel that opens under a trigger, closes on an outside click, on Escape, and before Turbo
// takes a snapshot of the page.
//
// The open class is a value rather than a literal because a caller may bring its own panel: every
// path below reads `openClassValue`, so a caller that overrides it gets a dropdown that actually
// closes. `trigger` is optional — Decks::ActionsDropdown and Decks::ExportDropdown declare no such
// target — and everything that touches it is guarded, because Stimulus reports a missing target by
// logging and swallowing the error, which would leave the panel open with nothing on screen saying
// why.
//
// The three document listeners are registered here rather than as `data-action` in the markup: the
// two existing callers' components are shared and unaware of them, and a close path that only some
// callers wire up is a close path that silently does not exist.
export default class extends Controller {
  static targets = ["menu", "trigger"]
  static values = { openClass: { type: String, default: "dropdown-menu--open" } }

  connect() {
    this.boundClose = this.close.bind(this)
    this.boundCloseOnEscape = this.closeOnEscape.bind(this)
    this.boundCloseNow = this.closeNow.bind(this)

    document.addEventListener("click", this.boundClose)
    document.addEventListener("keydown", this.boundCloseOnEscape)
    document.addEventListener("turbo:before-cache", this.boundCloseNow)
  }

  disconnect() {
    document.removeEventListener("click", this.boundClose)
    document.removeEventListener("keydown", this.boundCloseOnEscape)
    document.removeEventListener("turbo:before-cache", this.boundCloseNow)
  }

  toggle() {
    this.#render(!this.#open)
  }

  open() {
    this.#render(true)
  }

  // The outside-click handler: a click on the trigger or inside the panel is the panel's own
  // business, and closing on it would undo the very click that opened it.
  close(event) {
    if (this.element.contains(event.target)) return

    this.closeNow()
  }

  // Unconditional close, and the `turbo:before-cache` handler. A snapshot cached with the panel
  // open restores it open, floating over a page whose content has moved — and a restoration visit
  // serves that snapshot without re-requesting, so nothing repaints it away. Same reason the search
  // overlay closes itself before the snapshot (see the <body> data-action in ApplicationLayout).
  closeNow() {
    this.#render(false)
  }

  // Escape only speaks for a panel that is actually open: preventDefault from a closed one would
  // eat the key on every page that renders a dropdown, the search overlay's own Escape included.
  closeOnEscape(event) {
    if (event.key !== "Escape" || !this.#open) return

    event.preventDefault()
    this.closeNow()
  }

  get #open() {
    return this.menuTarget.classList.contains(this.openClassValue)
  }

  // The class first, aria second, and the order is load-bearing: `trigger` is optional, and a throw
  // on the way to it must not be able to strand the panel open. The guard makes the throw
  // impossible; the ordering makes it harmless anyway.
  #render(open) {
    this.menuTarget.classList.toggle(this.openClassValue, open)
    if (this.hasTriggerTarget) this.triggerTarget.setAttribute("aria-expanded", String(open))
  }
}
