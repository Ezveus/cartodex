// Flash messages for controllers that talk to the API in the background. A
// server-rendered flash rides on a page load; these controllers never reload
// the page, so they build the same markup here and let the flash controller
// dismiss it after five seconds.

const CONTAINER_ID = "flash-messages"

export function flashNotice(message) {
  appendFlash(message, "flash-notice")
}

export function flashAlert(message) {
  appendFlash(message, "flash-alert")
}

// Reports a failed fetch: the API's own messages when it sent any (a 422
// explains itself better than we can), the status code otherwise. Worth the
// detour — swallowing !ok responses is what once let a 500 on every write look
// like a button that simply did nothing.
export async function flashResponseError(response, fallback) {
  const errors = await responseErrors(response)

  flashAlert(errors.length ? errors.join(", ") : `${fallback} (HTTP ${response.status})`)
}

async function responseErrors(response) {
  try {
    const body = await response.json()
    return Array.isArray(body.errors) ? body.errors : []
  } catch {
    return [] // no body, or not JSON: the status is all we can report
  }
}

function appendFlash(message, modifier) {
  const container = document.getElementById(CONTAINER_ID)
  if (!container) return

  // One flash per message at a time. Repeated failures are common — a debounced
  // search retries on every pause in typing, and a dead session fails all of
  // them — and each copy would stack for five seconds in a block-level
  // container, pushing the page down under a wall of the same sentence.
  const shown = Array.from(container.children).some((child) => child.textContent === message)
  if (shown) return

  const flash = document.createElement("div")
  flash.className = `flash ${modifier}`
  flash.dataset.controller = "flash"
  // Announced to screen readers, which otherwise never learn that the action
  // failed: nothing else on the page changes when a write is refused.
  flash.setAttribute("role", "status")
  flash.setAttribute("aria-live", "polite")
  flash.textContent = message
  container.appendChild(flash)
}
