# A deck can be shared, and three surfaces stop requiring a session — Design

Issue: none — requested directly. The scope deliberately left out is recorded on #142.

## Goal

Every route in the app except `/`, `/up`, `/mcp` and the OAuth endpoints sits inside `authenticate :user`. A deck therefore cannot be shown to anybody but its owner, and a decklist is the one thing in Cartodex a player actually wants to send someone.

This change gives a deck two states, private and shared, and moves three surfaces outside the session gate: a shared deck, the card catalog, and the dashboard. A visitor with a link reads a decklist and can copy it into TCG Live; a visitor without one lands on a dashboard that searches the card catalog and the shared decks, and nothing else.

## Scope

**In:** the `key` that addresses a deck, the `shared` flag and its Share control, the public deck view, the shared-deck index, the visitor dashboard, the public navbar, the card catalog without a session, the fourth search group, a Pundit policy layer for the new boundary, and the identity change rippling through the API, the Stimulus controllers and the MCP tools.

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

Written by hand because Active Record refuses a `public` or `private` scope, and named `shared`/`unshared` so that the column, the scopes, the modal, the badge and the URL all use one word. Partial index `WHERE shared = 1`, which is what the showcase, the index and the search group all read.

Existing decks come out of the migration private. **`Decks::Duplicator` must not carry `shared` over**: duplicating a shared deck produces a private copy, or a user publishes something by pressing Duplicate.

### The identity rule

The key is a deck's identifier **everywhere it crosses a boundary of the app** — URL segment, JSON field, MCP tool argument, Stimulus value. `decks.id` stays the primary key and the target of every foreign key, so a `<select>` of decks (the tournament form) and internal form parameters (`over_allocations#reallocate`'s `from_deck_id` / `to_deck_id`) keep carrying the integer: those reference a row, they do not address a page.

### Where the unscoped lookup lives — the rule this design rests on

`Deck.find_by!(key: …)` **without a user scope** appears in exactly one place: the publicly reachable actions of `DecksController`, each immediately followed by `authorize`. Everywhere else — the API, `deck_results`, `over_allocations`, admin, MCP — the lookup stays scoped by association and merely changes its key: `current_user.decks.find_by!(key: …)`.

This is what keeps a change that mechanically touches every deck lookup in the app from opening a hole in any of them. The key replaces the id *inside* the ownership scope; the ownership guarantee does not move.

#### Blast radius (counted, not estimated)

- **14 lookups in 7 files** switch from an id to a key: `DecksController` (8), `DeckResultsController` (1), `Api::DecksController` (1), `Api::DeckResultsController` (1), `DeckCardPayload` (1), `Admin::DecksController` (1), `McpTool#find_deck!` (1).
- **2 deliberately stay numeric**: `OverAllocationsController#reallocate`'s `from_deck_id` and `to_deck_id` come from a `<select>` of the user's decks, so they reference rows, not addresses.
- **35 path-helper call sites** (`deck_path`, `deck_url`, `export_deck_path`, …) change what they emit without being edited at all — that is the whole point of `to_param`, and it is also why a half-finished migration is invisible until a request 404s. Hence the `to_param` test in family 6.
- **7 Stimulus controllers** and **7 MCP tool schemas** change explicitly.
- **1 unscoped lookup** is created, in `DecksController`, and it is the only one.

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

`rescue_from Pundit::NotAuthorizedError` renders **404**, and renders it identically whether the key is unknown, the deck is private, or the viewer is a signed-in stranger. The key *is* the sharing secret: a 403 on `/decks/:key` would confirm that this key names a real deck, turning an unguessable address into an oracle. "There is no deck at this address for you" is the only honest answer, and it is what `current_user.decks.find` already says today.

### The guard that moves

Four entries leave `authenticate :user`: `get "dashboard"`, `get "search"`, `resources :decks` and `resources :cards`. They do not lose their guard — they move it into the controller — but they do lose one of the two belts, and the nested `deck_results` routes ride out with the deck resource.

The concern that keeps the two halves inseparable:

```ruby
# A controller reachable without a session. The two things it does must never be
# separated: it drops the app-wide Devise gate for the actions it names, and it
# makes Pundit's verify_authorized mandatory on *every* action of the controller.
# A publicly reachable action that forgets to authorize is the exact bug this
# feature can introduce, and the after_action is what turns it into a test
# failure instead of a leak.
module PubliclyReachable
  extend ActiveSupport::Concern

  included { after_action :verify_authorized }

  class_methods do
    def publicly_reachable(*actions)
      skip_before_action :authenticate_user!, only: actions
    end
  end
end
```

In a controller that includes it, **every** action calls `authorize` — index-shaped actions call `authorize Deck, :shared_index?` alongside `policy_scope`, rather than relying on `verify_policy_scoped`. One rule to re-read instead of two.

