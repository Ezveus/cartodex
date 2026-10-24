import { describe, expect, test } from "vitest"
import DisclosureController from "controllers/disclosure_controller"
import { mount } from "../support"

const fragment = `
  <div data-controller="disclosure">
    <button class="deck-printings-toggle" aria-expanded="false" aria-controls="deck-printings-card-7"
            data-action="disclosure#toggle">Printings</button>
    <ul id="deck-printings-card-7" hidden><li>PAL 172</li></ul>
    <button class="deck-printings-others-toggle" aria-expanded="false" aria-controls="deck-printings-others-card-7"
            data-action="disclosure#toggle">Other printings (2)</button>
    <ul id="deck-printings-others-card-7" hidden><li>SVI 1</li></ul>
  </div>`

describe("disclosure_controller", () => {
  test("opens the element its button controls, and closes it on the next click", async () => {
    const { element } = await mount(fragment, { disclosure: DisclosureController })
    const toggle = element.querySelector(".deck-printings-toggle")
    const list = element.querySelector("#deck-printings-card-7")

    toggle.click()
    expect(toggle.getAttribute("aria-expanded")).toBe("true")
    expect(list.hidden).toBe(false)

    toggle.click()
    expect(toggle.getAttribute("aria-expanded")).toBe("false")
    expect(list.hidden).toBe(true)
  })

  test("leaves the other disclosures alone", async () => {
    const { element } = await mount(fragment, { disclosure: DisclosureController })

    element.querySelector(".deck-printings-others-toggle").click()

    expect(element.querySelector(".deck-printings-toggle").getAttribute("aria-expanded")).toBe("false")
    expect(element.querySelector("#deck-printings-card-7").hidden).toBe(true)
    expect(element.querySelector("#deck-printings-others-card-7").hidden).toBe(false)
  })
})
