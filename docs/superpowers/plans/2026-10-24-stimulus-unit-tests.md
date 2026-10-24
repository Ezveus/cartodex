# Plan: Stimulus unit tests (#235)

Spec: `docs/superpowers/specs/2026-10-24-stimulus-unit-tests-design.md`. One lane — every file
below depends on the toolchain the first step installs, and the whole change is under fifteen
files, so a second implementation agent would cost more than it returns.

1. **Toolchain** — `mise.toml` gains `node = "24.22.1"`; `package.json` (private, `type: module`,
   scripts `test` = `vitest run`, `test:watch` = `vitest`, exact devDependencies
   `@hotwired/stimulus 3.2.2`, `jsdom 30.1.3`, `vitest 5.0.5`); committed `package-lock.json`;
   `.gitignore` gains `/node_modules/`.
2. **`vitest.config.js`** — jsdom environment, `include: ["test/javascript/**/*.test.js"]`,
   `setupFiles: ["test/javascript/setup.js"]`, `unstubGlobals`, `restoreMocks`; aliases read from
   `config/importmap.rb`'s `pin_all_from … under:` lines by an exported `importmapAliases(source)`
   (in `test/javascript/importmap_aliases.js`), throwing on an unreadable line.
3. **`test/javascript/setup.js`** — `beforeEach`: reset `document.head`/`body`, add the CSRF meta,
   `#flash-messages`, `window.Turbo = { visit: vi.fn() }`. `afterEach`: `resetSupport()`.
4. **`test/javascript/support/`** — the contract #236 writes against:
   - `mount(html, { identifier: ControllerClass, … })` → `{ application, element, controller(identifier, element?) }`;
     records Stimulus `handleError` errors.
   - `settle()` — let pending promises and one macrotask run.
   - `stubFetch(...replies)` — reply is a `Response`, an `Error` (network failure) or
     `(request) => Response`; returns the mock. `jsonResponse(body, { status })`,
     `emptyResponse(status = 204)`, `requests()` → `[{ url, method, headers, body }]` with the body
     parsed.
   - `captureEvents(target, type)` → live array of the events.
   - `flashMessages()` → `[{ text, kind }]` from `#flash-messages`.
   - `resetSupport()` — stop apps, drop listeners, throw the first controller error, then fail on
     unexpected or unconsumed fetch replies.
5. **Tests** — `helpers/api.test.js` (headers + CSRF + JSON body; network error → flash + null;
   handOver → `HandedOver`; `!ok` with `errors` → joined flash; `!ok` without → status flash; 204 →
   `true`; 200 → parsed body), `helpers/flash.test.js` (notice/alert markup, de-duplication, no
   container → no throw), `controllers/collection_quantity_controller.test.js` (connect renders;
   increment POSTs and dispatches `collection-quantity:changed` with `added`; failure leaves the
   state; decrement at 1 deletes; remove with/without add button), `support.test.js` (the harness
   fails what it must: a controller error, an unexpected request, an unconsumed reply),
   `importmap_aliases.test.js` (parses the real file, throws on an unreadable line).
6. **Version guard** — `test/javascript_toolchain_test.rb`: banner of the gem's `stimulus.js` ==
   `package.json` pin == lock version; pin is exact; every `setup-node` step in `ci.yml` reads
   `node-version-file: mise.toml`; `mise.toml` declares a three-part Node.
7. **CI** — `test_js` job, added to `deploy.needs`. `dependabot.yml`: npm ecosystem, ignore
   `@hotwired/stimulus`.
8. **Docs** — CLAUDE.md: command, aliases, the harness, six checks; `ruby_version_test.rb` and
   CLAUDE.md's "all six jobs" wording (one job now installs no Ruby); `docs/architecture/deck-odds.md`'s
   "no JS test infrastructure" lines.

Test invocations: `mise exec -- npm test`; `bin/rails test test/javascript_toolchain_test.rb`;
full `bin/rails test`.
