# A deck can be shared, and three surfaces stop requiring a session — Design

Issue: none — requested directly. The scope deliberately left out is recorded on #142.

## Goal

Every route in the app except `/`, `/up`, `/mcp` and the OAuth endpoints sits inside `authenticate :user`. A deck therefore cannot be shown to anybody but its owner, and a decklist is the one thing in Cartodex a player actually wants to send someone.

This change gives a deck two states, private and shared, and moves three surfaces outside the session gate: a shared deck, the card catalog, and the dashboard. A visitor with a link reads a decklist and can copy it into TCG Live; a visitor without one lands on a dashboard that searches the card catalog and the shared decks, and nothing else.

## Scope

**In:** the `key` that addresses a deck, the `shared` flag and its Share control, the public deck view, the shared-deck index, the visitor dashboard, the shared navbar shell and its public variant, the card catalog without a session, the fourth search group, a Pundit policy layer for the new boundary, app-wide `noindex`, per-IP rate limits on the three endpoints that open, the three `/cards` queries that make one of them affordable, and the identity change rippling through the API, the Stimulus controllers and the MCP tools — outputs as well as inputs.

**Out — all of it on #142, none of it specified:** author attribution, public results/stats/tournaments, any public view of a collection, copying someone else's shared deck, comments/likes/counters, sitemap and Open Graph metadata, revoking a link that has already been passed around, and an MCP tool that shares a deck.

## Confirmed decisions (from the brainstorming interview)

