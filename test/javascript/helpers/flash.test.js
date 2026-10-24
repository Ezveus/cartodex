import { describe, expect, test } from "vitest"
import { flashAlert, flashNotice, flashResponseError } from "helpers/flash"
import { flashMessages, jsonResponse } from "../support"

describe("helpers/flash", () => {
  test("writes a notice and an alert as dismissable, announced flashes", () => {
    flashNotice("Saved")
    flashAlert("Refused")

    expect(flashMessages()).toEqual([ { text: "Saved", kind: "notice" }, { text: "Refused", kind: "alert" } ])
    expect(Array.from(document.querySelectorAll("#flash-messages > *"), (element) => element.className))
      .toEqual([ "flash flash-notice", "flash flash-alert" ])
    const flash = document.querySelector("#flash-messages > .flash")
    expect(flash.dataset.controller).toBe("flash")
    expect(flash.getAttribute("role")).toBe("status")
    expect(flash.getAttribute("aria-live")).toBe("polite")
  })

  test("shows one copy of a message while it is on screen", () => {
    flashAlert("Offline")
    flashAlert("Offline")
    flashAlert("Still offline")
    flashAlert("offline")

    expect(flashMessages().map((flash) => flash.text)).toEqual([ "Offline", "Still offline", "offline" ])
  })

  test("does nothing, and does not throw, on a page without #flash-messages", () => {
    document.getElementById("flash-messages").remove()

    expect(() => flashAlert("Lost")).not.toThrow()
    expect(document.body.textContent).toBe("")
  })

  test("reports a refusal's own errors, else the fallback with its status", async () => {
    await flashResponseError(jsonResponse({ errors: [ "Too many" ] }, { status: 422 }), "Couldn't add")
    await flashResponseError(jsonResponse({ errors: "not a list" }, { status: 422 }), "Couldn't save")

    expect(flashMessages().map((flash) => flash.text)).toEqual([ "Too many", "Couldn't save (HTTP 422)" ])
  })
})
