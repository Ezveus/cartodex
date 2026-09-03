# A tournament becomes a public event, and a participation is its own record — Design

Issue: none — requested directly.

## Goal

`Tournament` is misnamed. It carries `user_id`, `deck_id`, `tournament_profile_id`, `placement` and `championship_points` alongside `name`, `date`, `tier` and `format`: it is one player's participation wearing the name of the event. Two members who attended the same Regional own two unrelated rows that agree on nothing, and deleting a deck deletes the tournament it was played at.

This change splits the record along the line that is already visible in its columns. `tournaments` becomes the event — public, shared between members, one row per real-world tournament — and `tournament_entries` becomes the participation, private to its owner, pointing at both the event and the deck.

## Scope

**In:** the table split and its data migration, `TournamentEntry`, the cardinality rule for a player's entries in one event, the uniqueness rule that keeps one event from being catalogued twice, a public catalog at `/tournaments` with a public event page, the member's own list at `/tournaments/mine`, nested entry routes, two Pundit policies, the split of the form and of the show page into event and participation halves, the navbar's second entry and the nav-section rule that lights exactly one of them, the search group becoming the catalog, the `deck_results` foreign key rename rippling through two controllers, two views and one Stimulus controller, a per-IP rate limit on the catalog, and the CLAUDE.md paragraphs that describe all of it.

**Out:** anything about *other people's* participations. The public event page shows the event and nothing else — no attendee list, no entry count, no deck played by anybody, no leaderboard. Also out: an admin panel CRUD for tournaments (the policy covers moderation through the app's own routes), a merge tool for two catalog entries that describe the same event, any MCP tool for tournaments, an official Play! Pokémon event identifier or location/organizer columns, and per-division attendance on the event.

## Confirmed decisions (from the brainstorming interview)

