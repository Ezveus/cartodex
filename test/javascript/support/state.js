// What a test leaves behind for the shared afterEach (test/javascript/setup.js) to check and
// clean up. Kept in one place so that the order of that check is decided once — see
// resetSupport.
export const state = {
  applications: [],
  controllerErrors: [],
  listeners: [],
  fetch: null
}

// Runs after every test. Applications are stopped first, and their controllers disconnected —
// `Application#stop` alone stops observing the page without calling disconnect(), which would
// leave whatever connect() hung on document or window listening into the next test. That comes
// before the checks because a controller's disconnect() can itself fail and has to be counted. Then the first failure found is thrown, which
// fails the test that caused it:
//
// - a controller error, because Stimulus logs those to the console and carries on, so a
//   controller that threw in connect() or in an action would otherwise sit under a green test;
// - a request no reply was queued for, because requestJson turns a rejected fetch into a flash
//   and a null, so the test would only see a controller that quietly did nothing;
// - a queued reply nobody asked for, because the test expected a request that never happened.
export function resetSupport() {
  for (const { application, identifiers } of state.applications) {
    application.unload(identifiers)
    application.stop()
  }
  for (const { target, type, listener } of state.listeners) target.removeEventListener(type, listener)

  const { controllerErrors, fetch } = state
  state.applications = []
  state.controllerErrors = []
  state.listeners = []
  state.fetch = null

  if (controllerErrors.length > 0) {
    const [{ error, message }] = controllerErrors
    error.message = `${message}: ${error.message}`
    throw error
  }

  if (fetch?.unexpected.length > 0) {
    const [request] = fetch.unexpected
    throw new Error(`fetch was called with no reply queued: ${request.method} ${request.url}`)
  }

  if (fetch?.queue.length > 0) {
    throw new Error(`${fetch.queue.length} queued fetch repl${fetch.queue.length === 1 ? "y was" : "ies were"} never requested`)
  }
}