1. **A deck is addressed by a `key`, on every route, private and public alike.** Not by its numeric id, and not by a second share-only URL. One deck, one address, whoever is looking.
2. **The key is stable for life.** Flipping a deck private makes its link 404; flipping it back revives the same link. There is no revocation, by design (#142).
3. **A shared deck shows its decklist and its exports.** Name, description, format and archetype, the grouped card list with images and preview, and the TCG Live / Cardmarket / image exports. Not the win-loss record, not `/stats`, not the real-vs-proxy split.
4. **The dashboard is the landing page for everyone.** Signed out it shows the search field, a showcase of the most recently shared decks, and Sign in / Sign up. Nothing personal — no collection card, no deck card, no import, no scanner.
5. **A signed-in user's search gains a second deck group.** "My decks" (all of them, private included) and "Shared decks" (other people's). A visitor sees the second group only.
6. **The shared decks have their own index**, `/decks/shared`, the same page for visitor and signed-in user. `/decks` stays the owner's private list, untouched.
7. **A shared deck names nobody.** No author, no pseudonym, and above all no email address (#142).
8. **The MCP contract breaks on purpose.** `deck_id: integer` becomes `deck_key: string`; a client holding remembered ids gets an error.
9. **Sharing is a "Share" entry in the deck's Actions dropdown**, opening a modal that carries both the private/shared toggle and the link to copy.
10. **Architecture: separate public views *and* a Pundit policy layer.** The read-only view is a different file, not a flag on the owner's view; the rules live in policies rather than in controller conditionals.

### Added after the review of this document

11. **`/decks/compare?ids[]=…` converts to keys.** A URL still carrying numeric deck ids after this change is the incoherence decision 1 exists to prevent, and it costs three lines.
12. **Nothing in the app is indexable, for now.** Not just the shared surfaces: `noindex, nofollow` on every response. Un-sharing takes a deck off Cartodex at once and would not take it out of a search engine for weeks, and opening `/cards` would publish a scraped catalog with its prices. Indexing becomes a deliberate decision when #142's SEO work is specified.
13. **All three newly public endpoints are rate-limited, and `/cards` is made cheap first.** Rationing an endpoint that loads the whole catalog would ration an amplifier instead of removing it.
14. **A visitor who signs in from a shared deck returns to it** (`store_location_for`), rather than landing on the dashboard.

### Added after the second review

15. **The image proxy keeps its limiter, at 300/min.** It caches no bytes, so each request is one fetch from a third party. The number is derived from the burst the public scope promises — one image export is at most 60 requests — not copied from another controller.
16. **Server-side byte caching for the image proxy is the real fix and is not in this change.** It would make the limiter unnecessary; it goes on #142 with the rest of the deferred scope.

## Facts established before designing (measured, not assumed)

- **`enum :visibility, { private: …, public: … }` will not load.** `ActiveRecord::Base.dangerous_class_method?` is `true` for both `:public` and `:private`, so the scopes the enum generates are refused. An *attribute* named `public` is fine (`dangerous_attribute_method?(:public)` is `false`), and so is `key`. The column is therefore a boolean and the scopes are written by hand — as `shared` / `unshared`, which also matches the "Share" verb in the UI.
- **The clipboard controller already copies a static string.** `clipboard_controller.js` declares `static values = { url: String, text: String }` and prefers `text` when present. The share modal needs no new JavaScript.
- **The image export reads the DOM, and pins the public card row's markup.** `deck_image_export_controller.js` queries `.deck-card-item`, reads `dataset.cardPreviewUrl` and `.deck-card-qty` inside each, and names the file from `.deck-show-header h1`. Exports are in scope for a shared deck, so the public row and header must keep those four hooks or the export silently produces an empty image.
- **Six Stimulus controllers declare `deckId: Number`**: `result_modal`, `archetype_picker`, `deck_card_owned_copies`, `printing_picker`, `card_search`, `deck_card_quantity`. A seventh, `tournament_pdf`, reads a deck id out of a dataset attribute and builds the export URL by hand.
- **Routes declared inside a `resources` block are drawn before the member routes.** The app already relies on it for `matchups` and `compare`, so `/decks/shared` cannot be swallowed by `/decks/:id`. A fixed-length 22-character key makes it doubly impossible.
- **Fixtures bypass callbacks.** `NameNormalizable` already documents this for `name_normalized`; a `NOT NULL` key means every row of `test/fixtures/decks.yml` must spell one out or the whole suite fails at insertion.
- **`RATE_LIMIT_STORE` is already duplicated.** The `Module.new` that proxies to `Rails.cache` at call time exists verbatim in `Mcp::ServerController` and `Oauth::RegistrationsController`. This change adds a third limiter, which is the moment to extract it.
- **The admin panel has its own gate.** `Admin::BaseController#require_admin!` redirects unless `current_user&.admin?`, independently of the routes' `authenticate` block, so the admin surface is unaffected by anything below.
- **There is no pagination gem.** `CardsController` hand-rolls `PER_PAGE` with `offset`/`limit` and computes `@pages`. `/decks/shared` follows that, rather than introducing a dependency.
- **`resources :decks` has `deck_results` nested inside it.** Moving the deck resource out of the `authenticate` block takes the nested result routes with it — see "The guard that moves" below.

Added after a review pass over this document, each verified in the branch:

- **`HomeController#dashboard` calls `authenticate_user!` in its own body** (`home_controller.rb:9`), on top of the app-wide `before_action`. A `skip_before_action` does not touch it.
- **A halting `before_action` skips the `after_action` too**, so `verify_authorized` cannot observe a missing `authorize` on a signed-out request to an owner-only action.
- **An unknown key and a private deck raise different exceptions** — `ActiveRecord::RecordNotFound` and `Pundit::NotAuthorizedError` — and therefore reach different renderers unless both are rescued.
- **`/decks/compare` carries numeric deck ids in its query string**: `decks_controller.rb:77`, `decks/deck_card.rb:22` (`value: @deck.id`), `deck_compare_controller.js:41`.
- **`/cards` instantiates the whole catalog to print set counts.** `CardSet.by_release.includes(:cards)` (`cards_controller.rb:7`) exists only so the sidebar can render `card_set.cards.size` (`cards/index_view.rb:93`).
- **`Home::DashboardView` prints the user's email** in its `h1` (`dashboard_view.rb:10`) — the only email on the page.
- **`Decks::Duplicator` copies an explicit attribute allowlist**, so a new column can never leak through it.
- **`test/fixtures/decks.yml` has two rows**, and one test builds a deck URL by hand (`test/controllers/api/deck_results_controller_test.rb`, private `deck_results_path`).
- **`Search::ResultsList` derives its option ids from `deck.id`** (`results_list.rb:35`), so one deck rendered in two groups emits one DOM id twice.

And after a second review pass:

- **`over_allocations/index_view.rb:32` calls `deck_path(d[:id])` with a bare integer** — the only `deck_path` in the app not given a model, so `to_param` cannot save it.
- **`ListOverAllocationsTool` serialises the service output directly** (`list_over_allocations_tool.rb:7`), deck ids included; `list_decks_tool.rb:2`'s description says "with their ids". The other twelve tools emit no deck identifier.
- **`/cards` and `/cards/:id` hotlink `card.image_url`** (`cards/index_view.rb:168`, `cards/show_view.rb:77` and `:159`). The proxy serves only the deck page's hover and the image export.
- **`#image` caches nothing server-side** — `HttpFetcher` runs on every request; `expires_in` only sets a header.
- **`deck_image_export_controller.js` loads every card image in parallel** (`Promise.all`) through the proxy, which `img.crossOrigin` + `canvas.toBlob` require to be same-origin.
- **Neither `rarity` nor `regulation_mark` is indexed** (`db/schema.rb`, table `cards`), and `cards_controller.rb:26-27` scans both on every request.
- **`app/controllers` holds 36 `*_controller.rb` files.** The earlier count of 39 included the concerns.
- **`Mcp::ServerController` inherits `ActionController::API`**, not `ApplicationController`.
- **`Admin::DecksController` is already unscoped** (`admin/decks_controller.rb:4,8`) and cannot be otherwise.
- **`Search::Global#total_for` re-runs a `count`** once a page fills its cap (`global.rb:65-67`).
- **`Ui::AppNavbar` links six destinations**, none of them a shared-deck index; the mobile chrome that `click_nav_link` needs lives in `app_navbar.rb:11-20`.
- **`public/robots.txt` exists and is the Rails default** — a comment and nothing else.
- **`yield(:head)` is available in the layout** (`application_layout.rb:15`) and Phlex writes `content_for` (`styleguide/page_view.rb:37`), so a per-page meta has an insertion point — though decision 12 makes it app-wide instead.

And after the review of the two implementation plans, each of which had reused an existing component without reading all of it:

- **`Decks::DeckCard` prints the win rate.** Lines 10–17 render a foil sheen and a `★ 63%` flag when `Deck#hot?` is true — five decided results at 60% or better — which is the record decision 3 keeps private, read from `deck_results` on every row. Lines 19–25 render the compare checkbox whatever the page. Reusing the row on `/decks/shared` therefore needs one switch that turns off the owner's badges, the foil flag *and* the checkbox together; `with_actions: false` hides the dropdown and nothing else.
- **`check_box_tag` posts nothing when unchecked**, unlike the form builder's `check_box`, which emits a hidden `"0"` first. `ActiveModel::Type::Boolean.new.cast(nil)` is `nil`, and `shared` is `NOT NULL`. The Share form needs the hidden field, and the action a `|| false` behind it.
- **A Turbo Stream `replace` on a `<turbo-frame>` inside an open `<dialog>` must render the frame, not the dialog** — a `<dialog>` rendered inside another is closed, and the open one goes blank. The Share control is therefore two components, the dialog and the frame it contains.
- **No system test builds a full URL** and nothing sets `default_url_options` for them, so `deck_url(deck)` in `test/system/` either raises or names a host that is not Capybara's. Assert on a path suffix.
- **`test/fixtures/archetypes.yml` has no `:one`.** Its rows are `ogerpon` and `budew_ogerpon`.

## Data model

### `decks.key`

| column | notes |
|---|---|
| `key` | string, NOT NULL, UNIQUE index — the deck's address, everywhere |

```ruby
before_validation :assign_key, if: -> { key.blank? }
validates :key, presence: true

def to_param = key

private

def assign_key
  self.key = SecureRandom.urlsafe_base64(16)   # 22 chars, 128 bits
end
```

`before_validation` rather than `before_create` so that the callback and the validation agree: with `before_create` plus a presence validation, `Deck.new(name: "x").valid?` would be `false` while `save` succeeded. The `key.blank?` guard does two jobs — `before_validation` also runs on update, and a row written by a callback-bypassing insert heals on its next save.

No `validates :key, uniqueness: true`. It would add a SELECT to every deck save to guard a collision on 128 bits of entropy that will not happen; the UNIQUE index is the guarantee, exactly as it is for `(set_name, set_number)` on `Card`.

The length is fixed at 22 characters, which is what makes `/decks/shared` unambiguous no matter what the generator returns.

### `decks.shared`

| column | notes |
|---|---|
| `shared` | boolean, NOT NULL, `default: false` |

```ruby
scope :shared,   -> { where(shared: true) }
scope :unshared, -> { where(shared: false) }
```

Written by hand because Active Record refuses a `public` or `private` scope, and named `shared`/`unshared` so that the column, the scopes, the modal, the badge and the URL all use one word.

The index is `add_index :decks, [:shared, :created_at]`, **not** a partial index on `shared` alone. Two of the three readers order by `created_at` — the showcase (`limit(6)`) and the paginated index — and an index on a single-valued boolean only enumerates rows, it does not serve a sort. The third reader is the search group's `LIKE '%…%'`, which stays a scan whatever we index: the composite index narrows the row set it scans, and nothing more. Any claim that the pattern itself is "bounded by the index" would be false.

Existing decks come out of the migration private. **`Decks::Duplicator` already cannot carry `shared` over** — it builds the copy from an explicit attribute allowlist, so a new column is excluded by construction. Nothing to change there; the invariant is worth a test precisely because the next person to add a column may reach for `dup` instead.

### The identity rule

The key is a deck's identifier **everywhere it crosses a boundary of the app** — URL segment, JSON field, MCP tool argument, Stimulus value. `decks.id` stays the primary key and the target of every foreign key, so a `<select>` of decks (the tournament form) and internal form parameters (`over_allocations#reallocate`'s `from_deck_id` / `to_deck_id`) keep carrying the integer: those reference a row, they do not address a page.

