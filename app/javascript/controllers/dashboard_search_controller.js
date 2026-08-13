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
    this.#activate((this.activeIndex - 1 + this.options.length) % this.options.length)
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
    this.options = Array.from(this.panelTarget.querySelectorAll("[role=option]"))
    this.activeIndex = -1
    this.#setExpanded(this.panelTarget.textContent.trim().length > 0)
  }

  #activate(index) {
    this.options.forEach((option) => option.classList.remove("is-active"))
    this.activeIndex = index

    const option = this.options[index]
    option.classList.add("is-active")
    option.scrollIntoView({ block: "nearest" })
    this.inputTarget.setAttribute("aria-activedescendant", option.id)
  }

  #clear() {
    const frame = this.panelTarget.querySelector("turbo-frame")
    if (frame) frame.innerHTML = ""

    this.#collapse()
  }

  #collapse() {
    this.options = []
    this.activeIndex = -1
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
