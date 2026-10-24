# JavaScript unit tests

Vitest + jsdom over the Stimulus controllers and helpers in `app/javascript/`. Dev/test only:
`package.json` is read by nothing in the app, and importmap stays the only way JavaScript is
served.

```bash
mise install          # Node, from mise.toml (CI reads the same line)
npm ci                # once, and after package-lock.json changes
npm test              # the whole suite, once
npm run test:watch    # re-run on save
npx vitest run test/javascript/controllers/collection_quantity_controller.test.js
```

## Imports

A test imports a controller exactly the way the app does — `controllers/…`, `helpers/…`,
`@hotwired/stimulus` — so controllers run unchanged. `vitest.config.js` reads the aliases from
`config/importmap.rb`'s `pin_all_from` lines (`importmap_aliases.js`): pin a new directory there
and it resolves here with no edit. `@hotwired/stimulus` comes from `node_modules`, pinned exactly to
the version the stimulus-rails gem vendors; `test/javascript_toolchain_test.rb` fails when the two
disagree. A controller importing `@hotwired/turbo-rails` or `@hotwired/stimulus-loading` would need
one more devDependency or alias — none does today.

## The page every test starts on

`setup.js` resets the document before each test to what the layout renders and the controllers
assume: `<meta name="csrf-token" content="test-csrf-token">` (`CSRF_TOKEN`), an empty
`#flash-messages`, and `window.Turbo = { visit: vi.fn() }`. Mocks and stubbed globals are restored
after each test (`restoreMocks`, `unstubGlobals`).

## Writing a controller test

Everything below is exported by `support/index.js`.

```js
import { expect, test } from "vitest"
import CollectionQuantityController from "controllers/collection_quantity_controller"
import { captureEvents, flashMessages, jsonResponse, mount, requests, settle, stubFetch } from "../support"

test("adds a copy", async () => {
  stubFetch(jsonResponse({ quantity: 1 }, { status: 201 }))                 // 1. answer the requests
  const { element } = await mount(`
    <div data-controller="collection-quantity" data-collection-quantity-card-id-value="7">
      <button data-action="collection-quantity#increment">+</button>
    </div>`, { "collection-quantity": CollectionQuantityController })       // 2. mount on a fragment
  const changes = captureEvents(document, "collection-quantity:changed")    // 3. listen

  element.querySelector("button").click()
  await settle()                                                            // 4. let the round trip finish

  expect(requests()).toMatchObject([ { method: "POST", url: "/api/collections", body: { collection: { card_id: 7, quantity: 1 } } } ])
  expect(changes.map((event) => event.detail)).toEqual([ { delta: 1, removed: false, added: true } ])
  expect(flashMessages()).toEqual([])
})
```

- **`mount(html, { identifier: Class })`** puts the fragment in the page, starts a private Stimulus
  application with only those controllers, and resolves once they have connected. It returns
  `{ application, element, controller(identifier, element?) }` — `element` is the fragment's first
  element. The application is stopped and every controller disconnected after the test.
- **`settle()`** waits out what a click started: Stimulus drops an async action's promise, so a
  test that clicks has nothing else to await. Holding the controller, await the action instead:
  `await controller("collection-quantity").increment()`.
- **`stubFetch(...replies)`** answers requests in order. A reply is a `Response`
  (`jsonResponse(body, { status })`, `emptyResponse(204)`, or `new Response(...)` for anything
  else), an `Error` (`networkError()`, what a browser throws offline), or a function of the request
  returning either. `requests()` lists what was sent as `{ url, method, headers, body }`, the body
  parsed from JSON. Real `Response` objects mean `helpers/api.js`'s `requestJson` runs unmodified —
  prefer this to mocking `requestJson`. To replace `requestJson` itself, `vi.mock("helpers/api", …)`
  works through the same alias.
- **`captureEvents(target, type)`** returns an array that fills with every `type` event reaching
  `target`. `this.dispatch("changed")` from controller `foo` is `foo:changed` and bubbles, so
  `document` sees it.
- **`flashMessages()`** returns `[{ text, kind }]` from `#flash-messages`, `kind` being `notice` or
  `alert`.

## What fails a test besides its assertions

The shared `afterEach` fails the test, after the fact, when:

- a controller threw — in `connect()`, `disconnect()`, an action, a value or target callback.
  Stimulus only logs these, so without this a dead controller passes;
- a request arrived with no reply queued — `requestJson` would have turned it into a flash and a
  `null`, invisible to the test;
- a queued reply was never requested.

`support.test.js` holds each of those to account.
