import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu", "toggle"]

  // Issue #105: the hamburger's aria-expanded was written once in the markup and never again, so a
  // screen reader was told the menu was shut for as long as it was open.
  toggle() {
    const open = this.menuTarget.classList.toggle("navbar-menu--open")

    // Guarded rather than assumed. Ui::NavbarShell declares the target and every navbar goes
    // through it, so this is never missing today — but the menu must stay toggleable in a variant
    // that has no hamburger, and a missing target is a throw Stimulus swallows: the menu would
    // open once and then look broken with nothing on screen saying why.
    if (this.hasToggleTarget) this.toggleTarget.setAttribute("aria-expanded", String(open))
  }
}
