import { Controller } from "@hotwired/stimulus"

// Tells the server a one-time announcement was seen, from the only place that knows: a page the
// member is looking at. The server cannot tell while rendering — a hover prefetch, the rest of a
// frame request's page and a response Turbo discards to reload after a deploy are all rendered
// and never shown. Connecting is the proof. The element is data-turbo-temporary, so a page
// restored from Turbo's cache never brings it back to acknowledge twice.
//
// Silent on failure: a lost acknowledgement only means the announcement shows once more.
export default class extends Controller {
  static values = { url: String }

  connect() {
    const token = document.querySelector("meta[name=csrf-token]")?.content

    fetch(this.urlValue, {
      method: "DELETE",
      credentials: "same-origin",
      headers: token ? { "X-CSRF-Token": token } : {}
    }).catch(() => {})
  }
}
