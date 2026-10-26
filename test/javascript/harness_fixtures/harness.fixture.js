import { Controller } from "@hotwired/stimulus"
import { test } from "vitest"
import { requestJson } from "helpers/api"
import { jsonResponse, mount, stubFetch } from "../support"

// Run by harness.test.js only. Every test but the first must fail, and fail only because of what
// the shared afterEach checks: none of them asserts anything.

class FailingConnect extends Controller {
  connect() { throw new Error("fixture: boom in connect") }
}

class FailingAction extends Controller {
  fail() { throw new Error("fixture: boom in action") }
}

test("control: a clean test", async () => {
  stubFetch(jsonResponse({ ok: true }))
  await requestJson("/api/ok", { failure: "f" })
})

test("a controller throws in connect", async () => {
  await mount(`<div data-controller="failing-connect"></div>`, { "failing-connect": FailingConnect })
})

test("a controller throws in an action", async () => {
  const { element } = await mount(`<button data-controller="failing-action" data-action="failing-action#fail"></button>`, { "failing-action": FailingAction })
  element.click()
})

test("a request is made without ever calling stubFetch", async () => {
  await requestJson("/api/unstubbed", { failure: "f" })
})

test("a request outruns the queued replies", async () => {
  stubFetch(jsonResponse({}))
  await requestJson("/api/first", { failure: "f" })
  await requestJson("/api/second", { method: "POST", failure: "f" })
})

test("a queued reply is never requested", () => {
  stubFetch(jsonResponse({}))
})
