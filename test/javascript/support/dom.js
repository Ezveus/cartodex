// The CSRF token every test page carries in its meta tag (test/javascript/setup.js), for a test
// asserting the header requestJson sends.
export const CSRF_TOKEN = "test-csrf-token"

// The flashes helpers/flash.js wrote into #flash-messages, as { text, kind }, kind being
// "notice" or "alert" — the two helpers/flash.js writes — and null for any other class (the
// server-rendered `flash-info`, say), so a helper writing a third class does not pass as one of
// them.
export function flashMessages() {
  return Array.from(document.querySelectorAll("#flash-messages > .flash"), (flash) => ({
    text: flash.textContent,
    kind: flash.classList.contains("flash-alert") ? "alert" : flash.classList.contains("flash-notice") ? "notice" : null
  }))
}
