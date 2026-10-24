import { describe, expect, test } from "vitest"
import CollectionQuantityController from "controllers/collection_quantity_controller"
import { captureEvents, emptyResponse, flashMessages, jsonResponse, mount, requests, settle, stubFetch } from "../support"

const controllers = { "collection-quantity": CollectionQuantityController }

// The card page's counter (Cards::ShowView#collection_control): an add button shown at zero, a
// counter shown otherwise.
function cardPageCounter(quantity) {
  return `
    <div data-controller="collection-quantity"
         data-collection-quantity-card-id-value="7"
         data-collection-quantity-quantity-value="${quantity}"
         data-collection-quantity-flash-on-change-value="true">
      <button data-collection-quantity-target="addButton" data-action="collection-quantity#increment">Add to collection</button>
      <div data-collection-quantity-target="counter">
        <button data-action="collection-quantity#decrement" aria-label="Decrement">−</button>
        <span data-collection-quantity-target="qty">${quantity}</span>
        <button data-action="collection-quantity#increment" aria-label="Increment">+</button>
        <button data-action="collection-quantity#remove">Remove</button>
      </div>
    </div>`
}

function click(element, label) {
  const button = Array.from(element.querySelectorAll("button")).find((candidate) =>
    candidate.textContent === label || candidate.getAttribute("aria-label") === label)
  button.click()
}

