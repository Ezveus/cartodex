import { vi } from "vitest"
import { state } from "./state.js"

// Replaces window.fetch for this test with a mock that answers each request with the next reply,
// in order. A reply is
//
// - a Response — jsonResponse(…) and emptyResponse(…) build the usual ones;
// - an Error, which the request rejects with: networkError() is what a browser throws offline;
// - a function of the request ({ url, method, headers, credentials, body }) returning either of the above,
//   for a reply that depends on what was sent.
//
//   stubFetch(jsonResponse({ quantity: 2 }), jsonResponse({ errors: ["Nope"] }, { status: 422 }))
//
// Strict both ways: a request past the last reply, and a reply still queued when the test ends,
// fail the test (see resetSupport). Every test starts with `stubFetch()` already called, no reply
// queued, so a request from a test that never stubs fails too. Returns the vi.fn, for assertions
// on the raw calls.
export function stubFetch(...replies) {
  const fetchState = { queue: [ ...replies ], requests: [], unexpected: [] }
  state.fetch = fetchState

  const mock = vi.fn(async (url, init = {}) => {
    const request = {
      url: String(url),
      method: init.method ?? "GET",
      headers: { ...init.headers },
      credentials: init.credentials,
      body: parseBody(init.body)
    }
    fetchState.requests.push(request)

    if (fetchState.queue.length === 0) {
      fetchState.unexpected.push(request)
      throw new TypeError(`No reply queued for ${request.method} ${request.url}`)
    }

    const queued = fetchState.queue.shift()
    const reply = typeof queued === "function" ? await queued(request) : queued
    if (reply instanceof Error) throw reply
    return reply
  })

  vi.stubGlobal("fetch", mock)
  return mock
}

// Every request the current stub received, in order, as { url, method, headers, credentials,
// body }, a JSON body already parsed and any other body left as sent.
export function requests() {
  return state.fetch?.requests ?? []
}

export function jsonResponse(body, { status = 200 } = {}) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } })
}

export function emptyResponse(status = 204) {
  return new Response(null, { status })
}

export function networkError() {
  return new TypeError("Failed to fetch")
}

function parseBody(body) {
  if (typeof body !== "string") return body

  try {
    return JSON.parse(body)
  } catch {
    return body
  }
}
