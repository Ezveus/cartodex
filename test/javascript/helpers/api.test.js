import { describe, expect, test } from "vitest"
import { HandedOver, requestJson } from "helpers/api"
import { CSRF_TOKEN, emptyResponse, flashMessages, jsonResponse, networkError, requests, stubFetch } from "../support"

describe("requestJson", () => {
  test("sends the body as JSON with the page's CSRF token, and returns the parsed answer", async () => {
    stubFetch(jsonResponse({ quantity: 3 }))

    const data = await requestJson("/api/collections", { method: "POST", body: { card_id: 7 }, failure: "Couldn't add" })

    expect(data).toEqual({ quantity: 3 })
    expect(requests()).toEqual([ {
      url: "/api/collections",
      method: "POST",
      headers: { "Content-Type": "application/json", "X-CSRF-Token": CSRF_TOKEN },
      credentials: "same-origin",
      body: { card_id: 7 }
    } ])
    expect(flashMessages()).toEqual([])
  })

  test("sends no body and a GET when given neither", async () => {
    stubFetch(jsonResponse([]))

    await requestJson("/api/cards", { failure: "Couldn't search" })

    expect(requests()[0]).toMatchObject({ method: "GET", body: undefined })
  })

  test("answers a body-less 204 with true, so a caller's `if (!data) return` lets it through", async () => {
    stubFetch(emptyResponse(204))

    expect(await requestJson("/api/collections/7", { method: "DELETE", failure: "Couldn't remove" })).toBe(true)
  })

  test("reports a request that never reached the server, and returns null", async () => {
    stubFetch(networkError())

    expect(await requestJson("/api/collections", { method: "POST", failure: "Couldn't add" })).toBeNull()
    expect(flashMessages()).toEqual([ { text: "Couldn't add — the request didn't reach the server", kind: "alert" } ])
  })

  test("flashes the server's own errors on a refusal, and returns null", async () => {
    stubFetch(jsonResponse({ errors: [ "Quantity is too large", "Card is missing" ] }, { status: 422 }))

    expect(await requestJson("/api/collections", { method: "POST", failure: "Couldn't add" })).toBeNull()
    expect(flashMessages()).toEqual([ { text: "Quantity is too large, Card is missing", kind: "alert" } ])
  })

  test("falls back to the failure and the status when the refusal explains nothing", async () => {
    stubFetch(new Response("<h1>Internal Server Error</h1>", { status: 500 }))

    expect(await requestJson("/api/collections", { method: "POST", failure: "Couldn't add" })).toBeNull()
    expect(flashMessages()).toEqual([ { text: "Couldn't add (HTTP 500)", kind: "alert" } ])
  })

  test("hands a listed refusal back to the caller, with its body, and flashes nothing", async () => {
    stubFetch(jsonResponse({ question: "Merge?" }, { status: 409 }))

    const data = await requestJson("/api/decks/k/cards/1/printing", { method: "PATCH", failure: "Couldn't swap", handOver: [ 409 ] })

    expect(data).toBeInstanceOf(HandedOver)
    expect(data).toMatchObject({ status: 409, body: { question: "Merge?" } })
    expect(flashMessages()).toEqual([])
  })

  test("hands over a listed refusal with no JSON body as an empty object", async () => {
    stubFetch(emptyResponse(409))

    const data = await requestJson("/x", { method: "PATCH", failure: "Couldn't", handOver: [ 409 ] })

    expect(data).toBeInstanceOf(HandedOver)
    expect(data.status).toBe(409)
    expect(data.body).toEqual({})
  })

  test("returns a listed status as the answer it is when it is a success", async () => {
    stubFetch(jsonResponse({ quantity: 1 }, { status: 201 }))

    expect(await requestJson("/x", { method: "POST", failure: "Couldn't", handOver: [ 201 ] })).toEqual({ quantity: 1 })
  })

  test("flashes a refusal it was not asked to hand over", async () => {
    stubFetch(jsonResponse({ errors: [ "Gone" ] }, { status: 404 }))

    expect(await requestJson("/x", { method: "PATCH", failure: "Couldn't", handOver: [ 409 ] })).toBeNull()
    expect(flashMessages()).toEqual([ { text: "Gone", kind: "alert" } ])
  })
})