`verify_authorized` is deliberately *not* installed application-wide. Exactly five of the 39 controllers in `app/controllers` are affected by the routing change — `HomeController`, `SearchController`, `DecksController`, `CardsController` and, by nesting, `DeckResultsController`. Every other one is scoped by association and would need a `skip_after_action` for no gain. The residual risk — a controller moved out of the block in six months without including the concern — is a deliberate, reviewable act, and `DeckResultsController` is the immediate example: its routes are now outside the block, it does not include the concern, and it relies on `ApplicationController`'s `before_action :authenticate_user!`. A request test per action is what holds that.

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

`#dashboard` authorizes `:dashboard, :show?`, then:

- signed in: today's page, unchanged, plus the showcase;
- signed out: `@pending_deck_imports = []`, no collection or deck card, no import panel, no scanner modal.

The showcase is `Deck.shared.order(created_at: :desc).limit(6)`, preloading `archetype: [:primary_card, :secondary_card]` and `standard_pool: [:first_card_set, :last_card_set]` — the format badge names the pool and reads both bounds, which is three extra queries per Standard deck otherwise.

### `DecksController`

```ruby
include PubliclyReachable
publicly_reachable :show, :export, :shared
```

`#show` loads `Deck.find_by!(key: params[:id])`, calls `authorize @deck`, then branches **once**:

- `@deck.user == current_user` → today's path intact (`@availability`, `@swappable_card_ids`, `@over_allocated_card_ids`, `@tournament_profiles`) rendering `Decks::ShowView`;
- otherwise → `Decks::PublicShowView`, handed the deck and its preloaded `deck_cards: :card` and nothing else. None of the allocation queries run.

`#export` authorizes `:export?`; its `tournament_pdf` branch authorizes `:tournament_pdf?` first.

`#shared` authorizes `Deck, :shared_index?` and renders `Deck.shared`, newest first, hand-paginated at `PER_PAGE = 24`. Filters are the query, the format and the archetype. Not `physical`, not `tcg_live`, not `proxies` — none of them means anything without a collection to compare against.

Every other action keeps `authenticate_user!` and calls `authorize`. Which form it takes is not left to taste, because `verify_authorized` applies to every action of this controller:

- record actions — `edit`, `update`, `destroy`, `duplicate`, `stats`, `share` — find through `current_user.decks.find_by!(key: …)` and call `authorize @deck`;
- record-less actions — `index`, `new`, `create`, `matchups`, `compare` — call `authorize Deck, :index?` / `:create?` on the class, since there is no record yet to reason about.

`#share` (`PATCH`) authorizes `:share?` and writes `shared` from `ActiveModel::Type::Boolean.new.cast(params[:shared])` — the toggle posts `"0"`/`"1"`, which is truthy either way if assigned raw. It answers with a Turbo Stream re-rendering the modal so the link appears in place.

### `CardsController`

```ruby
include PubliclyReachable
publicly_reachable :index, :show, :image
```

`@collection_quantity` becomes `current_user&.collections&.find_by(card_id: @card.id)&.quantity.to_i`, and `Cards::ShowView` takes a `signed_in:` argument that gates `collection_control` — the only owner-facing block in the card views.

### The image proxy becomes an open proxy

`/cards/:id/image` fetches from limitlesstcg.com on a miss and is now reachable without a session. Two measures, both required:

- `expires_in 30.days, public: true` instead of `public: false`. A Pokémon card image is not a secret, and letting a shared cache absorb the traffic is the actual protection.
- a per-IP `rate_limit` on `image` alone, applied only when nobody is signed in, following the two existing limiters exactly: explicit `name:`, and a `store:` that proxies to `Rails.cache` at call time so tests can exercise the throttle. `RATE_LIMIT_STORE` is extracted out of `Mcp::ServerController` and `Oauth::RegistrationsController` into one shared constant as part of this change.

## Views

| component | change |
|---|---|
| `Layouts::ApplicationLayout` | renders `Ui::AppNavbar` when signed in, `Ui::PublicNavbar` otherwise — today it renders no navbar at all, which would leave a public page with no navigation |
| `Ui::PublicNavbar` | new: brand → `root_path`, links Cards and Shared decks, Sign in / Sign up |
| `Home::DashboardView` | `current_user:` becomes nullable; splits into `signed_in_grid` and `visitor_call_to_action`, plus the showcase section |
| `Ui::ArchetypeBadge` | extracted from `Decks::ClassificationBadges`, so the public badges can reuse it instead of duplicating twelve lines |
| `Decks::ClassificationBadges` | consumes `Ui::ArchetypeBadge`; gains a "Shared" badge (owner views only) |
| `Decks::PublicBadges` | new: format label + `Ui::ArchetypeBadge`, and nothing else |
| `Decks::PublicShowView` | new: header, card-count stat, grouped card list, preview pane, export dropdown minus the tournament PDF |
| `Decks::PublicDeckCardItem` | new, ~25 lines: quantity as text, name, `SET NUMBER` as plain text, preview hooks |
| `Decks::SharedIndexView` | new: the shared index, deck cards with `Decks::PublicBadges` and no actions dropdown |
| `Decks::ShareModal` | new: the toggle, and when shared `deck_url(@deck)` in a readonly field with a `clipboard`-controller copy button |
| `Decks::ActionsDropdown` | gains "Share…" |
| `Cards::ShowView` | `signed_in:` gates `collection_control` |
| `Search::ResultsList` | gains the "Shared decks" group |
| `Home::WelcomeView` | deleted |

