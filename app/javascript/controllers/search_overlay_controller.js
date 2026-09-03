import { Controller } from "@hotwired/stimulus"

// Owns the one way into the search that every page has: the navbar trigger and the ⌘K / "/"
// shortcuts. Lives on <body>, because the trigger is in the navbar and the field is either in the
// dialog it opens or somewhere down the page.
//
// A page renders at most one Search::Spotlight — the frame the results land in is addressed by
// id, so two would fight over it. Which one this controller reaches therefore never needs
// deciding: pages with a dialog have their field inside it, and the dashboard and the styleguide
// have theirs inline and no dialog at all. Same trigger, same shortcut, both ways.
export default class extends Controller {
  static targets = ["dialog", "field", "hint"]

  // Every hint on the page, not just the first: the styleguide renders the shipped trigger beside
  // the navbar's own, and one of the two left saying ⌘K on a PC would be the bug this fixes.
  connect() {
    this.hintTargets.forEach((hint) => (hint.textContent = this.#shortcutLabel()))
  }

  open(event) {
    if (!this.hasFieldTarget) return
    if (event) event.preventDefault()

    if (this.hasDialogTarget && !this.dialogTarget.open) this.dialogTarget.showModal()

    this.fieldTarget.focus()
    this.fieldTarget.select()
  }

  close() {
    if (this.hasDialogTarget && this.dialogTarget.open) this.dialogTarget.close()
  }

  // The backdrop of a modal <dialog> is the dialog element itself, so a click reported against it
  // rather than against its contents landed outside the panel.
  clickBackdrop(event) {
    if (event.target === this.dialogTarget) this.close()
  }

  // ⌘K / Ctrl+K / "/". Stimulus key filters can't express modifiers, so both shortcuts share one
  // handler.
  shortcut(event) {
    const isSlash = event.key === "/"
    const isCommandK = event.key === "k" && (event.metaKey || event.ctrlKey)
    if (!isSlash && !isCommandK) return
    if (isSlash && this.#isTyping(event.target)) return

    this.open(event)
  }

  // The hint is the only thing that tells a user the shortcut exists, so it must name a key their
  // keyboard has: shortcut() accepts ⌘K and Ctrl+K alike, and the markup can only ship one of
  // them. userAgentData first, since navigator.platform is deprecated and reports Intel on Apple
  // Silicon — either spelling still contains "mac".
  #shortcutLabel() {
    const platform = navigator.userAgentData?.platform || navigator.platform || ""

    return /mac|iphone|ipad|ipod/i.test(platform) ? "⌘K" : "Ctrl K"
  }

  #isTyping(target) {
    return target.matches("input, textarea, select, [contenteditable=true]")
  }
}