### Where the unscoped lookup lives — the rule this design rests on

This change **creates exactly one** unscoped `Deck.find_by!(key: …)`: in the publicly reachable actions of `DecksController`, immediately followed by `authorize`. Everywhere else — the API, `deck_results`, `over_allocations`, MCP — the lookup stays scoped by association and merely changes its key: `current_user.decks.find_by!(key: …)`.

`Admin::DecksController` is the honest exception, and it is not new: `Deck.includes(:user, :deck_cards)` and `Deck.…find(params[:id])` (`admin/decks_controller.rb:4,8`) are already unscoped and cannot be otherwise — an admin panel lists everybody's decks. They change key like the rest and keep `Admin::BaseController#require_admin!` as their guard. Saying "no unscoped lookup survives anywhere" would be false, and this is the one sentence in the document that has to be exact.

This is what keeps a change that mechanically touches every deck lookup in the app from opening a hole in any of them. The key replaces the id *inside* the ownership scope; the ownership guarantee does not move.

#### Blast radius (counted, not estimated)

- **13 lookups in 7 files** switch from an id to a key: `DecksController` (7 — lines 33, 52, 89, 121, 129, 141, 147), `DeckResultsController` (1), `Api::DecksController` (1), `Api::DeckResultsController` (1), `DeckCardPayload` (1), `Admin::DecksController` (1), `McpTool#find_deck!` (1).
- **A 14th deck identifier lives in a URL and is not a lookup**: `/decks/compare?ids[]=…`. `DecksController#compare` does `Array(params[:ids]).map(&:to_i)` and `Decks::DeckCard`'s checkbox carries `value: @deck.id`. It converts to keys — `map(&:to_s)`, `where(key: ids)`, and the result re-sorted by `ids.index(deck.key)`. **Two Ruby edits and no JavaScript**: `deck_compare_controller.js` treats the checkbox value as an opaque string from `#selected()` through to `params.append`, with no numeric coercion anywhere, so it is not one of the controllers below.
- **2 deliberately stay numeric**: `OverAllocationsController#reallocate`'s `from_deck_id` and `to_deck_id` come from a `<select>` of the user's decks, so they reference rows, not addresses.
- **35 path-helper call sites** (`deck_path`, `deck_url`, `export_deck_path`, …) change what they emit without being edited at all — that is the whole point of `to_param`, and it is also why a half-finished migration is invisible until a request 404s. Hence the `to_param` test in family 6.
- **The 36th does not**, and it is a bug the moment the key lands. `over_allocations/index_view.rb:32` calls `deck_path(d[:id])` with a bare integer — the only `deck_path` in the app not handed a model — so `to_param` never runs and the helper keeps emitting `/decks/42` while `#show` looks up `find_by!(key: "42")`. **Every deck link in the over-allocation report would 404.** The fix belongs upstream in `Allocations::PhysicalDecksByCard`: add `decks.key` to the `pluck` and `key:` to the hash, *keeping* `id:`, which feeds the reallocation form's `from_deck_id`/`to_deck_id`. Then the view uses `deck_path(d[:key])`.
- **7 Stimulus controllers** and **7 MCP tool schemas** change explicitly. One test builds a deck URL by hand and must follow: `test/controllers/api/deck_results_controller_test.rb`'s private `deck_results_path`.
- **1 unscoped lookup is created**, in `DecksController`. `Admin::DecksController`'s two were already unscoped — see the paragraph above.

Owner-only actions still call `authorize @deck` after the scoped find. The redundancy is deliberate: it makes the policy the single readable statement of the rules, and it is what will make it safe the day somebody replaces a scoped find with a bare one.

## Authorization