describe("collection_quantity_controller", () => {
  test("shows the add button at zero and the counter otherwise, as soon as it connects", async () => {
    const empty = await mount(cardPageCounter(0), controllers)
    const held = await mount(cardPageCounter(2), controllers)

    expect(empty.element.querySelector("[data-collection-quantity-target=addButton]").style.display).toBe("")
    expect(empty.element.querySelector("[data-collection-quantity-target=counter]").style.display).toBe("none")
    expect(held.element.querySelector("[data-collection-quantity-target=addButton]").style.display).toBe("none")
    expect(held.element.querySelector("[data-collection-quantity-target=counter]").style.display).toBe("")
  })

  test("adds a first copy through the API, shows the counter and announces the change", async () => {
    stubFetch(jsonResponse({ quantity: 1 }, { status: 201 }))
    const { element } = await mount(cardPageCounter(0), controllers)
    const changes = captureEvents(document, "collection-quantity:changed")

    click(element, "Add to collection")
    await settle()

    expect(requests()).toMatchObject([ {
      url: "/api/collections",
      method: "POST",
      body: { collection: { card_id: 7, quantity: 1 } }
    } ])
    expect(element.querySelector("[data-collection-quantity-target=qty]").textContent).toBe("1")
    expect(element.querySelector("[data-collection-quantity-target=counter]").style.display).toBe("")
    expect(changes.map((event) => event.detail)).toEqual([ { delta: 1, removed: false, added: true } ])
    expect(flashMessages()).toEqual([ { text: "Added to collection (1 copy)", kind: "notice" } ])
  })

  // `added` says the card was not in the collection before this click — what collection_list
  // reads to add a row — and not that the collection now holds exactly one copy.
  test("announces an addition from zero even when the server answers several copies", async () => {
    stubFetch(jsonResponse({ quantity: 3 }))
    const { controller } = await mount(cardPageCounter(0), controllers)
    const changes = captureEvents(document, "collection-quantity:changed")

    await controller("collection-quantity").increment()

    expect(changes.map((event) => event.detail)).toEqual([ { delta: 3, removed: false, added: true } ])
  })

  test("takes the quantity the server answers, not one more than it showed", async () => {
    stubFetch(jsonResponse({ quantity: 5 }))
    const { element, controller } = await mount(cardPageCounter(2), controllers)
    const changes = captureEvents(document, "collection-quantity:changed")

    await controller("collection-quantity").increment()

    expect(element.querySelector("[data-collection-quantity-target=qty]").textContent).toBe("5")
    expect(changes[0].detail).toEqual({ delta: 3, removed: false, added: false })
    expect(flashMessages()).toEqual([ { text: "Added to collection (5 copies)", kind: "notice" } ])
  })

  test("changes nothing and announces nothing when an increment is refused", async () => {
    stubFetch(jsonResponse({ errors: [ "Card must exist" ] }, { status: 422 }))
    const { element } = await mount(cardPageCounter(2), controllers)
    const changes = captureEvents(document, "collection-quantity:changed")

    click(element, "Increment")
    await settle()

    expect(element.querySelector("[data-collection-quantity-target=qty]").textContent).toBe("2")
    expect(changes).toEqual([])
    expect(flashMessages()).toEqual([ { text: "Card must exist", kind: "alert" } ])
  })

  test("keeps the quantity when a decrement is refused", async () => {
    stubFetch(jsonResponse({ errors: [ "Quantity is invalid" ] }, { status: 422 }))
    const { element } = await mount(cardPageCounter(3), controllers)
    const changes = captureEvents(document, "collection-quantity:changed")

    click(element, "Decrement")
    await settle()

    expect(element.querySelector("[data-collection-quantity-target=qty]").textContent).toBe("3")
    expect(changes).toEqual([])
    expect(flashMessages()).toEqual([ { text: "Quantity is invalid", kind: "alert" } ])
  })

  test("keeps the row when a removal is refused", async () => {
    stubFetch(new Response(null, { status: 500 }))
    const { element } = await mount(`
      <ul>
        <li data-controller="collection-quantity" data-collection-quantity-card-id-value="9" data-collection-quantity-quantity-value="4">
          <button data-action="collection-quantity#remove">Remove</button>
        </li>
      </ul>`, controllers)
    const changes = captureEvents(element, "collection-quantity:changed")

    click(element, "Remove")
    await settle()

    expect(element.querySelector("li")).not.toBeNull()
    expect(changes).toEqual([])
    expect(flashMessages()).toEqual([ { text: "Couldn't remove this card from your collection (HTTP 500)", kind: "alert" } ])
  })

  test("decrements through a PATCH while more than one copy is held", async () => {
    stubFetch(jsonResponse({ quantity: 2 }))
    const { element } = await mount(cardPageCounter(3), controllers)
    const changes = captureEvents(document, "collection-quantity:changed")

    click(element, "Decrement")
    await settle()

    expect(requests()).toMatchObject([ { url: "/api/collections/7", method: "PATCH", body: { collection: { quantity: 2 } } } ])
    expect(element.querySelector("[data-collection-quantity-target=qty]").textContent).toBe("2")
    expect(changes.map((event) => event.detail)).toEqual([ { delta: -1, removed: false, added: false } ])
  })

  test("deletes the last copy instead of setting it to zero, and shows the add button again", async () => {
    stubFetch(emptyResponse(204))
    const { element } = await mount(cardPageCounter(1), controllers)
    const changes = captureEvents(document, "collection-quantity:changed")

    click(element, "Decrement")
    await settle()

    expect(requests()).toMatchObject([ { url: "/api/collections/7", method: "DELETE", body: undefined } ])
    expect(element.isConnected).toBe(true)
    expect(element.querySelector("[data-collection-quantity-target=addButton]").style.display).toBe("")
    expect(changes.map((event) => event.detail)).toEqual([ { delta: -1, removed: true, added: false } ])
    expect(flashMessages()).toEqual([ { text: "Removed from collection", kind: "notice" } ])
  })

  // The collection page's row has no add button: removing the card removes the row, and the
  // event is dispatched from the row's parent, since the row is no longer in the page to bubble
  // from.
  test("removes a collection row that has no add button, announcing it from the parent", async () => {
    stubFetch(emptyResponse(204))
    const { element } = await mount(`
      <ul class="collection-list">
        <li data-controller="collection-quantity"
            data-collection-quantity-card-id-value="9"
            data-collection-quantity-quantity-value="4">
          <span data-collection-quantity-target="qty">4</span>
          <button data-action="collection-quantity#remove">Remove</button>
        </li>
      </ul>`, controllers)
    const changes = captureEvents(element, "collection-quantity:changed")

    click(element, "Remove")
    await settle()

    expect(element.querySelector("li")).toBeNull()
    expect(changes.map((event) => [ event.target, event.detail ])).toEqual([ [ element, { delta: -4, removed: true, added: false } ] ])
    expect(flashMessages()).toEqual([])
  })
})
