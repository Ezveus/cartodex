import { Controller } from "@hotwired/stimulus"
import { describe, expect, test, vi } from "vitest"
import { state, resetSupport } from "./support/state.js"
import { captureEvents, flashMessages, jsonResponse, mount, requests, stubFetch } from "./support"
import { requestJson } from "helpers/api"

// The harness has to fail the tests it exists to fail. Each case below provokes one failure and
// calls resetSupport() itself — what the shared afterEach would do — to watch it throw.

class Failing extends Controller {
  connect() { throw new Error("boom in connect") }
}

class Clicking extends Controller {
  fail() { throw new Error("boom in action") }
}

function expectResetToThrow(pattern) {
  expect(() => resetSupport()).toThrow(pattern)
}

describe("the test harness", () => {
  test("fails a test whose controller threw in connect(), which Stimulus would only log", async () => {
    await mount(`<div data-controller="failing"></div>`, { failing: Failing })

    expectResetToThrow(/^Error connecting controller: boom in connect$/)
  })

  test("fails a test whose controller threw in an action", async () => {
    const { element } = await mount(`<button data-controller="clicking" data-action="clicking#fail"></button>`, { clicking: Clicking })

    element.click()

    expectResetToThrow(/^Error invoking action "click->clicking#fail": boom in action$/)
  })

  test("fails a test that made a request it queued no reply for", async () => {
    stubFetch()

    await expect(fetch("/api/surprise", { method: "POST" })).rejects.toThrow()
    expectResetToThrow(/no reply queued: POST \/api\/surprise/)
  })

  test("fails a test that queued a reply nobody requested", () => {
    stubFetch(jsonResponse({}), jsonResponse({}))

    expectResetToThrow(/2 queued fetch replies were never requested/)
  })

  test("stops each application, so a controller does not outlive its test", async () => {
    const disconnected = []
    class Tracked extends Controller { disconnect() { disconnected.push(this.element) } }
    const { element } = await mount(`<div data-controller="tracked"></div>`, { tracked: Tracked })

    resetSupport()

    expect(disconnected).toEqual([ element ])
    expect(state.applications).toEqual([])
  })

  test("stops each application from watching the page", async () => {
    const connected = []
    class Watched extends Controller { connect() { connected.push(this.element) } }
    const { element } = await mount(`<div></div>`, { watched: Watched })

    resetSupport()
    element.insertAdjacentHTML("beforeend", `<div data-controller="watched"></div>`)
    await Promise.resolve()

    expect(connected).toEqual([])
  })

  test("records a JSON body parsed and any other body as sent", async () => {
    stubFetch(jsonResponse({}), jsonResponse({}))

    await fetch("/a", { method: "POST", body: JSON.stringify({ n: 1 }) })
    await fetch("/b", { method: "POST", body: "plain text" })

    expect(requests().map((request) => request.body)).toEqual([ { n: 1 }, "plain text" ])
  })

  test("answers with a reply built from the request", async () => {
    stubFetch((request) => jsonResponse({ echo: request.url }))

    expect(await (await fetch("/api/echo")).json()).toEqual({ echo: "/api/echo" })
  })

  test("reports a flash of no known kind as kind null", () => {
    document.getElementById("flash-messages").innerHTML = `<div class="flash flash-success">Odd</div>`

    expect(flashMessages()).toEqual([ { text: "Odd", kind: null } ])
  })

  test("stops listening once the test is over", () => {
    const events = captureEvents(document, "ping")

    resetSupport()
    document.dispatchEvent(new Event("ping"))

    expect(events).toEqual([])
  })

  test("starts every test on the page skeleton controllers read", () => {
    expect(document.querySelector('meta[name="csrf-token"]').content).toBe("test-csrf-token")
    expect(document.getElementById("flash-messages").children).toHaveLength(0)
    expect(window.Turbo.visit).not.toHaveBeenCalled()
  })

  test("fails a test whose controller made a request without the test ever stubbing fetch", async () => {
    await requestJson("/api/x", { failure: "f" })

    expectResetToThrow(/no reply queued: GET \/api\/x/)
  })

  test("gives each mount its own application, so neither connects the other's elements", async () => {
    const connected = []
    class Counted extends Controller {
      connect() { connected.push(this.element) }
      ping() { connected.push("ping") }
    }
    const fragment = `<button data-controller="counted" data-action="counted#ping"></button>`

    const first = await mount(fragment, { counted: Counted })
    const second = await mount(fragment, { counted: Counted })
    first.element.click()

    expect(connected).toEqual([ first.element, second.element, "ping" ])
    expect(first.controller("counted")).not.toBe(second.controller("counted"))
  })

  test("never starts the production application", async () => {
    await mount(`<div data-controller="tracked"></div>`, { tracked: class extends Controller {} })

    expect(window.Stimulus).toBeUndefined()
  })
})

// Two tests that must run in this order: the first leaves a stubbed global and a spy behind, the
// second checks the configuration took both away (`unstubGlobals`, `restoreMocks`). innerWidth
// rather than fetch, because setup.js stubs fetch afresh before every test anyway.
describe("between tests", () => {
  const originalWidth = window.innerWidth

  test("a test may stub a global and spy on the console", () => {
    vi.stubGlobal("innerWidth", originalWidth - 400)
    vi.spyOn(console, "error")

    expect(window.innerWidth).toBe(originalWidth - 400)
    expect(vi.isMockFunction(console.error)).toBe(true)
  })

  test("the next one starts with neither", () => {
    expect(window.innerWidth).toBe(originalWidth)
    expect(vi.isMockFunction(console.error)).toBe(false)
  })
})