`gem "pundit"`, `include Pundit::Authorization` in `ApplicationController`, policies in `app/policies/`.

**`current_user` can be `nil`**, so `ApplicationPolicy` is written by hand without the `raise … unless user` that Pundit's generator template sometimes carries. A policy that rejects an absent user makes every public page impossible.

### `DeckPolicy`

| query | rule | why |
|---|---|---|
| `show?`, `export?` | `owner? \|\| record.shared?` | decklist and exports, decision 3 |
| `tournament_pdf?` | `owner?` | it reads one of the owner's `tournament_profiles` |
| `stats?` | `owner?` | the win-loss record stays private |
| `results?` | `owner?` | called by `DeckResultsController`, whose routes are nested under the deck resource and therefore now sit outside the `authenticate` block |
| `update?`, `destroy?`, `duplicate?`, `share?` | `owner?` | including every API write on the deck's cards |
| `create?` | `user.present?` | |
| `shared_index?` | `true` | the index of shared decks is open |
| `Scope#resolve` | `user ? Deck.where(user:).or(Deck.shared) : Deck.shared` | "the decks I may see" |

No `user.admin?` clause. Adding one would let an admin open any private deck at its normal URL, which is well beyond what an admin panel needs; `Admin::BaseController` keeps its own gate and its own unscoped lookups.

`CardPolicy` answers `true` to `index?`, `show?` and `image?`, and `DashboardPolicy` answers `true` to `show?`. A policy that says "yes, to everyone" is not ceremony here — it is the written trace of a decision, and it is what stops `verify_authorized` from having a blind spot.

### The 404, and why it is not a 403

The response is **404**, and it is byte-identical whether the key is unknown, the deck is private, or the viewer is a signed-in stranger.

What must not leak is the existence of **private** decks. A 403 on `/decks/:key` would say "this key names a real deck, you may not see it", so a scan of random keys would separate "no such deck" from "a private deck lives here" — an unguessable address turned into an existence oracle. It is not that the key is a secret: decision 6 lists every *shared* deck at `/decks/shared`, so sharing here means publishing, not sending a confidential link. The secrecy that matters belongs to the decks nobody shared.

**Two exceptions have to land on the same renderer, and by default they do not.** An unknown key raises `ActiveRecord::RecordNotFound` from `find_by!` and gets Rails' own 404; a private deck raises `Pundit::NotAuthorizedError` and gets ours. Test family 2 compares the responses, not just the statuses, so the concern rescues both:

```ruby
included do
  after_action :verify_authorized
  rescue_from ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, with: :not_found
end
```

Rescuing `RecordNotFound` in these controllers also preserves today's behaviour, where `current_user.decks.find` on somebody else's deck is already a 404. The alternative — `find_by` and then authorize the `nil` — does not work: Pundit cannot route `nil` to a policy.

`not_found` renders the **static page the rest of the app already uses**: `render file: Rails.public_path.join("404.html"), status: :not_found, layout: false`. Not an application 404 with a navbar: `/tournaments/999` would keep serving the static file, and a deck answering differently from everything else in the app is a difference nobody asked for. An in-app 404 page is a scope addition, not a detail of this one.

### The guard that moves

Four entries leave `authenticate :user`: `get "dashboard"`, `get "search"`, `resources :decks` and `resources :cards`. They do not lose their guard — they move it into the controller — but they do lose one of the two belts, and the nested `deck_results` routes ride out with the deck resource.

The concern that keeps the two halves inseparable:

```ruby
# A controller reachable without a session. The three things it does must never
# be separated: it drops the app-wide Devise gate for the actions it names, it
# makes Pundit's verify_authorized mandatory on *every* action of the
# controller, and it routes both "you may not" exceptions onto one renderer so
# an unknown key and a private deck are indistinguishable.
module PubliclyReachable
  extend ActiveSupport::Concern

  included do
    after_action :verify_authorized
    rescue_from ActiveRecord::RecordNotFound, Pundit::NotAuthorizedError, with: :not_found
  end

  class_methods do
    def publicly_reachable(*actions)
      skip_before_action :authenticate_user!, only: actions
    end
  end
end
```

In a controller that includes it, **every** action calls `authorize` — index-shaped actions call `authorize Deck, :shared_index?` alongside `policy_scope`, rather than relying on `verify_policy_scoped`. One rule to re-read instead of two.

**`verify_authorized` catches less than the comment above promises, and the test plan has to make up the difference.** A `before_action` that halts the chain skips the remaining callbacks *and* the `after_action`, so on a signed-out request to an owner-only action, `authenticate_user!` redirects and `verify_authorized` never runs. A missing `authorize` on `edit`, `update`, `destroy`, `duplicate`, `stats` or `share` is therefore invisible to a signed-out test. Test family 1 adds a **signed-in** request per action for exactly this reason.

`verify_authorized` is deliberately *not* installed application-wide. Exactly five of the 36 controllers in `app/controllers` are affected by the routing change — `HomeController`, `SearchController`, `DecksController`, `CardsController` and, by nesting, `DeckResultsController`. Every other one is scoped by association and would need a `skip_after_action` for no gain. The residual risk — a controller moved out of the block in six months without including the concern — is a deliberate, reviewable act.

`DeckResultsController` is the immediate case, and it is the one place where the two halves come apart on purpose. Its routes leave the block by nesting, but it is **not** publicly reachable: it does not include the concern, it keeps `ApplicationController`'s `before_action :authenticate_user!` as its only gate, and it therefore gets no `verify_authorized`. It still calls `authorize @deck, :results?` after its `current_user.decks.find_by!(key: …)` — nothing enforces that call, which is why family 1 tests it signed in as well as signed out.

## Routing

```ruby
# Outside `authenticate :user`. These controllers straddle the session boundary
# and gate themselves through PubliclyReachable; everything else stays inside.
get "dashboard", to: "home#dashboard"
get "search",    to: "search#show"

resources :decks, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
  get   :shared,  on: :collection   # /decks/shared
  patch :share,   on: :member
  # …existing matchups, compare, export, stats, duplicate, deck_results
end

resources :cards, only: [ :index, :show ] do
  get :image, on: :member
end

root "home#dashboard"
```

