import { Application } from "@hotwired/stimulus"
import { vi } from "vitest"
import { state } from "./state.js"

// Puts `html` in the page and starts a Stimulus application on it with only the controllers
// given, keyed by identifier:
//
//   const { element, controller } = await mount(
//     `<div data-controller="collection-quantity" data-collection-quantity-card-id-value="7"></div>`,
//     { "collection-quantity": CollectionQuantityController }
//   )
//
// Every controller in the fragment has connected when the promise resolves, and each identifier
// given must have connected at least once, or mount throws. The application is
// a private one, never controllers/application.js (the production singleton, which starts on
// import), and it is stopped after the test, every controller disconnecting. Each call gets its
// own container, so a test may mount twice without one application connecting the other's
// elements.
export async function mount(html, controllers = {}) {
  const container = document.createElement("div")
  container.innerHTML = html
  document.body.appendChild(container)

  const application = new Application(container)
  application.handleError = (error, message, detail) => {
    state.controllerErrors.push({ error, message, detail })
  }
  for (const [identifier, controllerClass] of Object.entries(controllers)) {
    application.register(identifier, controllerClass)
  }
  state.applications.push({ application, identifiers: Object.keys(controllers) })
  await application.start()

  // A misspelt data-controller connects nothing, and every assertion that something did not
  // happen then passes on a dead fixture.
  for (const identifier of Object.keys(controllers)) {
    if (!application.controllers.some((controller) => controller.identifier === identifier)) {
      throw new Error(`mount: no element in the fragment connected "${identifier}" — check its data-controller`)
    }
  }

  return {
    application,
    element: container.firstElementChild,
    controller(identifier, element = container.querySelector(`[data-controller~="${identifier}"]`)) {
      return application.getControllerForElementAndIdentifier(element, identifier)
    }
  }
}

// Lets whatever a click started run to the end. Stimulus calls an async action and drops the
// promise, so a test that clicks has nothing to await; this waits out the microtasks a
// requestJson round trip queues (fetch, then response.json()) and a few macrotasks besides.
// A test holding the controller can await the action itself instead:
// `await controller("collection-quantity").increment()`.
//
// Under vi.useFakeTimers() it flushes the same way without moving the clock, so a debounce has
// to be passed explicitly: `await vi.advanceTimersByTimeAsync(300)`, then `await settle()`.
export async function settle() {
  for (let turn = 0; turn < 5; turn++) {
    if (vi.isFakeTimers()) await vi.advanceTimersByTimeAsync(0)
    else await new Promise((resolve) => setTimeout(resolve, 0))
  }
}
