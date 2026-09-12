import { Controller } from "@hotwired/stimulus"

const FILTER_CLASS = "is-diff-only"
const FILTER_PARAM = "diff"

// The "Differences only" checkbox on the compare page. Separate from deck-compare, which is
// the selection controller on the decks index and shares nothing with this but a page name.
//
// It hides nothing itself: one class on the container drives every rule, so the server can
// render the filtered state straight from ?diff=1 — no flash of the full table on a shared
// link — and this only has to keep that class and the query parameter agreeing with the box.
export default class extends Controller {
  toggle(event) {
    const on = event.target.checked

    this.element.classList.toggle(FILTER_CLASS, on)
    this.#writeParam(on)
  }

  // replaceState, not pushState: the filter is a way of reading one page, not a page of its
  // own, so Back belongs to wherever the reader came from rather than to their last tick.
  #writeParam(on) {
    const url = new URL(window.location.href)

    if (on) {
      url.searchParams.set(FILTER_PARAM, "1")
    } else {
      url.searchParams.delete(FILTER_PARAM)
    }

    window.history.replaceState(window.history.state, "", url)
  }
}