`HomeController#welcome` and `Home::WelcomeView` are deleted: the visitor dashboard carries the Sign in / Sign up buttons, so the old landing page says nothing new. `get "dashboard"` stays alongside `root` — the navbar brand and existing bookmarks name it, and two routes onto one action cost nothing.

Everything else — collections, over_allocations, tournaments, tournament_profiles, settings, `namespace :admin`, `namespace :api`, styleguide — stays inside the block.

## Controllers

### `HomeController`

```ruby
include PubliclyReachable
publicly_reachable :dashboard
```

**Delete the `authenticate_user!` call inside `#dashboard`.** The action carries one today (`home_controller.rb:9`) on top of the app-wide `before_action`, left over from when `welcome` was the only skipped action. `publicly_reachable` issues a `skip_before_action`, which does nothing about a call inside the method body: leave it and the visitor dashboard redirects to sign-in with no visible cause. This is the kind of line that survives a mechanical edit, which is why it is written down.

`#dashboard` authorizes `:dashboard, :show?`, then:

- signed in: today's page, unchanged, plus the showcase;
- signed out: `@pending_deck_imports = []`, no collection or deck card, no import panel, no scanner modal.

The `h1` currently reads `"Welcome, #{@current_user.email}"` (`dashboard_view.rb:10`). It is the only place on the dashboard that prints an email, and decision 7 forbids one on a public surface — so it lives in `signed_in_grid`'s branch, not above it.

The showcase is `Deck.shared.order(created_at: :desc).limit(6)`, preloading `archetype: [:primary_card, :secondary_card]` and `standard_pool: [:first_card_set, :last_card_set]` — the format badge names the pool and reads both bounds, which is three extra queries per Standard deck otherwise.

### `DecksController`

```ruby
include PubliclyReachable
publicly_reachable :show, :export, :shared
```

`#show` loads `Deck.find_by!(key: params[:id])` **bare**, calls `authorize @deck`, then branches **once** and only then loads what the branch needs:

- `@deck.user == current_user` → reload as `current_user.decks.includes(:archetype, :tournaments, deck_cards: :card, deck_results: []).find(@deck.id)`, then today's path intact (`@availability`, `@swappable_card_ids`, `@over_allocated_card_ids`, `@tournament_profiles`) and `Decks::ShowView`;
- otherwise → reload as `Deck.includes(deck_cards: :card).find(@deck.id)` and render `Decks::PublicShowView`. None of the allocation queries run, and neither `deck_results` nor `tournaments` is touched.

The reload is deliberate. `includes` cannot be added after a `find_by!`, so the alternatives were to load with the owner's preloads up front — which would make a visitor's request load `deck_results` and `tournaments`, exactly what the anti-leak section claims it avoids — or to authorize before loading anything else and pay one extra query. The second is the order this design wants, and one query is its price.

`#show`, when it renders the public view, calls `store_location_for(:user, request.fullpath)`. Devise only remembers a location when `authenticate_user!` bounces a request, so without this a visitor who clicks Sign in on a shared deck lands on the dashboard and has to find the deck again.

`#export` authorizes `:export?`; its `tournament_pdf` branch authorizes `:tournament_pdf?` first.

`#shared` authorizes `Deck, :shared_index?` and renders `Deck.shared`, newest first, hand-paginated at `PER_PAGE = 24`, with the **same preloads as the showcase** — 24 rows each rendering `Decks::PublicBadges` → `format_label` → `StandardPool#name` → its two bounds is 72 avoidable queries a page. Filters are the query, the format and the archetype. Not `physical`, not `tcg_live`, not `proxies` — none of them means anything without a collection to compare against.

Its archetype filter options come from `Deck.shared` — the archetypes of the shared decks, in one query. **Not** `member_card_filter_options`, which starts from `current_user.decks` and would offer a visitor a filter derived from nobody's decks (and a member a filter that hides half the page).

Every other action keeps `authenticate_user!` and calls `authorize`. Which form it takes is not left to taste, because `verify_authorized` applies to every action of this controller:

- record actions — `edit`, `update`, `destroy`, `duplicate`, `stats`, `share` — find through `current_user.decks.find_by!(key: …)` and call `authorize @deck`;
- record-less actions — `index`, `new`, `create`, `matchups`, `compare` — call `authorize Deck, :index?` / `:create?` on the class, since there is no record yet to reason about.

`#share` (`PATCH`) authorizes `:share?` and writes `shared` from `ActiveModel::Type::Boolean.new.cast(params[:shared])`. The checkbox form carries a hidden `"0"` field because an unchecked bare checkbox posts nothing at all, and `nil` against the `NOT NULL` column would raise — the explicit cast plus `|| false` in the action is the belt behind that hidden field, not a defense against `"0"` itself (Active Record already casts `"0"` to `false` for a boolean attribute). It answers with a Turbo Stream re-rendering the modal so the link appears in place.

### `CardsController`

```ruby
include PubliclyReachable
publicly_reachable :index, :show, :image
```

`@collection_quantity` becomes `current_user&.collections&.find_by(card_id: @card.id)&.quantity.to_i`, and `Cards::ShowView` takes a `signed_in:` argument that gates `collection_control` — the only owner-facing block in the card views.

### What it costs to open three endpoints

Three unauthenticated endpoints do real work per request, and each needs its own answer. `RATE_LIMIT_STORE` — the `Module.new` proxying to `Rails.cache` at call time, currently copy-pasted in `Mcp::ServerController` and `Oauth::RegistrationsController` — is extracted into one shared constant here, so the marginal cost of each limiter below is a single `rate_limit` line. It goes in **`app/lib/rate_limit_store.rb`**, not in `ApplicationController`: `Mcp::ServerController` inherits from `ActionController::API`, so a constant on `ApplicationController` would be out of its reach. Its existing comment travels with it — the proxy-at-call-time is what lets tests substitute `Rails.cache`, and capturing the store at class load would defeat that.

