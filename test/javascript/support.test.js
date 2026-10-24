import { Controller } from "@hotwired/stimulus"
import { describe, expect, test } from "vitest"
import { state, resetSupport } from "./support/state.js"
import { captureEvents, jsonResponse, mount, stubFetch } from "./support"

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

    expectResetToThrow(/boom in connect/)
  })

  test("fails a test whose controller threw in an action", async () => {
    const { element } = await mount(`<button data-controller="clicking" data-action="clicking#fail"></button>`, { clicking: Clicking })

    element.click()

    expectResetToThrow(/boom in action/)
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
})
