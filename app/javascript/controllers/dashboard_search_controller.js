import { Controller } from "@hotwired/stimulus"

// Dashboard spotlight search: debounces the query into a Turbo Frame and makes the resulting
// options keyboard-navigable. The options live inside the frame, so they are re-collected on
// every frame load rather than cached at connect.
export default class extends Controller {
  static targets = ["input", "form", "panel"]
  static values = { delay: { type: Number, default: 300 }, minLength: { type: Number, default: 2 } }

  connect() {
    this.options = []
    this.activeIndex = -1
    this.dismissed = false
    this.element.addEventListener("turbo:frame-load", this.#frameLoaded)
  }

  disconnect() {
    clearTimeout(this.timeout)
    this.element.removeEventListener("turbo:frame-load", this.#frameLoaded)
  }

  search() {
    clearTimeout(this.timeout)

    if (this.inputTarget.value.trim().length < this.minLengthValue) {
      this.#clear()
      return
    }

    // A fresh request is about to be scheduled: any earlier dismissal no longer applies.
    this.dismissed = false
    this.timeout = setTimeout(() => this.formTarget.requestSubmit(), this.delayValue)
  }

  next(event) {
    if (this.options.length === 0) return

    event.preventDefault()
    this.#activate((this.activeIndex + 1) % this.options.length)
  }

  previous(event) {
    if (this.options.length === 0) return

    event.preventDefault()
    // From the initial state (activeIndex -1), ↑ must land on the LAST option, so -1 is treated as
    // one past the end. Plain (activeIndex - 1 + length) % length would land two short of it.
    const from = this.activeIndex < 0 ? this.options.length : this.activeIndex
    this.#activate((from - 1 + this.options.length) % this.options.length)
  }

  // Enter opens the highlighted option. With nothing highlighted it falls through, so the form
  // submits and the panel just refreshes.
  open(event) {
    const option = this.options[this.activeIndex]
    if (!option) return

    event.preventDefault()
    option.click()
  }

  close(event) {
    if (event) event.preventDefault()

    this.inputTarget.value = ""
    this.#clear()
  }

  clickOutside(event) {
    if (this.element.contains(event.target)) return

    this.#collapse()
  }

  // Coming back to the field undoes an earlier dismissal. Without this, #dismissed is only ever
  // cleared by an `input` event, so a user who clicked away and clicked back would find Enter and
  // the arrow keys dead until they edited the query text. The panel still holds the last results,
  // so restore them rather than making the user retype.
  resume() {
    if (!this.dismissed) return

    this.dismissed = false
    this.#collectOptions()
    this.#setExpanded(this.panelTarget.textContent.trim().length > 0)
  }

  // ⌘K / Ctrl+K / "/" focus the field. Stimulus key filters can't express modifiers, so both
  // shortcuts share one handler.
  shortcut(event) {
    const isSlash = event.key === "/"
    const isCommandK = event.key === "k" && (event.metaKey || event.ctrlKey)
    if (!isSlash && !isCommandK) return
    if (isSlash && this.#isTyping(event.target)) return

    event.preventDefault()
    this.inputTarget.focus()
    this.inputTarget.select()
  }

  #frameLoaded = () => {
    // A request already in flight when the panel was dismissed can still land afterwards (a 304
    // never even fires this listener, but a 200 does) — #dismissed is what stops it from
    // reopening what the user just closed. Bail before collecting the options too, not just
    // before reopening: #collapse emptied them on purpose, and refilling them here would leave
    // the arrow keys walking a hidden panel and Enter navigating to a row nobody ever saw.
    if (this.dismissed) return

    this.#collectOptions()
    this.#setExpanded(this.panelTarget.textContent.trim().length > 0)
  }

  #collectOptions() {
    this.#deactivate()
    this.options = Array.from(this.panelTarget.querySelectorAll("[role=option]"))
  }

  #activate(index) {
    this.#deactivate()
    this.activeIndex = index

    const option = this.options[index]
    option.classList.add("is-active")
    // aria-activedescendant only tells assistive tech where the focus ring is; aria-selected is
    // what makes it announce the row as the selected one.
    option.setAttribute("aria-selected", "true")
    option.scrollIntoView({ block: "nearest" })
    this.inputTarget.setAttribute("aria-activedescendant", option.id)
  }

  // Drops the highlight from whatever currently carries it. Called before every #activate, and
  // before the options are replaced or dropped — otherwise a row kept its `is-active` styling
  // while activeIndex said nothing was highlighted, and #resume brought that mismatch back.
  #deactivate() {
    this.options.forEach((option) => {
      option.classList.remove("is-active")
      option.setAttribute("aria-selected", "false")
    })
    this.activeIndex = -1
    this.inputTarget.removeAttribute("aria-activedescendant")
  }

  #clear() {
    const frame = this.panelTarget.querySelector("turbo-frame")
    if (frame) frame.innerHTML = ""

    this.#collapse()
  }

  #collapse() {
    // Cancels a debounce still in flight: without this, a dismissed panel reopens when the
    // pending request lands and #frameLoaded sees content. The timer is only half the story —
    // a request already sent to the server keeps running after clearTimeout, so #dismissed also
    // tells #frameLoaded not to reopen once that response arrives.
    clearTimeout(this.timeout)
    this.dismissed = true
    this.#deactivate()
    this.options = []
    this.#setExpanded(false)
  }

  #setExpanded(expanded) {
    this.panelTarget.classList.toggle("spotlight-panel-open", expanded)
    this.inputTarget.setAttribute("aria-expanded", expanded ? "true" : "false")
    if (!expanded) this.inputTarget.removeAttribute("aria-activedescendant")
  }

  #isTyping(target) {
    return target.matches("input, textarea, select, [contenteditable=true]")
  }
}