All the limiters are per-IP and `unless: -> { user_signed_in? }`, so an authenticated user never spends a visitor's budget, and all pass an explicit `name:` so their cache keys stay distinct.

**`/cards/:id/image`** fetches from limitlesstcg.com **on every request** — `#image` calls `HttpFetcher` and caches no bytes server-side, so `expires_in 30.days` is a response header and nothing more. Absent a shared cache in front, one inbound request is one outbound request to a third party: an amplifier, and the reason this endpoint keeps a limiter rather than relying on caching alone. `public: true` instead of `public: false` all the same, so any cache that *is* in front can help.

The budget is **300/min**, derived rather than copied: the proxy serves exactly two things — the deck page's hover preview and the image export — and `/cards` and `/cards/:id` do not use it at all (they hotlink `card.image_url` directly). The export loads every printing of a deck in parallel, and a deck holds at most 60 cards, so one export is at most 60 image requests in a burst. 300/min leaves five exports a minute per IP. Copying `Mcp::ServerController::IP_RATE_LIMIT_TO = 30` would have broken the second export of the minute — an export the public scope explicitly promises (decision 3).

Caching the bytes server-side is the real fix and would make the limiter unnecessary; it is deferred to #142, not part of this change.

**`/cards`** loads the entire catalog on every request, signed in or not: `CardSet.by_release.includes(:cards)` instantiates every `Card` in the database, and the only thing the view does with them is print `card_set.cards.size` in the sidebar (`cards/index_view.rb:93`). That `includes` becomes a grouped count (`Card.group(:card_set_id).count`, passed to `Cards::IndexView` alongside `@blocks`).

Two full scans remain after that, and they have to be dealt with in the same breath or the claim "each ask is now cheap" is false: `@rarities` and `@marks` are `distinct … pluck` over `cards`, and neither `rarity` nor `regulation_mark` is indexed. Both lists only change when a set is imported, so they go behind `Rails.cache.fetch` keyed on `Card.maximum(:updated_at)`. Not two new indexes — a cache is the honest answer for a low-cardinality column read on every page load.

With those two done, the action gets a limiter as well: the limiter bounds how often a visitor may ask, the query work is what makes each ask affordable, and rate-limiting an endpoint that scans the whole catalog three times would ration an amplifier instead of removing it.

**`/search`** answers a `LIKE '%…%'` over the whole card catalog per keystroke, plus — now — the shared decks. `MIN_QUERY_LENGTH = 2` and `NameNormalizable::MAX_QUERY_LENGTH = 100` bound the pattern, nothing bounds the rate. It gets a limiter too.

## Views

| component | change |
|---|---|
| `Layouts::ApplicationLayout` | renders `Ui::AppNavbar` when signed in, `Ui::PublicNavbar` otherwise — today it renders no navbar at all, which would leave a public page with no navigation; also carries the app-wide `robots` meta |
| `Ui::NavbarShell` | new: `nav.navbar` > `.navbar-inner` > brand + `.navbar-toggle` + `.navbar-menu[data-navbar-target=menu]`, extracted from `Ui::AppNavbar` and yielding its links |
| `Ui::PublicNavbar` | new: renders `Ui::NavbarShell`; brand → `root_path`, links Cards and Shared decks, Sign in / Sign up |
| `Ui::AppNavbar` | renders `Ui::NavbarShell`; gains a "Shared decks" link |
| `Home::DashboardView` | `current_user:` becomes nullable; splits into `signed_in_grid` and `visitor_call_to_action`, plus the showcase section |
| `Ui::ArchetypeBadge` | extracted from `Decks::ClassificationBadges`, so the public badges can reuse it instead of duplicating twelve lines |
| `Decks::ClassificationBadges` | consumes `Ui::ArchetypeBadge`; gains a "Shared" badge (owner views only) |
| `Decks::PublicBadges` | new: format label + `Ui::ArchetypeBadge`, and nothing else |
| `Decks::PublicShowView` | new: header, card-count stat, grouped card list, preview pane, export dropdown minus the tournament PDF |
| `Decks::PublicDeckCardItem` | new, ~25 lines: quantity as text, name, `SET NUMBER` as plain text, preview hooks |
| `Decks::SharedIndexView` | new: the shared index, deck cards with `Decks::PublicBadges` and no actions dropdown |
| `Decks::ShareModal` | new: the `<dialog>`, following `Decks::ResultModal`'s pattern; renders `Decks::ShareFrame` |
| `Decks::ShareFrame` | new: the `<turbo-frame>` the PATCH re-renders — the toggle (with the hidden `"0"` field), the sentence below, and when shared `deck_url(@deck)` in a readonly field with a `clipboard`-controller copy button. Separate from the dialog because a stream that re-rendered the dialog would nest a closed one inside the open one |
| `Decks::ActionsDropdown` | gains "Share…" |
| `Cards::ShowView` | `signed_in:` gates `collection_control` |
| `Search::ResultsList` | gains the "Shared decks" group |
| `Home::WelcomeView` | deleted |

**No proxy badge and no "To review" badge on any public surface.** Both report what the owner does or does not own, which is collection data reached through a deck.

**The share modal says "publish", not "here is a link".** Decision 6 lists every shared deck at `/decks/shared`, so offering only a link to copy would misdescribe what the toggle does. The modal must state that the deck will be **listed publicly**, and name what becomes visible: the deck's name, its **description** — free text often written while the deck was private — its format, its archetype and its card list. Nothing about results, collection or proxies.

**The navbar shell is shared, not duplicated.** Below 768px `.navbar-menu` is `display: none` until the `navbar` Stimulus controller adds `.navbar-menu--open`, and the suite's `click_nav_link` helper depends on exactly those two classes plus the toggle. A `Ui::PublicNavbar` that reimplemented "brand plus links" without the hamburger would make every mobile system test that navigates from a public page fail, and the failure would read as a Capybara visibility problem rather than as a missing hamburger. Hence `Ui::NavbarShell`: the chrome is identical, only the links differ.

