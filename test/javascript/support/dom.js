// The CSRF token every test page carries in its meta tag (test/javascript/setup.js), for a test
// asserting the header requestJson sends.
export const CSRF_TOKEN = "test-csrf-token"

// The flashes helpers/flash.js wrote into #flash-messages, as { text, kind }, kind being
// "notice" or "alert".
export function flashMessages() {
  return Array.from(document.querySelectorAll("#flash-messages > .flash"), (flash) => ({
    text: flash.textContent,
    kind: flash.classList.contains("flash-alert") ? "alert" : "notice"
  }))
}
