import { flashAlert, flashResponseError } from "helpers/flash"

// One way to call the JSON API from a controller, reporting every way the call
// can fail. `!response.ok` is only half of them: a network failure — offline,
// DNS, a reset connection, a server that never answers — rejects the fetch
// instead, so it never becomes a Response at all and sails past that check into
// an unhandled rejection. Both roads end in a flash here.
//
// Returns the parsed body on success, `true` for a body-less 204, and null on
// any failure, so a caller reads as:
//
//   const data = await requestJson(url, { method: "POST", body, failure: "..." })
//   if (!data) return
//
// `failure` is what the user is told when the server sent no explanation of its
// own; write it as the action that did not happen, not as the error.
//
// `handOver` lists the refusals a caller answers itself instead of flashing — a
// 409 that asks the user a question, say. Such a response comes back as a
// HandedOver rather than as null, so it cannot be mistaken for a success body
// (which is any object) nor for a failure already reported:
//
//   const data = await requestJson(url, { method: "POST", body, failure: "...", handOver: [409] })
//   if (data instanceof HandedOver) return this.ask(data.body)
//
// Empty by default, which is every caller written before it.
export class HandedOver {
  constructor(status, body) {
    this.status = status
    this.body = body
  }
}

export async function requestJson(url, { method = "GET", body, failure, handOver = [] } = {}) {
  let response

  try {
    response = await fetch(url, {
      method,
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      credentials: "same-origin",
      body: body === undefined ? undefined : JSON.stringify(body)
    })
  } catch {
    flashAlert(`${failure} — the request didn't reach the server`)
    return null
  }

  if (!response.ok && handOver.includes(response.status)) {
    return new HandedOver(response.status, await response.json().catch(() => ({})))
  }

  if (!response.ok) {
    await flashResponseError(response, failure)
    return null
  }

  // 204 carries no body, and asking for its JSON would throw. Truthy so that
  // callers can keep the single `if (!data) return` guard.
  return response.status === 204 ? true : response.json()
}