**A signed-in user needs the "Shared decks" link too.** Decision 6 says the index is the same page for visitor and member, but the only way in for a member would otherwise be the search group's "See all", which requires typing a matching query first — the visitor would navigate the app better than the member. One caveat to accept and write down: `/decks/shared` has `controller_name == "decks"`, so with the current `@active_controller` mechanism both "Decks" and "Shared decks" light up together. Passing a finer activation key is the fix; accepting the double highlight is also allowed, as long as it is a decision and not a surprise.

### Nothing is indexable, anywhere

Every response carries `X-Robots-Tag: noindex, nofollow`, set app-wide in `ApplicationController`, and `Layouts::ApplicationLayout` carries the matching `<meta name="robots" content="noindex, nofollow">`. The header rather than the meta alone because it also covers what has no `<head>`: the JSON API and the image proxy.

**`public/robots.txt` is deliberately left permissive**, and that is not an oversight. A path disallowed there is never fetched, so a compliant crawler reads neither the meta nor the header — and a URL somebody linked from outside can still surface as a bare result. Blocking the crawl defeats the de-indexing it is meant to reinforce. To have nothing appear in a search engine you must let the crawler in and hand it `noindex`, which is what the header does. The file gains a comment saying so, so the next person does not "fix" it with `Disallow: /`.

This covers the whole app, not only the shared surfaces: `/cards` and `/cards/:id` become public too, and they publish the entire catalog scraped from Limitless — card text, `price_eur`, `price_usd`, `cardmarket_url` — with images hotlinked from a third party's CDN for anonymous traffic. Whether any of that should be indexable is a decision for the day #142's SEO work is specified; until then the answer is no, for everything.

The public card row must keep the class `deck-card-item`, the `data-card-preview-url` attribute and a `.deck-card-qty` element, and the public header must keep its `h1` inside `.deck-show-header`. Those four are the contract `deck_image_export_controller.js` reads, and the image export is in the public scope.

## Search

`Search::Global` accepts `user: nil` and grows a fourth group.

```ruby
Result = Data.define(
  :query, :decks, :deck_total, :shared_decks, :shared_deck_total,
  :cards, :card_total, :tournaments, :tournament_total
)
```

`#total` sums all four, so `any?` keeps working.

```ruby
def deck_scope
  @deck_scope ||= @user ? @user.decks.search(@query) : Deck.none
end

def shared_deck_scope
  @shared_deck_scope ||= begin
    scope = Deck.shared
    scope = scope.where.not(user: @user) if @user
    scope.search(@query)
  end
end

def tournament_scope
  @tournament_scope ||= @user ? @user.tournaments.name_matching(@query) : Tournament.none
end
```

`where.not(user: @user)` exists for one reason: a user's own shared deck must not appear in both deck groups of the same result list.

It came close to carrying a second, and that is worth avoiding rather than documenting. `Search::ResultsList` builds its option ids as `"spotlight-option-deck-#{deck.id}"` (`results_list.rb:35`), so one deck rendered in two groups would emit the same DOM id twice and `dashboard_search_controller.js`'s `querySelectorAll("[role=option]")` would take whichever the browser handed it. **The shared group therefore prefixes its ids differently** (`spotlight-option-shared-deck-…`). It costs nothing, and it means the first person who decides members *should* see their own decks in the public group breaks a product rule rather than silently breaking keyboard navigation.

`Deck.search` composes correctly on top of a filtered scope — its internal `#or` evaluates both sides against the current scope, so each branch carries the `shared` and the `where.not`. The existing constraint still holds: `search` before any `includes`, because `#or` refuses relations that do not carry the same includes. The shared group then takes the **same preloads the "My decks" group already has** (`:archetype`, `standard_pool: [:first_card_set, :last_card_set]`); its rows render the format badge exactly as the other group's do.

Cost is **up to two** more scans per keystroke, not one: `total_for` re-runs a `count` on the scope as soon as the page fills its cap, so a query broad enough to return five shared decks pays for the page and again for the total. That is the existing trade-off applied to a fourth group, and the queries that pay it are the short frequent ones the debounce lets through. The `[:shared, :created_at]` index narrows the rows those scans visit; it does nothing for the pattern itself, and no index would. Below `MIN_QUERY_LENGTH` nothing touches the database, unchanged. `/search` is also rate-limited per IP for visitors — see "What it costs to open three endpoints".

The "Shared decks" group's "See all" points at `shared_decks_path(q: …)`, and its rows render `Decks::PublicBadges`.

## API and MCP

No API action leaves the `authenticate` block: the public deck page is read-only and calls nothing. The API changes identity only.

- `Api::DecksController#deck_json` exposes `key:` instead of `id:`.
- `Api::DecksController#set_deck` and `DeckCardPayload#set_deck` become `current_user.decks.find_by!(key: params[:id | :deck_id])`.
- The six Stimulus controllers move from `deckId: Number` to `deckKey: String`; `tournament_pdf_controller.js` reads a key out of its dataset attribute.

### MCP — a breaking contract change, accepted

`McpTool#find_deck!` becomes `user.decks.find_by!(key:)`. `deck_id: integer` becomes `deck_key: string` on `add_card_to_deck`, `list_deck_cards`, `set_deck_card_owned_copies`, `set_deck_card_printing`, `set_deck_card_quantity` and `list_printings` (optional argument), and `reallocate_owned_copies` takes `from_deck_key` / `to_deck_key`. `list_decks` returns `key` instead of `id`, which is the only way a client discovers the new values, and its `description` stops saying "with their ids". Error strings say "unknown deck key".