1. **"Public" means a shared catalog with an event-only public page.** Any member creates or completes an event; the page is reachable without a session, like a shared deck; participations stay private to their owner.
2. **Creation is open, editing belongs to the creator and to admins.** `tournaments.created_by_id` records who catalogued it.
3. **Duplicates are prevented by the UI and by the database.** The catalog's own search is the picker one passes through to record a participation; `(name_normalized, date)` is UNIQUE.
4. **`participant_count` stays on the participation.** Play! Pokémon ranks by age division, so the number a `placement` is measured against is the size of *that* division, not the event's attendance. The event carries no attendance figure at all.
5. **A player may have one entry per tournament per tournament profile.** A member managing several Play! Pokémon profiles (their own and a child's) records one participation each; the same profile twice in one event is refused.
6. **The participation is named `TournamentEntry`.**
7. **Entries are nested under their tournament**; the member's own list is `/tournaments/mine`.
8. **One design document, two implementation stages** — the identity split first, everything still behind Devise; the public opening second. The same shape as `2026-09-02-shared-decks-design.md`.

## Facts established before designing (measured, not assumed)

- **`deck_results.tournament_id` already points at what becomes the participation.** Renaming the table and renaming that column rewrites no data in `deck_results` at all. This is what makes the migration cheap, and it decides the direction of the rename: the old table becomes `tournament_entries` and a *new* `tournaments` is created, rather than the reverse.
- **`StandardPools::AnchorBackfill` needs no change.** It reads `Tournament.where(format: "standard", standard_pool_id: nil)`, `tournament.date` and `tournament.name` — four columns that all stay on the event. That it survives untouched is evidence the split falls where the data already wanted it.
- **`Decks::TournamentPdfExporter`, `Decks::TournamentPdfModal` and `tournament_pdf_controller.js` are unaffected** despite their names: they read a `TournamentProfile`.
- **Exactly five places name `tournament_id` as a parameter or a field**: `DeckResultsController#deck_result_params`, `Api::DeckResultsController#deck_result_params`, `Decks::ResultModal#tournament_group`, `DeckResults::EditView`, and the JSON body built by `result_modal_controller.js`.
- **`test/fixtures/deck_results.yml` references no tournament**, so the fixture rename does not reach it.
- **No MCP tool and no dashboard query touches `Tournament`.** `app/mcp/` holds fourteen tools beside their base class, none of them about tournaments; `HomeController` does not mention one.
- **`Deck.with_standard_pool` preloads the pool *and both of its bounds***, because `StandardPool#name` reads them and preloading the pool alone still costs two queries per distinct pool. The catalog prints a Format column, so `Tournament` needs the same scope — see *Controllers* below.
- **`Ui::NavLinks.section_for` has exactly one exception today** (`decks#shared`), written as a guard clause.
- **`decks#shared` paginates by hand** — `@page`, `@pages`, `offset`/`limit`, a `SHARED_PER_PAGE` constant — and parses `params[:page]` as `params[:page].to_s.to_i` because `?page[]=1` hands over an Array, which `to_i` would not answer. The catalog copies both.
- **`name_normalized` is nullable in `db/schema.rb` but always populated**: `AddNameNormalizedToDeckTournamentArchetype` backfilled it in Ruby, and `NameNormalizable` maintains it in a `before_save`. The new events table can therefore declare it `null: false`.
- **`StandardPool has_many :tournaments, dependent: :restrict_with_error`** — unchanged in meaning; it now restricts on events.
- **The test database is loaded from `db/schema.rb`, so no migration in this repo has ever been executed by CI.** See *Migration* below for the consequence.

## Data model

### `tournaments` — the event

| Column | Notes |
| --- | --- |
| `name` | `null: false` |
| `name_normalized` | `null: false` — the unique index depends on it |
| `date` | `null: false` |
| `tier` | `null: false, default: "regional"` |
| `format` | `null: false, default: "standard"` |
| `other_format_name` | required when `format` is `other` |
| `standard_pool_id` | required when `format` is `standard` |
| `created_by_id` | → `users`, nullable |

`format` and `standard_pool_id` belong to the event: the format a tournament is played under is a fact about the tournament, not about the player. The agreeable corollary is that `Ui::StandardPoolNotice`, the `tournament-standard-pool` Stimulus controller and its `pool_calendar_json` move to the event form unchanged — they compare `standard_pool` against `StandardPool.at(date)`, two columns that stay together.

Indexes: UNIQUE on `(name_normalized, date)`, plus `standard_pool_id` and `created_by_id`.

### `tournament_entries` — the participation

Keeps `user_id`, `deck_id`, `tournament_profile_id`, `participant_count`, `placement`, `championship_points`; gains `tournament_id` (`null: false`); loses the seven event columns above.

Indexes: `user_id`, `deck_id`, `tournament_id`, `tournament_profile_id`, plus the two partial unique indexes below.

### The identity rule

`(name_normalized, date)` is UNIQUE, and that pair *is* the event: "2026 Los Angeles Regional Championships" held on 2026-03-14 is one tournament however many members attended it. The index is the guarantee; a `validates :name_normalized, uniqueness: { scope: :date }` exists for the readable error — the same division of labour as `(set_name, set_number)` on `Card`.

That validation needs one extra line in the model:

```ruby
# NameNormalizable normalizes in a before_save, which is too late for a uniqueness
# validation to see the value it must compare. Running it before_validation as well is
# idempotent, and it is what makes the validation and the UNIQUE index agree byte for byte.
before_validation :normalize_name
```

Matching on the normalized column rather than on `name` is not cosmetic: SQLite's `LIKE` and `lower()` only fold ASCII A–Z, so a uniqueness check on `name` would let "2026 Los Angeles Régional" through in a way the Unicode-downcased column does not.

### The cardinality rule

One entry per `(tournament, tournament_profile)` when a profile is set, one per `(tournament, user)` when it is not. Both halves are needed because **SQLite treats NULLs as distinct** — the lesson `Archetype`'s `(primary_pokemon_id, secondary_pokemon_id)` index paid for, where a NULL secondary let duplicate single-member archetypes through for as long as that index existed. Here the FK cannot become an empty string, so the answer is two partial indexes:

```ruby
add_index :tournament_entries, [ :tournament_id, :tournament_profile_id ],
  unique: true, where: "tournament_profile_id IS NOT NULL",
  name: "index_tournament_entries_on_tournament_and_profile"
add_index :tournament_entries, [ :tournament_id, :user_id ],
  unique: true, where: "tournament_profile_id IS NULL",
  name: "index_tournament_entries_on_tournament_and_user"
```

A profile belongs to exactly one user, so the first index implies the user too. The model mirrors both in **one** custom validation, `one_entry_per_player`, rather than two conditional `validates` calls: it is one rule, and a reader should see all of it at once.

### Cascades — where the split fixes a live bug

| Today | After |
| --- | --- |
| `Deck has_many :tournaments, dependent: :destroy` — deleting a deck destroys the tournament | `Deck has_many :tournament_entries, dependent: :destroy` — it destroys only my participations |
| `User has_many :tournaments, dependent: :destroy` | `has_many :tournament_entries, dependent: :destroy` **and** `has_many :created_tournaments, class_name: "Tournament", foreign_key: :created_by_id, dependent: :nullify` — deleting a member must not remove catalog entries other members point at |
| `TournamentProfile has_many :tournaments, dependent: :nullify` | `has_many :tournament_entries, dependent: :nullify` |
| — | `Tournament has_many :entries, class_name: "TournamentEntry", dependent: :restrict_with_error` |
| `Tournament has_many :deck_results, dependent: :nullify` | `TournamentEntry has_many :deck_results, dependent: :nullify` |

`restrict_with_error` on the event's entries follows `StandardPool#decks` and deliberately departs from `Archetype`'s `:nullify`: another member's participation must not vanish because the creator of the catalog entry decided to delete it. A creator who wants their entry gone deletes their own participation first; if others remain, an admin arbitrates.

### Where the derived numbers live

`CP_REFERENCE`, `TOP_CUT_BANDS`, `TIER_LABELS` and `FORMAT_LABELS` stay on `Tournament` — reference data about the structure of a Play! Pokémon event. The two methods that read them move to `TournamentEntry`: `suggested_championship_points` needs `placement` and its tournament's `tier`, `standard_top_cut` needs `participant_count`. One rule, visible at a glance: the facts with the event, the derivation with the row that holds the figures.

`format_label` and `tier_label` stay on `Tournament`; entry views call `entry.tournament.format_label`. No delegation — an explicit `entry.tournament` says which record answers.

`Tournament` also gains the twin of `Deck`'s preload scope, and for the same reason:

```ruby
# The catalog prints format_label, which for a Standard event names the pool, and
# StandardPool#name reads both of its bounds — so preloading the pool alone still costs two
# queries per distinct pool. Deliberately a twin of Deck.with_standard_pool rather than a
# shared concern: two call sites do not justify one, and a third model would be the moment.
scope :with_standard_pool, -> { includes(standard_pool: [ :first_card_set, :last_card_set ]) }
```

Like `Deck`'s, it gets a flat-cost test — one that goes red if the scope stops preloading, which is the only way this class of regression is ever noticed.

## Migration

One migration, in this order. Every step after the first mutates something; step 1 exists so a data problem is found before any of them has run.

1. **Pre-flight check, before any mutation.** If two rows of `tournaments` share `(user_id, tournament_profile_id, name_normalized, date)`, they would merge into one event and violate the entry uniqueness index. The migration `raise`s, listing the offending ids, having touched nothing — so it is replayable once a human has decided what those rows mean. **It never deletes a row of its own accord.**
2. `rename_table :tournaments, :tournament_entries`
3. `rename_column :deck_results, :tournament_id, :tournament_entry_id` — no data rewritten; the column already pointed at the participation.
4. `create_table :tournaments` with the event columns and `created_by_id`, and the UNIQUE index on `(name_normalized, date)`.
5. `add_reference :tournament_entries, :tournament, foreign_key: true` — nullable at this point.
6. **Backfill**, using `MigrationTournament` / `MigrationTournamentEntry` classes defined inside the migration and isolated from the app's models — the pattern `AddNameNormalizedToDeckTournamentArchetype` already established, for the reason it states: the backfill must keep working whatever those classes grow into. Walking entries by ascending `id`, `find_or_create_by` on `(name_normalized, date)`; the event takes its name, date, tier, format, `other_format_name` and `standard_pool_id` from the oldest participation, and `created_by_id` from that row's `user_id`. Two members who attended the same event converge on one row, and whoever recorded it first is its creator.
7. `change_column_null :tournament_entries, :tournament_id, false`
8. `remove_column` for the seven event columns on `tournament_entries`.
9. The two partial unique indexes from *The cardinality rule*.

`down` is written and genuinely reversible: the seven columns come back, their values are copied from each entry's event, `deck_results.tournament_entry_id` is renamed back, and the new `tournaments` table is dropped and the entries table renamed. Without it a rollback in development leaves a dead database.

**The risk this design cannot cover with a test.** The test database is loaded from `db/schema.rb`, so CI never executes this migration — not the pre-flight, not the backfill, not the `down`. The repository already accepts that risk for every migration, but no previous migration had to rewrite production rows. The implementation plan therefore carries an explicit manual step before deploy: take a copy of the production database, run the migration against it locally, check the counts (one entry per original row; as many events as distinct `(name_normalized, date)` pairs; no orphaned `deck_results.tournament_entry_id`), then run `down` and `up` again.

## Authorization

Two policies, both created in stage 1 so that stage 2 is a small diff. Every action calls `authorize` from stage 1 onwards, before the concern that makes it mandatory is even included.

Written in the endless-method style `DeckPolicy` already uses:

```ruby
class TournamentPolicy < ApplicationPolicy
  # The catalog and an event's page are public. Written down rather than left true by
  # omission, so that verify_authorized has no blind spot over this controller.
  def index? = true
  def show? = true

  def mine? = user.present?
  def create? = user.present?

  def update? = creator_or_admin?
  def edit? = creator_or_admin?
  def destroy? = creator_or_admin?

  private

  def creator_or_admin? = user.present? && (record.created_by_id == user.id || user.admin?)
end
```

`new?` needs no line — `ApplicationPolicy` already defines it as `create?`.

`TournamentEntryPolicy` answers `owner?` to everything, defined as `DeckPolicy` defines it (`user.present? && record.user_id == user.id`, a visitor owning nothing), and has no public read at all.

`index?`/`show?` returning an unconditional `true` is the same construct as `CardPolicy` and `DashboardPolicy`: not ceremony, but the written trace of "this is public", and what stops `verify_authorized` from having a blind spot over the controller.

### The one place this departs from a documented invariant

CLAUDE.md currently says: *"No query anywhere checks `user.admin?` — an admin who wants to read a private deck goes through `Admin::DecksController`'s own gate."* `TournamentPolicy#creator_or_admin?` will read `user&.admin?`.

That invariant protects the deck-sharing confidentiality boundary: a policy shortcut there would quietly widen what a visitor-facing rule allows. Nothing here is hidden. An admin correcting a catalog entry gains no read they did not already have, and the alternative — an `Admin::TournamentsController` duplicating three actions to express the same permission — is more code for the same effect. The policy carries a comment saying exactly this, and the CLAUDE.md paragraph is reworded to state what it protects rather than "nowhere".

### 404 versus 403 — the opposite answer from decks

A deck answers 404 for both "unknown" and "not yours", because a 403 would turn a scan of random keys into an existence oracle for private decks. A tournament's existence is public — it is *listed* on `/tournaments`. So an unauthorized `edit` gets a redirect to the public page with an alert, not a 404, which would lie without protecting anything:

```ruby
# Declared here on purpose. PubliclyReachable routes both RecordNotFound and
# NotAuthorizedError onto the static 404 so that a private deck and an unknown key are
# indistinguishable; rescue_from handlers are consulted in reverse order of declaration,
# so this one wins for NotAuthorizedError alone. RecordNotFound keeps the concern's 404.
rescue_from Pundit::NotAuthorizedError, with: :redirect_to_tournament
```

## Routing

Final state. In stage 1 the whole block stays inside `authenticate :user`; in stage 2 it moves out, next to `resources :decks` and `resources :cards`.

```ruby
resources :tournaments do
  get :mine, on: :collection
  resources :entries, only: %i[new create show edit update destroy],
            controller: "tournaments/entries" do
    member do
      post   :attach_results   # deck_result_ids[]
      delete :detach_result    # deck_result_id
    end
  end
end
```

`get :mine, on: :collection` is emitted before the member routes, so `/tournaments/mine` is not swallowed by `/tournaments/:id`.

`attach_results` and `detach_result` are member actions on the entry rather than a third level of nesting (`/tournaments/:tid/entries/:eid/deck_results/attach`, and the `attach_tournament_entry_deck_results_path` that comes with it). One controller instead of two, two URL segments instead of three, at the cost of two non-resourceful actions on `Tournaments::EntriesController`. They are the entry's own composition of its matches, which is the same object the controller already owns.

## Controllers

### `TournamentsController`

Takes the shape `DecksController` already has: a public half and a member half in one controller.

- `index` — the catalog. `name_matching` on the query, `order(date: :desc)`, `with_standard_pool` (the Format column names the pool), hand-rolled pagination (`CATALOG_PER_PAGE = 24`, `@page`, `@pages`, `offset`/`limit`), and a filter form targeting a Turbo Frame so a keystroke pays the pager's `COUNT` and one page of rows rather than the whole surrounding page. `params[:page].to_s.to_i` for the reason `decks#shared` documents: on an action that rescues only `RecordNotFound` and `NotAuthorizedError`, `?page[]=1` would otherwise be an unhandled 500 for any bot that tries the shape. When a member is signed in, one `pluck` over the page's ids marks the rows they attended; the query is not issued at all for a visitor.
- `show` — the public event page. Also loads `@my_entry = current_user&.tournament_entries&.find_by(tournament: @tournament)`, which decides between "View your entry" and "Record your participation".
- `new` / `create` — members. On success, redirect to `new_tournament_entry_path(@tournament)`: cataloguing an event is almost always wanting to record one's participation in it, and chaining the two forms avoids one form writing two models. On a uniqueness failure the form re-renders with a message that **names the existing event and links to it** — the controller looks it up on `(name_normalized, date)`. Without the link the user knows they are blocked but not where to go, which is half the anti-duplicate mechanism missing.
- `edit` / `update` / `destroy` — creator or admin. `destroy` reports `restrict_with_error` as a flash naming how many participations remain, rather than a 500.
- `mine` — `current_user.tournament_entries.joins(:tournament).includes(:deck, :tournament_profile, :tournament).order("tournaments.date DESC")`. No `with_standard_pool` here: this list has no Format column, and preloading two card sets per row for something nothing prints is the mistake the scope exists to fix, not to spread.

`show` and the entry pages render `Tournaments::EventDetails`, which prints `format_label` — so both load their tournament through `with_standard_pool`. One record, but three queries instead of one otherwise.

### `Tournaments::EntriesController`

**Every entry lookup is scoped by association** — `current_user.tournament_entries.find(…)`, never `TournamentEntry.find`. The *tournament* named in the URL is looked up unscoped (`Tournament.find(params[:tournament_id])`), which is not the same risk and not the exception CLAUDE.md's "Where the unscoped lookup lives" paragraph is about: an event is public, so there is nothing for a scope to protect. `show` carries the rich page and loads `@unassigned_results = @entry.deck.deck_results.where(tournament_entry_id: nil).order(played_at: :desc)`.

`attach_results` and `detach_result` are today's `Tournaments::DeckResultsController#attach`/`#detach` with the foreign key renamed:

```ruby
@entry.deck.deck_results.where(id: ids, tournament_entry_id: nil)
     .update_all(tournament_entry_id: @entry.id)
```

### Stage 2 additions

`include PubliclyReachable` and `publicly_reachable :index, :show`; the `rescue_from` above; and one rate limit:

```ruby
CATALOG_RATE_LIMIT_TO = 60
rate_limit to: CATALOG_RATE_LIMIT_TO, within: 1.minute,
  name: "tournaments-index", unless: -> { user_signed_in? },
  store: RateLimitStore, only: :index
```

60/min because the catalog has exactly the shape and cost `decks#shared` was measured at — a debounced field driving a paginated listing behind a Turbo Frame. `show` gets none: one page load per click, no live control behind it, the same reasoning that leaves `decks#show` unlimited.

## Views and navigation

The current 147-line, ten-field form splits along the same line as the model.

- **`Tournaments::Form`** keeps `name`, `date`, `tier`, `format`, `standard_pool_id` with `Ui::StandardPoolNotice`, and `other_format_name` — and therefore the whole `tournament-standard-pool` controller and `pool_calendar_json`, unchanged.
- **`Tournaments::Entries::Form`** takes `deck_id`, `tournament_profile_id`, `participant_count` with its top-cut hint, `placement`, and `championship_points` with its CP hint (which now reads `tier` through `entry.tournament`). It shows the event's name and date read-only at the top: one is filling in a placement, and needs to see in what.

| Page | Component | Content |
| --- | --- | --- |
| `/tournaments` | `Tournaments::IndexView` (reworked) | Catalog: search field targeting a Turbo Frame, columns Name / Date / Tier / Format, pager, and an "attended" marker per row for a signed-in member. No Deck / Placement / CP columns — those are personal. |
| `/tournaments/:id` | `Tournaments::ShowView` (reworked) | The thin public page: name, `Tournaments::EventDetails`, and the call to action chosen by `@my_entry`. Nothing about any other member. |
| `/tournaments/mine` | `Tournaments::MineView` (new) | What today's index shows — Tournament / Date / Tier / Deck / Placement / CP / Actions — with the name linking to the participation. |
| `/tournaments/:tid/entries/:id` | `Tournaments::Entries::ShowView` (new) | The rich page: `Tournaments::EventDetails` read-only, my figures, my matches, and the form that attaches the deck's unassigned results. |

`Tournaments::EventDetails` is extracted rather than copied between the public page and the participation, for the reason `Ui::CardPreview` was: two views showing the same facts, one place describing them.

The two views that list a deck's tournaments in a `<select>` — `Decks::ResultModal#tournament_group` and `DeckResults::EditView` — switch from `@deck.tournaments` to `@deck.tournament_entries` preloaded with their tournament, keeping the `"name (date)"` option label built in the view with `localize`, where `localize` belongs. The field label stays "Tournament": the user really is choosing a tournament; only the foreign key names their participation in it. The shared shape is one line, not a component.

Mechanically following from that: the JSON key `tournament_id` becomes `tournament_entry_id` in `result_modal_controller.js` (and its target is renamed `tournamentEntrySelect`, or the name would lie), and `:tournament_id` becomes `:tournament_entry_id` in the `permit` lists of `DeckResultsController` and `Api::DeckResultsController`.

### Navigation

`Ui::AppNavbar` gains a second entry: "Tournaments" (`tournaments_path`, section `tournaments`) and "My tournaments" (`mine_tournaments_path`, section `my_tournaments`). `Ui::PublicNavbar` gains "Tournaments" in stage 2 — one section only, since a visitor cannot reach `mine`.

`Ui::NavLinks.section_for` has one exception today, written as a guard clause. With a second, it becomes a table:

```ruby
SECTION_OVERRIDES = {
  [ "decks", "shared" ]     => "shared_decks",
  [ "tournaments", "mine" ] => "my_tournaments"
}.freeze
```

The comment moves from "the controller name for every route but one" to the general rule: the controller name, except where one controller serves two lists. `test/controllers/navbar_active_section_test.rb` gains its rows for the new pages, with the count assertion it already makes per page and per navbar — a rule that lights two entries and a rule that lights none fail it differently.

## Search

`Search::Global#tournament_scope` loses its per-user branch: the "TOURNAMENTS" group becomes the catalog, `Tournament.name_matching(@query)`, identical for a member and a visitor. `Search::ResultsList` needs no change — it already points at `tournament_path` and prints `date · tier_label` — and "See all" lands on `/tournaments`, now public.

The accepted cost: a member searching "Los Angeles" reaches the public page and clicks once more to get to their participation. The alternative would be a fifth result group for one's own entries, beside the catalog, mirroring DECKS / SHARED DECKS — but it would print exactly the same names as the group next to it, since a participation has no name of its own. Not built.

## Documentation

CLAUDE.md is updated in the same commit as the code it describes, in four places: the **Models** paragraph (the event/participation split, the cascades, the identity rule and the two partial indexes), the policies paragraph (the `admin?` departure and why it is not the deck rule), the **PubliclyReachable** paragraph (`tournaments#index` and `#show` joining the public surface, with the local `rescue_from` that redirects instead of serving the 404), and **`RateLimitStore`** (a sixth `rate_limit`, and why 60).

## Testing plan

**Fixtures.** `test/fixtures/tournaments.yml` splits into `tournaments.yml` (events, with `name_normalized` spelled out by hand — fixtures are inserted without callbacks) and `tournament_entries.yml`. A case the current fixtures do not have is added: **two users on the same event**, without which nothing exercises what the split makes possible.

**Models.** `tournament_test.rb` keeps the event's validations, `format_label`, `clear_inapplicable_classification`, the `(name_normalized, date)` uniqueness — including a case-and-accent pair, since that is the column's whole reason for existing — and the `restrict_with_error`. A new `tournament_entry_test.rb` covers the numericality validations, `placement_within_participant_count`, deck and profile ownership, `suggested_championship_points`, `standard_top_cut`, and `one_entry_per_player` **in both branches**, with a profile and without: the profile-less branch is precisely the one a single index could not have enforced.

**Controllers.** `tournaments_controller_test.rb` rewritten (catalog and search, pagination, the call to action driven by `@my_entry`, the creation collision naming the existing event, `edit`/`update` as creator / as another member / as admin, `destroy` blocked by a participation, `mine`). A new `tournaments/entries_controller_test.rb` absorbs today's attach/detach test and adds the entry CRUD. Two policy tests. `public_access_test.rb` gains `tournaments#index` and `#show` in stage 2 — per action, as that file requires, since the bug it guards against is an over-broad `skip_before_action`.

**System tests.** There is no system test for tournaments today. Two are added, both expected to pass on each side of the 768px breakpoint and navigating with `click_nav_link`: in stage 1, the nominal path "search the catalog → it is not there → create it → record my participation"; in stage 2, `public_navigation_test.rb` gains a visitor reaching the catalog and an event page and seeing no member affordance.

**Sabotage check.** For the new tests that carry a real rule — both branches of `one_entry_per_player`, editing by a non-creator, the visitor's public reach — the implementation plan requires breaking the implementation to confirm the test actually goes red. Plan-prescribed test code in this repository has been vacuous before.

## Staging

**Stage 1 — the identity split.** Migration, models, policies (with `authorize` called everywhere), routes and controllers, the view split, the `deck_results` foreign key rename and its five call sites, search, navbar and nav sections, fixtures and tests. Everything stays inside `authenticate :user`: the catalog is shared between members, not yet open to visitors. Observable behaviour barely moves, which is what makes this stage testable on its own.

**Stage 2 — the public opening.** `PubliclyReachable`, the local `rescue_from`, the rate limit, `Ui::PublicNavbar`, `public_access_test.rb` and the visitor system test. No schema change. If stage 1 goes wrong, no half-finished public surface has been exposed.

## Notes

- No merge tool for two catalog entries describing the same event. The unique index makes the common case impossible and a spelling variant remains correctable by editing one of the two; a real merge (repointing participations, choosing surviving values) is a project of its own.
- The public event page shows no attendance figure, by decision 4: the event carries none, and the only attendance the database holds is the size of one player's own division.
- Nothing here is indexable. `XRobotsTagMiddleware` already stamps `x-robots-tag: noindex, nofollow` on every response the app emits, the new pages included.
