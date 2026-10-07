import { Controller } from "@hotwired/stimulus"

// Tells the server a one-time announcement was seen, from the only place that knows: a page the
// member is looking at. The server cannot tell while rendering — a hover prefetch, the rest of a
// frame request's page and a response Turbo discards to reload after a deploy are all rendered
// and never shown. Connecting is not enough on its own either: a tab opened in the background
// (cmd/middle-click, a restored session) runs its scripts while nobody looks at it, so the
// acknowledgement waits until the document is visible. The element is data-turbo-temporary, so a
// page restored from Turbo's cache never brings it back to acknowledge twice.
//
// Silent on failure: a lost acknowledgement only means the announcement shows once more.
export default class extends Controller {
  static values = { url: String }

  connect() {
    if (document.visibilityState === "visible") {
      this.#acknowledge()
    } else {
      document.addEventListener("visibilitychange", this.#acknowledgeOnceVisible)
    }
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.#acknowledgeOnceVisible)
  }

  #acknowledgeOnceVisible = () => {
    if (document.visibilityState !== "visible") return

    document.removeEventListener("visibilitychange", this.#acknowledgeOnceVisible)
    this.#acknowledge()
  }

  #acknowledge() {
    const token = document.querySelector("meta[name=csrf-token]")?.content

    fetch(this.urlValue, {
      method: "DELETE",
      credentials: "same-origin",
      headers: token ? { "X-CSRF-Token": token } : {}
    }).catch(() => {})
  }
}
