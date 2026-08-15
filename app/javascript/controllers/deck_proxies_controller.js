import { Controller } from "@hotwired/stimulus"

// Keeps the deck header's "Proxies" badge in step with the allocation steppers.
//
// The badge is derived from the deck's cards, which the page edits in place, and it sits in the
// `deck-header` turbo frame — outside the elements doing the editing, so no amount of bubbling
// reaches it on its own. This controller sits on their common ancestor and relays the deck-wide
// answer each write already returns. The server stays the source of truth; nothing is recomputed
// here from the DOM.
//
// The badge is rendered on every load, hidden when it does not apply, so there is always an
// element to toggle.
export default class extends Controller {
  static targets = ["badge"]

  toggle({ detail: { hasProxies } }) {
    if (!this.hasBadgeTarget) return
    this.badgeTarget.hidden = !hasProxies
  }
}