**Inputs are not the whole contract.** `ListOverAllocationsTool` serialises `Allocations::OverAllocations` straight to JSON, and that payload embeds the `{ id:, name: }` deck hashes from `PhysicalDecksByCard`. Change only the inputs and the tool set becomes incoherent rather than merely breaking: a client reads "these three decks over-commit this card", then has no key to hand to `reallocate_owned_copies` and has to call `list_decks` and join on the name. The `PhysicalDecksByCard` fix above resolves it by construction — same service, one place. The other twelve tools were checked: `SuggestOwnedEquivalentsTool`, `ListPrintingsTool` and `ListDeckCardsTool` emit no deck identifier at all, so `ListOverAllocationsTool` is the only output that needed looking at.

A client that remembered numeric ids will error until it lists decks again. That is the cost of decision 1, and it is preferred to two identifiers coexisting.

No MCP tool shares or unshares a deck (#142).

## Migration and deploy

One migration: add `key` (string) and `shared` (boolean, `NOT NULL`, default `false`), backfill a key per existing row, then add the `NOT NULL` constraint and the UNIQUE index on `key`, plus `[:shared, :created_at]`.

Backfill inside the migration rather than in a rake task: `bin/docker-entrypoint` runs `db:prepare` before the server accepts traffic, so there is no window in which a keyless deck is served. The order matters for the same reason it does for `standard_pool_id` — the constraint and the data must land in one step.

**The backfill must not go through the model.** `Deck#update!` would run `validates :standard_pool, presence: true, if: :standard?`, and any pre-#122 Standard deck that slipped through without an anchor would abort the migration halfway. Use `reset_column_information` and then `update_column`, or raw SQL: the migration's job is to fill a column, not to re-validate history.

`test/fixtures/decks.yml` gains a literal `key` on each of its two rows — fixtures skip callbacks, as the file's own note about `name_normalized` already says.

## Testing plan

Eight families. Five of them exist specifically to catch what this change can break, and two of those came out of reviewing this document rather than writing it.

1. **The guard that moved, action by action — twice per action.** A request test per action of the five affected controllers (`HomeController`, `SearchController`, `DecksController`, `CardsController`, `DeckResultsController`), **signed out**: owner-only actions redirect to sign-in, publicly reachable ones return 200. Per action, not per controller — an over-broad `skip_before_action` is precisely the bug.

   And a **signed-in** request per action, because that is the only way `verify_authorized` can fire at all: a halting `before_action` skips the `after_action` too, so the signed-out half of this family cannot see a missing `authorize` on `edit`, `update`, `destroy`, `duplicate`, `stats` or `share`.

   This family also carries the JS identity assertions. The existing system suite happens to exercise `printing_picker`, `deck_card_quantity` and `deck_card_owned_copies` (via `deck_printing_swap_test`, `deck_proxy_badge_test`, `deck_card_mobile_test`) and the spotlight, but nothing covers `result_modal`, `archetype_picker`, `card_search` or `tournament_pdf`. A renamed value that misses its controller fails silently — `deckKey` arriving at a controller still declaring `deckId: Number` yields `/api/decks/NaN/…`, and the reverse yields `/api/decks//…` — so those four get an assertion that the rendered attribute is the key. `/decks/compare`'s checkbox gets one too, for the same reason and without a controller change.
2. **The indistinguishable 404.** Visitor on a private deck's key, visitor on an unknown key, signed-in stranger on a private deck: all three 404, and the test compares the response **bodies**, not just the statuses — the two exceptions reach that renderer by different routes, and only the concern's double `rescue_from` makes them converge.
3. **The leak test.** A shared deck's public page does *not* contain the allocation steppers, the printing picker, "Log Result", the edit link, or the Proxies badge — explicit absence assertions. This one gets sabotage-verified by making the action render `Decks::ShowView` instead: an absence test that cannot fail proves nothing.
4. **`DeckPolicy` unit tests**: owner / other signed-in user / visitor × shared / unshared × every query.
5. **`Search::Global`**: with `user: nil` (no decks, no tournaments, cards and shared decks populated) and with a signed-in user, asserting that a shared deck belonging to the searcher appears exactly once.
6. **Identity**: key assigned on create, unchanged by an update, UNIQUE index raising on a duplicate, `shared` false by default, `Decks::Duplicator` producing an unshared copy (an invariant its attribute allowlist already gives us — the test guards the next person who reaches for `dup`), `to_param` returning the key, and both fixture rows carrying one.

   Write this family **first**. It is what makes the 35 path-helper call sites that change without being edited visible at all; run against a half-finished migration they fail, and run last they hide behind everything else.

Two more, from the second review, that no family above would catch:

7. **The over-allocation report's deck links.** A controller test on `over_allocations#index` asserting the HTML contains `deck_path(deck)` — the key — and **not** `/decks/#{deck.id}`. Sabotage it by restoring `d[:id]`; it must go red. Nothing else in the suite would notice, because that helper call is the one `to_param` cannot reach.
8. **The MCP contract, end to end.** Not just "the JSON has a `key` field": a test that chains the two tools — read `list_over_allocations`, take a deck's key from the report, hand it to `reallocate_owned_copies`, expect success. A presence assertion proves the field exists; only the chain proves the contract is coherent.

Plus system tests **at both viewports**, since the repo requires every system test to pass on each side of the 768px breakpoint:

- a visitor opens a shared link and sees the decklist;
- the owner opens the Share modal, flips the toggle, and the URL appears;
- **a visitor navigates from a public page** with `click_nav_link "Cards"` — this is the test that proves `Ui::PublicNavbar` really carries the hamburger and `.navbar-menu`, and it is the one the mobile half needs;
- **a signed-in user reaches `/decks/shared`** through `click_nav_link "Shared decks"`.

Known hazard on the mobile half — below the breakpoint the card preview becomes a `<dialog>` whose backdrop swallows subsequent clicks.

## Notes

`allow_browser versions: :modern` now applies to visitors too, so an old browser gets a 406 on a shared link instead of a decklist. Accepted: the alternative is a browser-support policy that differs by session state.
