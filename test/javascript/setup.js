import { afterEach, beforeEach, vi } from "vitest"
import { installBrowserStandIns, removeClipboard } from "./support/browser.js"
import { CSRF_TOKEN } from "./support/dom.js"
import { stubFetch } from "./support/fetch.js"
import { resetSupport } from "./support/state.js"

const INITIAL_URL = window.location.href

installBrowserStandIns(window)

// Every test starts from the page skeleton the layout renders and the controllers assume:
//
// - the CSRF meta tag, which helpers/api.js, collection_controller.js, decks_controller.js and
//   set_import_controller.js read with no null check — absent, the three controllers throw and
//   requestJson reports every request as one that "didn't reach the server";
// - an empty #flash-messages, which helpers/flash.js writes into and silently skips without;
// - window.Turbo, with a mock `visit` (card_search_controller.js, printing_picker_controller.js).
//
// fetch starts stubbed with no reply queued, so a test that never calls stubFetch still fails on
// any request its controller makes — requestJson would otherwise swallow the failure into a flash.
beforeEach(() => {
  stubFetch()
  document.head.innerHTML = `<meta name="csrf-token" content="${CSRF_TOKEN}">`
  document.body.innerHTML = `<div id="flash-messages"></div>`
  window.Turbo = { visit: vi.fn() }
})

// jsdom keeps one window per test file, so whatever a test leaves in it reaches the next test:
// storage (deck_compare_controller.js keeps its selection in sessionStorage), the URL
// (deck_diff_filter_controller.js rewrites it with history.replaceState) and fake timers.
afterEach(() => {
  try {
    resetSupport()
  } finally {
    document.head.innerHTML = ""
    document.body.innerHTML = ""
    delete window.Turbo
    removeClipboard()
    sessionStorage.clear()
    localStorage.clear()
    history.replaceState(null, "", INITIAL_URL)
    vi.useRealTimers()
  }
})
