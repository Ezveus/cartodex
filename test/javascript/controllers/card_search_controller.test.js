import { describe, expect, test, vi } from "vitest"
import CardSearchController from "controllers/card_search_controller"
import { jsonResponse, mount, requests, settle, stubFetch } from "../support"

// The worked example of a debounced controller (test/javascript/README.md, "Debounces and other
// timers").
const fragment = `
  <div data-controller="card-search" data-card-search-deck-key-value="k">
    <input data-card-search-target="input" data-action="input->card-search#search">
    <div data-card-search-target="results"></div>
  </div>`

function type(input, value) {
  input.value = value
  input.dispatchEvent(new Event("input"))
}

describe("card_search_controller", () => {
  test("searches once the typing has paused for 300 ms, for the last thing typed", async () => {
    vi.useFakeTimers()
    stubFetch(jsonResponse([]))
    const { element } = await mount(fragment, { "card-search": CardSearchController })
    const input = element.querySelector("input")

    type(input, "pi")
    await vi.advanceTimersByTimeAsync(200)
    type(input, "pika")
    await vi.advanceTimersByTimeAsync(299)
    expect(requests()).toEqual([])

    await vi.advanceTimersByTimeAsync(1)
    await settle()

    expect(requests().map((request) => request.url)).toEqual([ "/api/cards?q=pika" ])
    expect(element.querySelector("[data-card-search-target=results]").textContent).toBe("No cards found")
  })

  test("does not search for fewer than two characters", async () => {
    vi.useFakeTimers()
    const { element } = await mount(fragment, { "card-search": CardSearchController })

    type(element.querySelector("input"), "p")
    await vi.advanceTimersByTimeAsync(1000)

    expect(requests()).toEqual([])
  })
})
