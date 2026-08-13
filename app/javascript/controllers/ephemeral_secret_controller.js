import { Controller } from "@hotwired/stimulus"

// Removes its element before the page can be restored from the browser's
// back/forward cache. data-turbo-temporary covers Turbo Drive's own snapshot
// cache, but a real unload — a cross-origin link, a data-turbo="false"
// navigation — hands the live DOM to the bfcache, which Turbo never sees. Back
// would then put a one-shot secret back on screen long after it was revealed.
export default class extends Controller {
  connect() {
    this.removeElement = () => this.element.remove()
    window.addEventListener("pagehide", this.removeElement)
  }

  disconnect() {
    window.removeEventListener("pagehide", this.removeElement)
  }
}
