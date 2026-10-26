import { state } from "./state.js"

// Collects every `type` event that reaches `target`, into the array returned — it fills as the
// events arrive, so read it after the action has settled:
//
//   const changes = captureEvents(document, "collection-quantity:changed")
//   …
//   expect(changes.map((event) => event.detail)).toEqual([ { delta: 1, removed: false, added: true } ])
//
// A Stimulus `this.dispatch("changed")` is named `<identifier>:changed` and bubbles by default,
// so capturing on `document` sees it from anywhere in the page. The listener is removed after the
// test.
export function captureEvents(target, type) {
  const events = []
  const listener = (event) => events.push(event)
  target.addEventListener(type, listener)
  state.listeners.push({ target, type, listener })
  return events
}