**No proxy badge and no "To review" badge on any public surface.** Both report what the owner does or does not own, which is collection data reached through a deck.

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

`where.not(user: @user)` is load-bearing: without it a user's own shared deck appears in both deck groups of the same result list.

`Deck.search` composes correctly on top of a filtered scope — its internal `#or` evaluates both sides against the current scope, so each branch carries the `shared` and the `where.not`. The existing constraint still holds: `search` before any `includes`, because `#or` refuses relations that do not carry the same includes.

Cost is one more `LIKE` scan per keystroke, bounded by the `WHERE shared = 1` partial index, so cheaper than the full-catalog card scan already on that path. Below `MIN_QUERY_LENGTH` nothing touches the database, unchanged.

The "Shared decks" group's "See all" points at `shared_decks_path(q: …)`, and its rows render `Decks::PublicBadges`.

## API and MCP

No API action leaves the `authenticate` block: the public deck page is read-only and calls nothing. The API changes identity only.

- `Api::DecksController#deck_json` exposes `key:` instead of `id:`.
- `Api::DecksController#set_deck` and `DeckCardPayload#set_deck` become `current_user.decks.find_by!(key: params[:id | :deck_id])`.
- The six Stimulus controllers move from `deckId: Number` to `deckKey: String`; `tournament_pdf_controller.js` reads a key out of its dataset attribute.

### MCP — a breaking contract change, accepted

`McpTool#find_deck!` becomes `user.decks.find_by!(key:)`. `deck_id: integer` becomes `deck_key: string` on `add_card_to_deck`, `list_deck_cards`, `set_deck_card_owned_copies`, `set_deck_card_printing`, `set_deck_card_quantity` and `list_printings` (optional argument), and `reallocate_owned_copies` takes `from_deck_key` / `to_deck_key`. `list_decks` returns `key` instead of `id`, which is the only way a client discovers the new values. Error strings say "unknown deck key".

A client that remembered numeric ids will error until it lists decks again. That is the cost of decision 1, and it is preferred to two identifiers coexisting.

No MCP tool shares or unshares a deck (#142).

## Migration and deploy

One migration: add `key` (string) and `shared` (boolean, `NOT NULL`, default `false`), backfill a key per existing row, then add the `NOT NULL` constraint and the UNIQUE index on `key` plus the partial index on `shared`.

Backfill inside the migration rather than in a rake task: `bin/docker-entrypoint` runs `db:prepare` before the server accepts traffic, so there is no window in which a keyless deck is served. The order matters for the same reason it does for `standard_pool_id` — the constraint and the data must land in one step.

`test/fixtures/decks.yml` gains a literal `key` on every row.

## Testing plan

Six families. Three of them exist specifically to catch what this change can break.

1. **The guard that moved, action by action.** A request test per action of `DecksController`, `CardsController` and `DeckResultsController`, signed out: owner-only actions redirect to sign-in, publicly reachable ones return 200. Per action, not per controller — an over-broad `skip_before_action` is precisely the bug.
2. **The indistinguishable 404.** Visitor on a private deck's key, visitor on an unknown key, signed-in stranger on a private deck: all three 404, and the test compares the responses rather than asserting the same status three times.
3. **The leak test.** A shared deck's public page does *not* contain the allocation steppers, the printing picker, "Log Result", the edit link, or the Proxies badge — explicit absence assertions. This one gets sabotage-verified by making the action render `Decks::ShowView` instead: an absence test that cannot fail proves nothing.
4. **`DeckPolicy` unit tests**: owner / other signed-in user / visitor × shared / unshared × every query.
5. **`Search::Global`**: with `user: nil` (no decks, no tournaments, cards and shared decks populated) and with a signed-in user, asserting that a shared deck belonging to the searcher appears exactly once.
6. **Identity**: key assigned on create, unchanged by an update, UNIQUE index raising on a duplicate, `shared` false by default, `Decks::Duplicator` producing an unshared copy, `to_param` returning the key, and every fixture row carrying one.

Plus system tests **at both viewports**, since the repo requires every system test to pass on each side of the 768px breakpoint: a visitor opens a shared link and sees the decklist; the owner opens the Share modal, flips the toggle, and the URL appears. Known hazard on the mobile half — below the breakpoint the card preview becomes a `<dialog>` whose backdrop swallows subsequent clicks.

## Notes

`allow_browser versions: :modern` now applies to visitors too, so an old browser gets a 406 on a shared link instead of a decklist. Accepted: the alternative is a browser-support policy that differs by session state.
