import { describe, expect, test, vi } from "vitest"
import CardSearchController from "controllers/card_search_controller"
import { captureEvents, jsonResponse, mount, requests, settle, stubFetch } from "../support"

// The worked example of a debounced controller (test/javascript/README.md, "Debounces and other
// timers").
const fragment = `
  <div data-controller="card-search" data-card-search-url-value="/api/decks/k/cards?group=set">
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

  // The POST is deck_rows_controller.js's to send: it is the one that knows whether a write is
  // already in flight, and an add answered after an older stepper answer would be overwritten.
  test("hands the add to the deck page as a request, clears the search and sends nothing itself", async () => {
    vi.useFakeTimers()
    stubFetch(jsonResponse([ { id: 99, name: "Pikachu", set_name: "SVI", set_number: "1", card_type: "Pokémon" } ]))
    const { element } = await mount(fragment, { "card-search": CardSearchController })
    const adds = captureEvents(document, "card-search:add")
    const input = element.querySelector("input")

    type(input, "pika")
    await vi.advanceTimersByTimeAsync(300)
    await settle()
    element.querySelector(".card-search-add-btn").click()
    await settle()

    expect(requests().map((request) => request.url)).toEqual([ "/api/cards?q=pika" ])
    expect(adds.map((event) => event.detail)).toEqual([ {
      url: "/api/decks/k/cards?group=set",
      body: { deck_card: { card_id: "99", quantity: 1 } },
      failure: "Couldn't add the card to this deck"
    } ])
    expect(input.value).toBe("")
    expect(element.querySelector("[data-card-search-target=results]").innerHTML).toBe("")
    expect(window.Turbo.visit).not.toHaveBeenCalled()
  })
})
