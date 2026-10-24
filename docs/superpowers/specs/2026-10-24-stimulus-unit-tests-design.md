# Stimulus controllers under unit test (Vitest + jsdom)

## Request

Issue #235. The repository has no JavaScript test infrastructure: 38 Stimulus controllers and two
helpers are exercised only through system tests, and `/decks/:id/odds` kept all of its arithmetic
server-side for that reason alone. The deck builder rework (#236) moves real behaviour into
Stimulus controllers and is built on this setup, so the setup has to make a controller test cheap
to write: mount a controller on a DOM fragment, answer its requests, read what it dispatched.

## Measurements

- importmap serves Stimulus from `stimulus-rails` 1.3.4 (`Gemfile.lock`), pinned as
  `stimulus.min.js`. That file carries **no version banner**: `grep -c "Stimulus 3"` finds none.
  The banner lives in the sibling `stimulus.js` of the same gem (`Stimulus 3.2.2`, line 6, after
  three Sprockets `//= link` directives), so the guard reads that file.
- The npm `@hotwired/stimulus@3.2.2` `dist/stimulus.js` is code-identical to the gem's `stimulus.js`
  once its first four lines (three Sprockets directives and a blank line) are stripped — `diff` reports a single line, the banner, which
  upstream left at `Stimulus 3.2.1` in the 3.2.2 npm release. The installed package's own banner is
  therefore not a usable version source; `package-lock.json` is.
- Node: 24.22.1 is the newest release of the active LTS line (Krypton, 2026-10-20); 26.x is still
  "Current" (`lts=false` in `nodejs.org/dist/index.json`) on the day this was written.
- `actions/setup-node@v7` reads `mise.toml` through `node-version-file` (it parses
  `[tools] node = "…"`, `src/util.ts`), so CI reads the same declaration a developer's `mise`
  does — one copy, nothing to keep in agreement.
- vitest 5.0.5, jsdom 30.1.3: `npm install` → 0 vulnerabilities. vitest 5's engines admit
  `^22.12 || ^24 || >=26`.
- Baseline before this change: `bin/rails test` → 2540 runs, 0 failures.

## Decisions

- **`package.json` is dev/test only.** Its three packages are `devDependencies`, exactly pinned
  (no `^`), and nothing in the app, the Dockerfile or Propshaft reads it. importmap stays the only
  runtime path. `.dockerignore` already excluded `/node_modules/`.
- **Controllers are imported unchanged**: `controllers/*` and `helpers/*` resolve to
  `app/javascript/…` through Vitest aliases, `@hotwired/stimulus` through `node_modules`.
- **The aliases are read from `config/importmap.rb`, not restated.** `vitest.config.js` reads every
  `pin_all_from "<dir>", under: "<name>"` line and aliases `<name>` to `<dir>`. A directory pinned
  tomorrow is importable under test the same day, and the two lists cannot drift. A `pin_all_from`
  line the reader cannot parse (no `under:`, a non-literal argument) **fails the config load**
  naming the line, rather than leaving a module unresolvable in a way that reads like a typo in a
  test.
- **The Stimulus version guard is a Minitest test** (`test/javascript_toolchain_test.rb`), beside
  `test/ruby_version_test.rb` and for the same reason: it answers to configuration files. It reads
  the installed gem's path from Bundler (`Gem.loaded_specs`), so it follows what `Gemfile.lock`
  actually resolved rather than a number written in a test, and asserts that the banner version
  equals both the `package.json` pin and the version `package-lock.json` installs. Running under
  Ruby means the `test` job enforces it without Node, and a bundler dependabot bump of the gem
  fails CI on the very pull request that moves production.
- **The same file asserts that every CI job installing Node does so from `mise.toml`** and that
  `mise.toml` declares a three-part Node version — the Ruby guard's shape.
- **Tests live in `test/javascript/`, named `*.test.js`.** `bin/rails test` only collects
  `*_test.rb`, and Propshaft and importmap only read `app/`, so the files reach neither.
- **Each test starts from the page skeleton controllers assume**: a fresh
  `<meta name="csrf-token">` (read without a null check by `helpers/api.js`,
  `collection_controller.js`, `decks_controller.js`, `set_import_controller.js`), an empty
  `#flash-messages` (written by `helpers/flash.js`, which silently does nothing without it), and
  `window.Turbo = { visit: vi.fn() }` (read by `card_search_controller.js` and
  `printing_picker_controller.js`). `window.Stimulus` is not set; nothing outside
  `controllers/application.js` reads it. After each test, storage, the URL, fake timers and a
  stubbed clipboard are reset — jsdom keeps one window per file.
- **Stand-ins for what jsdom lacks**: `<dialog>` `showModal`/`show`/`close` (five controllers) and
  `Element#scrollIntoView` (two) are installed once as stateless functions; `navigator.clipboard`
  stays undefined, as on a non-secure origin, until a test calls `stubClipboard()`.
- **`mount` starts a private Stimulus `Application`** registering only the controllers it is given,
  never `controllers/application.js` (which starts on import and is the production singleton).
- **`mount` refuses a fragment in which a given identifier never connected** — a misspelt
  `data-controller` would otherwise make every negative assertion pass.
- **A controller's error fails the test.** Stimulus' `Application#handleError` logs to
  `console.error` and swallows, so a controller throwing in `connect()` or in a synchronous action
  would otherwise leave a green test over a dead controller. `mount` records those errors and the
  shared `afterEach` throws the first one.
- **`stubFetch` is strict in both directions, and on by default.** A request with no reply left,
  and a reply nobody requested, both fail the test in `afterEach`; every test starts with
  `stubFetch()` called and nothing queued, so a test that never stubs is held to it too. The first matters because `requestJson` catches a
  rejected `fetch` and turns it into a flash, so an unexpected request would otherwise be invisible;
  the second because a test that queued a reply expected a request that never happened.
- **Requests are answered with real `Response` objects** (Node 24's global), so `requestJson`'s
  `response.ok`, `status` and `json()` run unmodified.
- **CI job `test_js`**: checkout, `actions/setup-node@v7` with `node-version-file: mise.toml` and
  the npm cache, `npm ci`, `npm test`. The `deploy` job `needs:` it.
- **dependabot gains the npm ecosystem, and ignores `@hotwired/stimulus`.** Its version follows the
  gem: a bump starts as a bundler pull request, which the guard turns red until `package.json` is
  edited in that same pull request.

- **The harness is proved from outside.** `harness.test.js` runs Vitest in a child process over
  fixtures that fail only through the shared `afterEach`; a test calling `resetSupport()` itself
  cannot tell whether `setup.js` calls it.

## Owner may reverse

- **Aliases derived from `config/importmap.rb`** — alternative: hand-write them in
  `vitest.config.js` plus a guard test comparing them. Derived: a new `pin_all_from` is importable
  under test with no edit. Hand-written: one more list to keep, with a test reporting drift.
- **dependabot ignores `@hotwired/stimulus` in npm** — alternative: let it open npm pull requests
  for Stimulus. Ignored: the gem's bundler PR is the only one, and the guard says what to edit.
  Not ignored: an npm PR appears whenever npm ships first, and it is red until stimulus-rails
  vendors the same version.
- **Node 24 LTS** — alternative: Node 26 (current, LTS expected at the end of October 2026). 24 is
  supported to 2028 and admitted by vitest 5; 26 would need a bump of nothing else.
- **No `npm audit` step in CI** — the packages never reach production, and dependabot covers
  advisories; adding one would fail CI on advisories against a test runner.

## Out of scope

Rewriting any controller; testing every existing controller. Covered here: `helpers/api.js`,
`helpers/flash.js`, `collection_quantity_controller.js` (a `requestJson` round trip, values,
targets, both of its dispatch paths and its flash) and `card_search_controller.js` (its debounce,
the worked fake-timer example).
