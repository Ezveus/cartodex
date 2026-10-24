import { afterEach, beforeEach, vi } from "vitest"
import { CSRF_TOKEN } from "./support/dom.js"
import { resetSupport } from "./support/state.js"

// Every test starts from the page skeleton the layout renders and the controllers assume:
//
// - the CSRF meta tag, which helpers/api.js, collection_controller.js and decks_controller.js
//   read with no null check — absent, every write throws before reaching fetch;
// - an empty #flash-messages, which helpers/flash.js writes into and silently skips without;
// - window.Turbo, with a mock `visit` (card_search_controller.js, printing_picker_controller.js).
beforeEach(() => {
  document.head.innerHTML = `<meta name="csrf-token" content="${CSRF_TOKEN}">`
  document.body.innerHTML = `<div id="flash-messages"></div>`
  window.Turbo = { visit: vi.fn() }
})

afterEach(() => {
  try {
    resetSupport()
  } finally {
    document.head.innerHTML = ""
    document.body.innerHTML = ""
    delete window.Turbo
  }
})
