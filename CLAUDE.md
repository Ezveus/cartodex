# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cartodex is a Pokémon Trading Card Game card manager built with Rails 8.1 and Ruby 3.4.1. Features include collection tracking (with webcam scanning), deck management with archetype tagging and per-result win/loss tracking, tournament profiles (Play! Pokémon divisions), and decklist import plus multiple export formats (JSON, PTCG text, Cardmarket wishlist, tournament PDF, image). Card data is scraped from Limitless TCG. An admin panel provides dashboard, CRUD for card sets/cards/users/decks/archetypes/imports, and bulk import/rescrape actions.

## Common Commands

```bash
bin/setup                                    # Initial project setup
bin/dev                                      # Start development server
bin/rails test                               # Run unit tests
bin/rails test:system                        # Run system tests (desktop side of the breakpoint)
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system  # …and the mobile side; both must pass
bin/rails test test/models/card_test.rb      # Run a single test file
bin/rails test test/models/card_test.rb:10   # Run a specific test by line
bin/rubocop                                  # Lint (rubocop-rails-omakase style)
bin/brakeman --no-pager                      # Security scan
bin/importmap audit                          # JS dependency audit
```

CI runs five checks (`bin/brakeman`, `bin/importmap audit`, `bin/rubocop -f github`, `bin/rails db:test:prepare test test:system`, and the same system tests again below the 768px breakpoint — see Test Setup) on every push and PR. Production deploy via Kamal is **manual**: trigger the workflow with `workflow_dispatch` (Actions → CI → Run workflow, or `gh workflow run ci.yml`), which re-runs the checks and deploys only if they pass. Kamal config lives in `config/deploy.yml` and `.kamal/`; `bin/kamal` is the deploy CLI. `bin/jobs` runs the Solid Queue worker locally. **The database is made ready before the server accepts traffic, and all of it is automatic.** `bin/docker-entrypoint` runs `db:prepare`, then `db:seed`, then `standard_pools:backfill_anchors` — in the new image, before boot. That order is not cosmetic: the migration adds `standard_pool_id` and the validation making it mandatory on a Standard record, so between the two an empty `standard_pools` table leaves `StandardPool.current` nil, and creating a Standard deck 422s while decklist import raises for every user. A post-deploy hook would have left the app serving in exactly that state, and `.kamal/hooks/pre-deploy` cannot help either — it runs `kamal app exec --reuse`, which execs into the *old* container and so cannot see a new migration at all. Both extra steps are safe on every boot: the seeds fill missing values and never overwrite (the `||=` guard, same as `CardSets::Importer` — `db/seeds/card_sets.rb` used to `update!` unconditionally, which reverted admin edits and is what kept seeding off the deploy path), and the backfill is scoped to rows with no anchor. The backfill exits non-zero when it could write nothing, failing the boot on purpose.

## Architecture

### Deep dives

Seven features have their rationale written out under `docs/architecture/`, one file each. What
remains inline below is the structural map plus the rules that bite from outside their own
feature; the files carry the measurements behind every decision. Read the relevant one **before**
changing the code it covers — each records what was already tried and why it was rejected.

| File | Covers |
|---|---|
| `tournaments-and-standings.md` | `Tournament` / `TournamentEntry` / `TournamentStanding`, the wiki-governed sheet, claim links, field sizes, ownerless field-list decks, sheet pagination |
| `limitless-imports.md` | Bulk standings import from Limitless TCG — the paper results pages and the online best finishes, de-duplication, undo |
| `archetype-metagame.md` | `/archetypes` and `/archetypes/:id` — sample scoping, the card report, the performance panel, the query budget, the public surface and the slug address |
| `card-labels-and-roles.md` | `CardLabel` / `CardLabelAssignment`, the ACE SPEC and role families, `RoleSuggester`, `/admin/card_roles`, the `/cards` label filter |
| `public-surface.md` | `PubliclyReachable`, the policies, the public views, the Share control, `XRobotsTagMiddleware`, the rate limits |
| `mcp-and-oauth.md` | `POST /mcp`, the tool classes, Doorkeeper OAuth 2.1, client registration, consent, connected apps |
| `frontend.md` | The design token system, `/styleguide`, the global search spotlight, the navbars, the shared pickers |

**Database**: SQLite3 in every environment. Multi-database setup: `primary` plus `queue` (Solid Queue), `cable` (Solid Cable, dev/prod), and `cache` (Solid Cache, prod). Schema in `db/schema.rb`; secondary schemas in `db/queue_schema.rb`, `db/cable_schema.rb`, `db/cache_schema.rb`.

**Service pattern**: Business logic lives in `app/services/`. Services inherit from `ApplicationService` which provides a `.call(...)` class method that delegates to `new(...).call`, plus a `serialized_transaction` helper (SQLite `BEGIN IMMEDIATE` when no transaction is open, else a savepoint) used by the allocation services to serialize read-then-write under concurrent MCP calls. Custom error classes (`ParseError`, `FetchError`) for error handling.

Key services:
- `Cards::Fetcher` — scrapes card data from limitlesstcg.com using Nokogiri, creates/updates Card records with associated Attacks, Abilities, and PokemonSubtypes. **A printing already in the database is never re-scraped** (issue #121): card text is immutable once printed, so presence — not freshness — is the guard, and an import of known cards costs zero HTTP requests. The one thing the skip path still does is re-attempt the `card_set` link (via `update_column`, so `compute_fingerprint` does not run and the card cannot drift out of its printing group), because a card imported before its set existed would otherwise stay orphaned forever. `force: true` is the only refresh, and therefore the **only** thing that updates `price_eur`/`price_usd`/`cardmarket_url`; it is reachable from the admin panel alone (`Admin::CardsController#rescrape`, `CardSets::RescrapeJob`).
- `CardSets::Importer` — scrapes card set data from Limitless TCG, used by `CardSets::ImportJob`. Since #121 it re-links known cards to the set but no longer refreshes their text, so it is an import, not a repair tool; `CardSets::RescrapeJob` is the repair tool. It writes `release_date` too, guarded by `||=` so a hand-seeded date (`db/seeds/card_sets.rb`) survives a re-scrape rather than being overwritten.
- `Decks::Fetcher` — parses decklist text format (`QUANTITY NAME SET NUMBER`), creates Deck with DeckCards in a transaction, coordinates Cards::Fetcher for each card, and auto-tags the deck with a matching existing archetype via `Decks::ArchetypeDetector`. Lines naming the same printing are merged into one `DeckCard` with the summed quantity — `(deck_id, card_id)` is UNIQUE, so they would otherwise raise — but only when they agree on the card name: a set code and number repeating under two different names is a typo, and merging it silently would import a deck nobody wrote. It accepts a `nil` user and four optional keywords — `shared:`, `format:`, `standard_pool:`, `other_format_name:` — whose defaults preserve its two pre-existing positional-only call sites exactly; `Tournaments::StandingListImportJob` is what actually needs them, to build an ownerless, shared field-list deck anchored to the event's own pool rather than to a user or to `StandardPool.current`. `other_format_name:` travels with `format:` and is not optional beside it: `Deck` requires it whenever the format is `other`, and `other` is a format the event form really offers, so passing one without the other made `Deck.create!` raise for every field list at such an event.
- `Decks::ArchetypeDetector` — two jobs behind one name, deliberately separated. *Matching* asks whether an existing `Archetype`'s member cards are all in the deck: its members were chosen by a human, so containment is safe to ask of the **whole** card pool of **any** type, and it is keyed on `Card#fingerprint` (the "same card, any printing" key) rather than on name, which conflated unrelated cards sharing one. A weighted score — rule-box Pokémon 3, other Pokémon 2, Trainer/Energy 1, summed, ties broken by member count — keeps an ill-advised "Iono" archetype from winning unless nothing else matches; a secondary absent from the deck disqualifies outright. A card with no `fingerprint` can never match — `compute_fingerprint` is a `before_save`, so only a write that bypasses callbacks (`update_column`, `insert_all`, a fixture) can produce one, and such a card is invisible to matching rather than falling back to its name. *Suggestion* is unchanged and stays **Pokémon-only**: ranking Trainers by copies played would propose Ultra Ball on every deck ever imported, so a Trainer-led archetype is created by hand and matching finds it afterwards. The `Result` names this split: `archetype` describes the match, `suggested_primary`/`suggested_secondary` only the notable Pokémon.
- `Archetypes::FingerprintSync` — recomputes `archetypes.primary_fingerprint`/`secondary_fingerprint` from the cards they point at and **reports** the pairs that would collide rather than writing one of them (`bin/rails archetypes:resync_fingerprints`). It reports rather than writes in the other unwritable case too: a member card with no fingerprint, since `primary_fingerprint` is `NOT NULL` and writing through would abort the run part-way instead of naming anything. It is a repair tool, not a callback: a `force: true` rescrape moves a card's fingerprint, and a `Card` callback would have to fail a whole set rescrape halfway through to keep the index honest.
- `Decks::Exporter` / `Decks::CardmarketExporter` / `Decks::TournamentPdfExporter` — deck export in JSON, Cardmarket wishlist, and tournament PDF formats (PTCG text export lives in `bin/export_deck_ptcg`)
- `Decks::Duplicator` — duplicates a deck with all its DeckCards
- `HttpFetcher` — Net::HTTP wrapper used by other services
- **Collection↔deck allocation** (real copies vs proxies): `Allocations::Availability` computes owned/committed/available per exact printing (use `.for_cards` to render a whole page — `.call` is the one-card case of it); `Allocations::OverAllocations` lists over-committed cards; `Allocations::PhysicalDecksByCard` answers "which physical decks hold these cards" in one grouped query, for both the report and its reallocation targets. `Collections::CardAdder`/`QuantitySetter`/`OwnedEquivalents` and `Decks::CardAdder` (greedy real-backing on physical decks, via `Allocations::Backing`)/`OwnedCopiesSetter`/`OwnedCopiesReallocator` (pure conversion between decks)/`DeckCardQuantitySetter` are the write operations, each wrapped in `serialized_transaction`. See the design spec at `docs/superpowers/specs/2026-07-02-collection-deck-allocation-design.md`.
- **Printing swap** (issue #99): `Cards::Printings` lists every printing sharing a card's `fingerprint` — unlike `Collections::OwnedEquivalents` it does **not** filter to what the user owns, since switching to a printing you do not own is a legitimate move; owned/available are annotations, and given a deck each entry also carries `in_deck` plus the `real_after`/`proxies_after` a swap would produce (nil when there is nothing to project). `Cards::Printings.swappable_card_ids` answers "which of these cards have another printing" in one grouped query, so the deck page decides in bulk which rows get a picker. `Decks::PrintingSwapper` is the write: it merges when the target printing already has a row (`(deck_id, card_id)` is UNIQUE and a mixed set is normal), and re-derives the backing against the target's availability. It returns a `Result` struct (`deck_card`, `merged`) rather than the row alone: whether the two rows merged is decided **inside** the transaction, because afterwards nothing left in the database tells them apart. Nothing is ever scraped: a printing the database does not hold is simply not on the list.
- **The backing rule** lives in one place, `Allocations::Backing.greedy(quantity:, current_owned:, available:)`: claim as many reals as the collection leaves free to this deck, capped at the row's total, never below what the deck already backs. Three callers apply it — `Decks::CardAdder` on an add, `Decks::PrintingSwapper` on a swap, and `Cards::Printings` when it *projects* that swap for the picker — and a projection that disagreed with the write would warn the user about the wrong thing. `available` must always come from `Availability`'s `excluding_deck:`, or a deck competes with itself.

**Jobs** (`app/jobs/`):
- `CardSets::ImportJob` — wraps `CardSets::Importer`
- `Decks::ImportJob` — wraps `Decks::Fetcher`, broadcasts progress via Turbo Streams, persists state via the `Import` model
- `Tournaments::StandingListImportJob` — wraps `Decks::Fetcher` for a field-list decklist typed into a standings row, attaches the resulting ownerless deck to the `TournamentStanding`, and broadcasts to the **contributor's** own `:notifications` stream rather than into `Decks::ImportJob`'s deck-grid targets

**Models**: User has_many Decks, Collections, Imports, and TournamentProfiles. Deck belongs_to an optional User (`decks.user_id` is nullable — an ownerless deck is a tournament field list, see below) and an optional Archetype (its own archetype), has_many Cards through DeckCards and has_many DeckResults (win/loss tracking with optional Archetype tagging for the opposing deck). Archetype has primary/secondary cards (Card refs), parent/children hierarchy, has_many DeckResults, and has_many TournamentStandings. Import persists background import status (progress, errors) for reload-safe tracking and retry, and belongs_to an optional Tournament (set by field-list imports alone, so an event page lists only the imports in flight *there*). TournamentProfile belongs_to User (Play! Pokémon division metadata) and has_many TournamentEntries. Tournament belongs_to an optional creator, has_many TournamentEntries, and has_many TournamentStandings (an event's public sheet); TournamentEntry belongs_to User, Tournament, Deck, and an optional TournamentProfile, and has_one TournamentStanding (the public row it claims). TournamentStanding belongs_to Tournament, Archetype, an optional Deck (an ownerless field list) and an optional TournamentEntry (the claim link), plus an optional `created_by` User. CardSet has_many Cards (code/name uniqueness, release_date, `by_release` scope). `Deck.with_standard_pool` preloads the pool **and both of its bounds**, because `StandardPool#name` reads them and preloading the pool alone still costs two queries per distinct pool; it replaced the same `includes` spelled out at six call sites in four files (both deck indexes, the dashboard showcase, the spotlight's two deck groups, `ListDecksTool`), four of which re-explained the reason. Four flat-cost tests now go red if it stops preloading — two existed, two were added for the showcase and the MCP tool, which had none. Card belongs_to CardSet (optional), has_many Attacks, Abilities, and optional PokemonSubtype. Card validations are conditional on `card_type` (Pokémon vs Trainer vs Energy). **`(set_name, set_number)` is UNIQUE** — that pair identifies a printing and is what `Cards::Fetcher` looks a card up by, so a duplicate would make the lookup arbitrary and, since a known printing is never re-scraped, permanently so; the model validation exists for the readable error, the index is the guarantee. (When Japanese sets land — issue #111 — set codes stop being globally unique and this key has to grow a region or a `card_set_id`.) Card uses a `compute_fingerprint` callback for deduplication (also the equivalence key for suggesting interchangeable printings).

**Tournaments, entries and standings** are written out in **`docs/architecture/tournaments-and-standings.md`** — the wiki governance of an event's public sheet, the claim link, the three per-division field sizes, ownerless field-list decks, the field-list import job and the sheet's pagination. Read it before touching `Tournament`, `TournamentEntry`, `TournamentStanding`, or anything routed under `tournaments`. Four of its rules stay here, because each of them bites from outside the feature — through `User#destroy`, through a deck delete, through a page that never mentions tournaments:

**`Tournament` is the shared public event; `TournamentEntry` is one member's private participation in it.** Any member may catalogue an event, and every other member's entry hangs off the same row — what a given player did there belongs on the entry, not the event. `(name_normalized, date)` is UNIQUE and *is* the event's identity — the same division of labour as `(set_name, set_number)` on `Card`: the model validation exists for the readable error, the index for the guarantee. `normalize_name` runs `before_validation` here, in addition to `NameNormalizable`'s own `before_save`, because the uniqueness check has to see the normalized value before the record is validated, not only once it is saved. It **squishes** as well as downcasing, and so does the query side (`normalize_for_match`) — fold only what is stored and a name typed with a double space becomes unfindable: a name arrives copy-pasted, with a trailing space or a double space where a line wrapped, far more often than it arrives typed, and without the squish one real event gets two catalog rows that render identically and both answer the same search. The split migration's `merge_key_name` mirrors the same rule, since rows written before it carry an unsquished `name_normalized`. `participant_count` stays on `TournamentEntry`, not `Tournament`, because Play! Pokémon ranks a placement against the size of *that player's age division*, not the event's attendance — two entries at the same event legitimately carry two different counts. Entry uniqueness is two partial indexes, `(tournament_id, tournament_profile_id)` where a profile is attached and `(tournament_id, user_id)` where it is not, because SQLite treats NULLs as distinct — the same trap `Archetype`'s old `(primary_pokemon_id, secondary_pokemon_id)` index fell into (see **Archetype identity** below): a single index on `(tournament_id, tournament_profile_id)` alone would never see two profile-less entries from the same player collide. **Both ends of a participation refuse to be deleted out from under it.** `Tournament has_many :entries` and `Deck has_many :tournament_entries` are `dependent: :restrict_with_error`, as is `TournamentProfile`'s — unlike `User`'s `:destroy` or `created_tournaments`' `:nullify`. On the event that stops another member's participation vanishing because the catalog entry's creator deleted it; on the deck it stops the *player's own* record of a placement, CP and profile vanishing behind a confirmation that only ever mentioned cards and results, and it is the one cascade that used to leave the event standing while the attendance disappeared. `TournamentsController#destroy` and `DecksController#destroy` therefore both branch on `destroy`'s return value and name the count in the alert — `restrict_with_error`'s own message names the association, not what is in the way. **`User has_many :tournament_entries, dependent: :destroy` is declared ahead of `:decks` and `:tournament_profiles`, and the order is load-bearing**: dependent callbacks run in declaration order, so "Cancel my account" only works because the entries go first — `UserTest` covers exactly that, and moving the line back below either association turns it red. The other half of the same rule lives on the entry: `TournamentEntry` refuses to change `deck_id` while `deck_results` are attached to it, because `DeckResult#entry_belongs_to_same_deck` is only checked when the *result* is saved and nothing re-checks it when the entry moves underneath — the update would otherwise succeed and leave every attached match invalid. Refusing rather than detaching keeps the decision with the user, the same call the two `restrict_with_error`s make.

**Entry uniqueness is per Play! Pokémon profile, not per user**, and every reader of it has to be plural. A parent tracking their own and their child's profiles legitimately has two participations in one event, so `TournamentsController#show` loads `@my_entries` — a singular `find_by` picked one of them arbitrarily and left the other unreachable from the only page that links to it — and the event page renders one button per entry, labelled with the player name once there is more than one to tell apart. It keeps offering "Record another participation" while the reader still owns a profile this event holds no entry for; that test is deliberately *narrower* than `one_entry_per_player` and deliberately not a restatement of it, so a reader it says no to loses a button rather than meeting a form that then refuses them. **A visitor gets none of it.** `can_record` — `policy(Tournament).create?`, passed by the ERB — guards `entry_action` as a whole rather than its `empty?` branch, because a visitor's `my_entries` is `[]` by construction and the empty case *is* the "Record your participation" button: a primary-styled link to the sign-in page, which is the navbar's job to offer and not this page's. `create?` and not `mine?` on purpose, even though both answer `user.present?` today and therefore no test can tell them apart — the question here is "may this reader record a participation", and reading it as "may they see their own list" is what would make the button vanish from every event page, silently, the day one of the two grows a condition. One **deck** can likewise carry two participations in one event, which is why `TournamentEntry#picker_label` — the label both tournament pickers print, kept on the model for the reason `Card#printing_label` is — names the profile: `"Name (date)"` alone prints the two options identically. Both pickers read the *loaded* association rather than building a fresh relation over it (`Decks::ResultModal`, `DeckResults::EditView`), because `picker_label` reads the event **and** the profile and both controllers preload the pair; a relation rebuilt with its own `includes` ignores the preload and N+1s on the profile, which a plain query count cannot see — the entry `SELECT` it repeats is served by the query cache. Flat-cost tests in `DecksControllerTest` and `DeckResultsControllerTest` are what actually hold that down.

**The claim link is the one thing on a standing that is not wiki-writable, and
`standing_params` must never permit `tournament_entry_id`.** Without that omission the ordinary
edit form would let any member attach their own participation to a row naming somebody else, or
detach yours. It is written only by `#claim`/`#unclaim`, from an id resolved through
`current_user.tournament_entries.find_by!(id:, tournament_id:)` — so a stranger's entry is a
`RecordNotFound`, never a policy question, which is why the *model* checks only that the
participation happened at this event and not who owns it. `TournamentStandingPolicy#unclaim?` is
the single owner-scoped rule in the file: anybody may correct the public data, only the claimant
may sever the link. **Neither of those two writes may assume the rest of the row is still valid.**
A standing goes invalid *after* it is written whenever the event's per-division field size is
lowered below a placement already recorded — `placement_within_division_field` reads the event, and
the event's creator may edit it — and `update!` re-runs every validation, not only the attribute
being changed. `#unclaim` therefore writes `update_column(:tournament_entry_id, nil)`, for the
reason `DecksController#share` writes its flag that way: severing a link has no business asking
whether the *rest* of the record validates, nothing this write could break can be broken by it
(both validations that read `tournament_entry` return early on nil), and `update!` there answered
the member's "Unlink" click with an unrescued `RecordInvalid` — a 500. `#claim` does need its
validations (that is where the link rules live), so it branches on `save` and builds its alert
from `errors.full_messages`, not from `errors[:tournament_entry]`: the key is empty for a
placement failure, and reading it alone redirected the member with a blank alert and no reason. A partial UNIQUE index on `tournament_entry_id WHERE … IS NOT NULL` is what
actually stops a member publishing themselves twice under two spellings of their own name, which
the player-name key cannot see — and it is partial because SQLite treats NULLs as distinct, the
trap `Archetype`'s old index fell into. Values on a standing are **copied** from a participation,
never derived from it: editing the private record must not silently republish, and the row being
wiki-editable is what makes correcting it an ordinary edit rather than a resync mechanism.
`Tournaments::StandingsController` is a third deliberate `PubliclyReachable` exception beside
`Tournaments::EntriesController` and `DeckResultsController`: its routes ride out of
`authenticate :user` by nesting under `tournaments` alone, it keeps `authenticate_user!` as its
only gate, every action calls `authorize`, and nothing enforces that it must — hence a case per
action in `test/controllers/public_access_test.rb`. It also carries its own
`rescue_from Pundit::NotAuthorizedError, with: :refuse_with_redirect`, the same call
`TournamentsController` makes, because nothing outside `PubliclyReachable` rescues that exception
and every other refusal in this controller is already a `RecordNotFound` from a scoped lookup —
`#unclaim` is the app's first action that can genuinely refuse a signed-in member, and unrescued
that is a 500.

**A `Deck` may belong to no member, and that made three latent reads into bugs.** `decks.user_id`
is nullable, and an ownerless deck is a tournament field list:
`Deck#ownerless_deck_is_shared_and_virtual` requires it to be `shared` (`/decks/shared` is the
only listing that can show it — it is *not* in anybody's `/decks`) and forbids it being `physical`
(`physical` is what makes a deck consume a collection, and there is no collection to consume),
which is what makes every allocation service unreachable for it **by construction** rather than by
convention: they all read `deck.user` and all sit behind `DeckPolicy#owner?`, which a nil
`user_id` can never satisfy. `TournamentEntry#deck_belongs_to_user` already refuses a field list
as a participation deck, for free. Two reads were live bugs the moment the column went nullable
and are fixed: `DecksController#show` branched on `@deck.user_id == current_user&.id`, which is
`nil == nil` — **true** — for an ownerless deck read by a visitor, and served them the owner's
page; and `Search::Global#shared_deck_scope`'s `where.not(user: @user)` compiles to
`user_id != ?`, which SQL evaluates to NULL rather than true, so every field list vanished from a
signed-in member's spotlight while a visitor still saw them (hence the explicit
`where(user_id: nil).or(…)`). Three more raised `NoMethodError` on `deck.user.email` — the two
admin deck views and the admin dashboard — and now print `Deck#owner_label`. `Decks::Duplicator`
builds from an attribute allowlist and calls `@deck.user.decks`, so it is unreachable for a field
list by both rules at once.

**Bulk standings import from Limitless TCG** (`/admin/standings_imports`) is written out in **`docs/architecture/limitless-imports.md`** — both sources (the paper results pages and the online "best finishes" leaderboard), the five services and the job, de-duplication and the `player_slug`/`list_digest` key, `tournaments.external_key`, the `"open"` division, the receipt and its undo. Read it before touching `Tournaments::Limitless*`, `StandingsImportPlan`, `StandingsImporter`, or `Import::KINDS`. Three of its rules are about SQLite and orphan rows rather than about Limitless, so they stay here:

**Every printing is resolved before `Decks::Fetcher` opens its transaction.** That transaction is a
SQLite `BEGIN IMMEDIATE`, so the database's single write lock is taken at `Deck.create!`, and
`Cards::Fetcher` goes to the network for any printing not already held at roughly 0.7 s each — one
list of new cards would hold the lock for 15–30 s while every other writer raises
`SQLite3::BusyException` after `database.yml`'s `timeout: 5000`. Warmed first, the same transaction
closes in milliseconds. `StandingsImporterTest` records the transaction depth at each simulated
fetch and fails if any is nested.

**The standing is created first and the list attached after**, because `Decks::Fetcher` commits its
own transaction and `deck` is optional on a standing: build the list first and a row that fails
`placement_within_division_field` leaves a shared, ownerless deck that `/decks/shared` lists and no
path in the app can delete. The attach is then **confirmed against the database** rather than
assumed — `update!` returns `true` even when the row it targets has been deleted, Rails does not
raise for an UPDATE that matched nothing, and standings are wiki-governed while a run walks
hundreds of them, so that `true` is exactly how the same orphan arrives by the other door.

**The event lookup is `find_by || create!`, never `find_or_create_by`**, whose `name_normalized:`
key `before_validation :normalize_name` promptly overwrites with nil, failing validation and
returning an unpersisted record without raising. It rescues **`RecordInvalid` as well as
`RecordNotUnique`**, and the validation is the likely path: `name_and_date_are_unique` is a
non-atomic `exists?` that fires long before the UNIQUE index can, so a member cataloguing the event
between the preview and the write surfaces as `RecordInvalid` — rescuing only the index error
blocked every row of that event instead of reusing the row somebody else had just made.

**The archetype catalog and one archetype's metagame report** (`/archetypes`, `/archetypes/:id`) are written out in **`docs/architecture/archetype-metagame.md`** — `Archetypes::MetagameScope`, `CardStats`, `Performance` and `IndexCounts`, the three things the page refuses to say, the fingerprint grouping, the copies ranges, the role mode, the venue split, and what opening the pages to visitors would cost. Read it before touching anything under `app/services/archetypes/`. Three of its rules stay here:

**Scoping by Standard pool is not a refinement, it is the difference between a true report and a
false one**, and the first real import already proved it: the 93 recorded lists of
*Raging Bolt ex / Teal Mask Ogerpon ex* span three rotations and present **72 distinct cards
blended against 46-48 within any one pool** — a 72-card pool no 60-card deck resembles, with
percentages describing no list anyone played. `tournaments.standard_pool_id` is the axis because
`Tournaments::StandingsImportPlan` writes `StandardPool.at(date)` for every Standard event and
**refuses** one it cannot anchor. Every option carries its list count (`TEF-PBL — 3 lists`), and
the **default is the most recent pool, not the best-populated one**: for that archetype the newest
pool holds 3 lists and the oldest 68, and defaulting to the fuller sample would answer "what does
this deck play?" with 2025 data under a heading that never says so. A sample under
`MetagameScope::SMALL_SAMPLE` (10) renders a notice, because that default view *is* such a sample.
Non-Standard events carry no pool and therefore appear only under "All formats", which the page
says rather than leaving to be discovered.

**One page prints "N lists" four times over, and the four are one number by construction.** The
sample selector, the card report's denominator, the performance panel and the index row each ask
a different service, so agreement is a property that has to be built rather than assumed, and two
things broke it. (Since the venue axis the page also prints a **fifth** number that is deliberately
not one of the four: the pool option's own label, which stays the pool's whole size while the
report covers one venue of it. That is the stable-label trade, and the page says so in words — see
`docs/architecture/archetype-metagame.md`. The four services still agree under every venue, and a
test asserts it.) `CardStats#lists_count` used to be derived from the `deck_cards` rows, which is
"lists holding at least one card" and not "lists" — a field list that resolved no printing gave
the page two denominators and computed every percentage over the one it did not show; it is now
`@standings.distinct.pluck(:deck_id).size`, the same question the other three ask. And all four
count **distinct deck ids**, because `index_tournament_standings_on_deck_id` is not unique and two
standings legitimately point at one deck — two players registering the same 60 cards. A single
test builds both shapes at once and asserts the four numbers equal. `CardStats` plucks where the
other three `COUNT(DISTINCT …)`, and it is the same one statement: the copies figure
(`docs/architecture/archetype-metagame.md`) needs
the **ids**, because a list playing none of a category has to be placed as a zero and a list
holding no card at all appears in no `deck_cards` row. That swap is what turned the service's own
`where.not(deck_id: nil)` from a documented no-op into a load-bearing filter — `COUNT(DISTINCT)`
drops NULLs, `pluck` hands back a nil that `size` counts (measured on the dump with one list-less
standing: 106 against 107). On the page it is *still* a no-op, since `MetagameScope#listed_standings`
filters already; what it now protects is a caller that does not, every one in `CardStatsTest`
among them.

**`ArchetypesController#index` orders and loads in one relation, `includes` and GROUP BY
together** — the obvious fear is that `includes` escalates to `eager_load` beside a GROUP BY,
JOINs `cards` and adds its columns to a SELECT the GROUP BY does not name, and it is wrong:
`includes` only escalates when something *references* the included table (a `where`/`order` naming
it, or an explicit `references`), and nothing here does. Measured on both shapes of the relation —
`Archetype.all`, and `Archetype.search` with its `.distinct` and two extra `left_joins` —
`eager_loading?` is false, both associations come back preloaded, and the page costs three
queries. An earlier version plucked the ordered ids and re-loaded them in a second pass to dodge
an escalation that does not happen, at the price of a query and a Ruby sort; the comment on
`page_of` is what stops it coming back. `.distinct` beside that GROUP BY and an aggregate
`ORDER BY` is something SQLite accepts — worth knowing against #62. `#show` costs **17 queries**
— 16, plus the one grouped read of `card_label_assignments` the card report added — and a
flat-cost test in `ArchetypesControllerTest` holds it there, measured identical at 3 and at 10
lists in the test whether or not those lists' cards carry labels, and by hand at 93.

**The card-label store and the role vocabulary** — `CardLabel`, `CardLabelAssignment`, `/admin/card_labels`, `/admin/card_roles`, `CardLabels::Importer`/`LimitlessSearch`/`RoleSuggester`, and the `/cards` label filter — are written out in **`docs/architecture/card-labels-and-roles.md`**. Read it before adding a label family, editing a role rule, or joining assignments to anything. Three of its rules stay here:

**A `force: true` rescrape moves a card's fingerprint out from under any assignment keyed on it**,
since `compute_fingerprint` recomputes from the card's own text while the assignment still names the
old value. `bin/rails card_labels:resync_fingerprints` is the repair tool for exactly that drift,
the same role `archetypes:resync_fingerprints` plays for `Archetype`'s denormalised columns: it
walks every assignment whose fingerprint now matches no card, re-derives it from the printing the
assignment still names (`card_id`), and **reports rather than writes** the two cases that cannot be
resolved safely — a printing with no fingerprint to read (or none at all, `card_id` having gone
NULL) and a move that would collide with a decision already recorded for the target fingerprint —
so that one ambiguous row does not abort a run part-way through and leave the rest unexamined. **The one thing it does not stop for is a suggestion**: a `suggested`
row sitting on the target fingerprint is deleted and a `suggested` row that is itself in the way of
a decision is dropped, because a machine's opinion must never block a human's. Measured before that
clause existed: a `force: true` rescrape moves a Pokémon's fingerprint, `card_labels:suggest_roles`
writes a `suggested` row on the new one, and the task then left the human's refusal stranded on the
old fingerprint with the guess sitting on the live one — which is what the report renders — and
aborted on every later run, taking the repair tool out of service for good.

**The `role` family is what a card *does*, and it is a constant because code reads it.**
`CardLabel::ROLES` — `draw`, `search`, `gust`, `switch`, `free-retreat`, `recovery`, `disruption`,
`retreat-tax` and `energy-acceleration` — is walked by `db/seeds/card_labels.rb` (skip-if-exists,
so a `db:seed` on every boot never reverts an admin's correction, and a role's *name* stays
editable while the row cannot be created or destroyed from the panel). The slugs are kebab-case
because `CardLabel`'s own format validation refuses anything else, and `energy_acceleration` reads
better in Ruby: a test walks every entry through the model, since nothing else would report the
mismatch — the seed skips a slug it cannot create as readily as one that already exists, and a
fresh database would come up one role short in silence. Roles are game mechanics and a property of
the **card**, never of the archetype playing it (Fezandipiti ex is `draw` in a deck that attacks
with it); "attacker" is deliberately not a role, since every Pokémon is one. **The list is
declared in `position` order, and that is load-bearing rather than tidy**: `CardLabel.roles` is
`order(:position, :slug)` and `CardLabelSeedTest` asserts the seeded rows come back in the order
the array declares them, so a role appended with an interleaving position turns it red — which is
how `free-retreat` (45) and `retreat-tax` (65) were found to belong in their slots rather than at
the end. The two retreat roles and the guards on their rules are written out in
`docs/architecture/card-labels-and-roles.md`.

**The rules carry no version, and the "played" filter is not a fixed population.** Changing a regex
silently rewrites every `suggested` row it owns — the run's `withdrawn` count is the only trace and
nothing persists it — so a rule is edited the way a migration is written, not the way a typo is
fixed. And `played_card_ids` reads every standing in the database, so the 94 fingerprints the
curation screen defaults to grow with every import: a pass that was "finished" un-finishes itself,
quietly, and nothing on the screen says so.

`StandardPool` is one period of the rotating Standard calendar: two `CardSet` bounds — the oldest legal set, moved by the annual rotation, and the newest, moved by every release — plus the legal `regulation_marks` and **two** dates. `(first_card_set_id, last_card_set_id)` is UNIQUE because that pair *is* the pool's name, `TEF-PBL`, which is what players call it. `released_on` says the cards exist and drives `StandardPool.current`, the anchor a new deck is pre-selected to; `legal_on` says Play! Pokémon considers the pool legal and drives `StandardPool.at(date)`, which is what a tournament asks — a set is tournament-legal about two weeks after it ships, so neither date derives from the other. `Deck` and `Tournament` each carry a `standard_pool_id`, required by validation when the format is `standard` and cleared otherwise (the `other_format_name` pattern): **only Standard rotates**, the other three formats are eternal and have no anchor. The anchor is **pinned** — nothing moves it automatically, and `Ui::StandardPoolNotice` merely invites the user to. `has_many :decks, dependent: :restrict_with_error`, unlike `Archetype`'s `:nullify`, because a NULL anchor on a Standard deck is unsavable on its next edit. Deck-construction rules are deliberately **not** here: see #61.

`db/seeds/standard_pools.rb` is a **bootstrap, not the source of truth**: pools are maintained from the admin panel, so the seed is keyed on the bound pair and **skips any row that already exists** rather than reasserting its values — otherwise every `db:seed` would silently revert an admin correction. Two of its values are not derivable and carry comments saying so: the `J` regulation mark starts at ASC, not MEG (the Mega Evolution block opens on `I` — *Mega Lucario ex* is MEG 77), and ASC's `legal_on` is 2026-03-06, five weeks after release rather than the usual two, because it shipped staggered and Play! Pokémon pushed legality past the 2026-02-13 EUIC. Re-deriving either with the two-week rule reintroduces a bug.

**Archetype identity is a fingerprint pair, not a card pair.** `primary_card_id`/`secondary_card_id` say which printing to *display*; `(primary_fingerprint, secondary_fingerprint)` is UNIQUE and says which archetype it *is* — two archetypes built from two printings of the same cards are duplicates, not siblings. A missing secondary is the **empty string, never NULL**: the previous `(primary_pokemon_id, secondary_pokemon_id)` index looked unique but SQLite treats NULLs as distinct, so duplicate single-member archetypes got through it for as long as it existed. Members may be **any** `card_type`, which is what lets a Trainer engine (Lost Zone Box, Mill/Stall) be an archetype at all. The denormalised columns back the index and **nothing else** — detection joins `cards` and reads the live fingerprint — which is what makes drift after a re-scrape harmless and lets `Archetypes::FingerprintSync` repair it out of band. `Archetype.search` spells its second join alias by hand (`secondary_cards_archetypes`), derived from the association name, so renaming that association breaks the scope at *query* time, not at load time.

**An archetype's *address* is a slug of its name, and the two archetype pages are public.** `archetypes.slug` is `name_normalized` parameterized — stored, `NOT NULL`, UNIQUE, with a `CHECK (slug <> '')` beside them, recomputed on every save, so renaming an archetype moves `/archetypes/:id` and **nothing records the old address**: links to it break, deliberately. `assign_slug` is a **`before_save`**, not a `before_validation`, and that is what lets `Archetype#to_param` read the column plainly: a *refused* rename never touches it, so the re-rendered admin form cannot post to the archetype whose slug the rejected name collided with and rename the wrong row with a 200 — which is exactly what the first version did. Both the uniqueness validation and the callback read one `derived_slug`. Both lookups key on the column (`ArchetypesController#show`, `Admin::ArchetypesController#set_archetype`, the latter for the reason `Admin::DecksController` keys on `decks.key`); `Api::ArchetypesController` keeps integer ids, because its JSON `id` feeds a `<select>` and a `deck.archetype_id` write — a reference to a row, not the address of a page, the same split `decks.id` keeps against `decks.key`. **Two callback orderings are load-bearing and neither is the obvious one.** `before_validation :normalize_name` is declared after `auto_generate_name`, because that callback supplies the name when nobody typed one and the validation reads `derived_slug` off the mirror — reversed, a create through `Api::ArchetypesController` validates a blank slug and 422s. And `before_save :assign_slug` must run after `NameNormalizable`'s own `before_save :normalize_name`, which holds only because `include NameNormalizable` sits on the model's second line; *its* position relative to `auto_generate_name` is irrelevant, since a `before_validation` always precedes every `before_save`. **Three refusals, all on `:name`** because that is the only field the admin form has — a collision (a UNIQUE slug adds the rule "names must differ by more than punctuation"; measured, two of the catalogue's 1806 card names collide, both Nidoran gender-symbol pairs), a blank (`parameterize` returns `""` only for a name with no Latin-transliterable character, which is what #111 will produce — and the `CHECK` is what makes that state unreachable rather than merely invalid, since `assign_slug` being a `before_save` means a validation-skipping write reaches the column), and **`RESERVED_SLUGS`**: `resources :archetypes` in the admin namespace emits `GET /admin/archetypes/new` ahead of `:id`, so an archetype slugged `new` has no reachable admin show page and `#update`'s redirect lands on a blank New form saying "Archetype updated.". `edit` needs no entry, being nested under `:id`; the list grows if either resource ever gains a collection route. Fixtures spell `slug` out by hand beside `name_normalized`, and `ArchetypeTest` asserts every one of them against `name.squish.downcase.parameterize` — plus that the *migration's* own copy of that rule agrees with the callback, since `db:test:prepare` loads the schema and CI never runs a migration. See `docs/architecture/public-surface.md` and `docs/architecture/archetype-metagame.md`.

**Allocation model** (collection as physically-owned inventory): `Collection.quantity` is the number of copies **owned** (source of truth; unique per user+card). `DeckCard.owned_copies` is how many of its copies are **real** (backed by owned cards); `quantity` is the total, `proxies = quantity − owned_copies` (unique per deck+card). Only decks with `physical == true` consume the collection. Invariant: `Σ owned_copies(card) over physical decks ≤ owned(card)` — exceeded only by a collection decrease, which is allowed and leaves a tolerated, surfaced over-allocation (never auto-corrected). Deck-level proxy state is **derived, never stored**: `Deck#has_proxies?` is `physical? &&` any `deck_card` with `owned_copies < quantity`, with `Deck.with_proxies` / `Deck.without_proxies` (over `DeckCard.with_proxies`) as the SQL counterpart backing the deck-list filter. The `physical` half is load-bearing on both sides — a non-physical deck's cards sit at `owned_copies 0` by construction, so the bare per-card test would match every TCG Live deck. The `decks.has_proxies` column and its form checkbox are gone (issue #56); because the badge now derives from data the deck page edits in place, every write in `Api::DeckCardsController` answers with a `deck: { has_proxies: }` key — including the card-removal case, which answers `{ removed: true }` instead of a body-less 204 — and the `deck-proxies` Stimulus controller toggles the badge, which the show header always renders (hidden when it does not apply). User has an `api_token_digest` (SHA-256 of a per-user MCP bearer token — see `User.authenticate_api_token` / `regenerate_api_token`).

**Controllers**: API endpoints under `Api::` namespace serve JSON (archetypes, cards, collections, decks with nested deck_cards and deck_results). `Api::DeckCardPrintingsController` (`GET …/cards/:card_id/printings`, `PATCH …/cards/:card_id/printing`) is separate from `Api::DeckCardsController` because that one identifies a row by its card id — the very thing a printing swap changes; the two share the deck lookup and the row JSON through the `DeckCardPayload` concern. Its swap response also carries what the page needs to rewrite the row in place: `merged`, `max_owned`, `over_allocated` and `image_path`. Admin panel under `Admin::` namespace covers dashboard, card sets (with import), cards (with rescrape), users (with toggle_admin), decks, archetypes (CRUD), standard pools (CRUD, no show page — a pool is five fields and the index shows all of them), card labels (CRUD for `type`, edit-only for `role`, plus the member action that imports one label from Limitless), and imports (list with error display, delete, retry). Top-level `tournament_profiles` and `deck_results` resources live alongside `decks`. `DeckResultsController` and `Api::DeckResultsController` both permit `tournament_entry_id` now, so a result can be attached to the participation it was played at. `Tournaments::EntriesController` routes under `resources :entries` — the URL reads `/tournaments/:tournament_id/entries/:id` — while the model is `TournamentEntry`, which is why its forms pass an explicit `url:`: polymorphic `form_with` would otherwise build `tournament_tournament_entries_path`, which does not exist. `Tournaments::StandingsController` is the same shape one level further: `resources :standings` under `tournaments`, no show and no index (the sheet lives inside `tournaments#show`, and a row is six fields), and forms that likewise pass an explicit `url:`. App routes require Devise authentication except the surface `PubliclyReachable` opens — `home#dashboard`, `search#show`, all of `resources :decks` (and, by nesting, its `deck_results` routes), all of `resources :cards`, `archetypes#index`/`#show`, and `tournaments#index`/`#show` (with `resources :tournaments` now carrying **two** nested resources out of `authenticate :user` by nesting alone — `entries` and `standings`, the same way `resources :decks` carries `deck_results`) — plus `og_images#deck`/`#archetype`/`#card` under `/og`, plus the always-unauthenticated `root`, `/up`, `/mcp` and the OAuth endpoints; each of the seven `PubliclyReachable` controllers still calls `authorize` on every action, so "no session required" is not "no check performed". See **Shared decks** below.

**The MCP server and the OAuth 2.1 authorization server** are written out in **`docs/architecture/mcp-and-oauth.md`** — `POST /mcp` and `Mcp::ServerController`, the two bearer credentials and the order they are tried in, the two rate limiters that sit between them, the tool classes in `app/mcp/` and how a new one is registered, Doorkeeper's configuration, RFC 7591 client registration, the two discovery documents, the consent screen and its scope narrowing, and the connected-apps screen. Read it before adding an MCP tool or touching anything under `/mcp` or `/oauth`.

**The public surface** is written out in **`docs/architecture/public-surface.md`** — `PubliclyReachable` and the blind spot it cannot cover, the policies that say yes to a nil user and never yield to an admin, the separate public views, the Share control, `XRobotsTagMiddleware`, the nine per-IP rate limits and how each was sized (including why hover prefetch, not a click, sets the peak rate of a page a listing links to), and `Search::Global`'s visitor path. Read it before making a route reachable without a session, before adding a `rate_limit`, and before touching a policy. Three rules stay here, because they are about deck identity rather than about the public surface:

**Shared decks — deck identity.** A `Deck` is addressed by its `key`, not `decks.id`, everywhere the address crosses a boundary of the app: the URL segment, JSON, an MCP tool argument, a Stimulus value. `decks.id` stays the primary key and the target of every foreign key, so a `<select>` of decks (the tournament entry form) and an internal write param (`over_allocations#reallocate`'s `from_deck_id`/`to_deck_id`) still carry the integer — those reference a row, not a page. `Deck::KEY_BYTES = 16` (`SecureRandom.urlsafe_base64(16)`, 22 URL-safe characters, 128 bits) is assigned by `assign_key`, wired as `before_validation :assign_key, if: -> { key.blank? }` — `before_validation` rather than `before_create` so the callback and the `presence` validation agree, and the `key.blank?` guard both stops an update from rewriting the key and heals a row a callback-bypassing insert left keyless. There is no uniqueness validation — the UNIQUE index on `key` is the guarantee, the same division of labour as `(set_name, set_number)` on `Card`. `Deck#to_param` returns the key, which is why 35 of the app's `deck_path`/`deck_url` call sites needed no edit to start emitting it; two sites the helper cannot reach on its own needed one anyway — `over_allocations/index_view.rb`'s `deck_path(d[:key])`, fed by `Allocations::PhysicalDecksByCard` now plucking `decks.key` alongside `decks.id` (kept, since the reallocation form's `<select>`s still need the row), and `/decks/compare?ids[]=…`, whose `DecksController#compare` maps `params[:ids]` to strings, looks up `Deck.where(key: ids)`, and re-sorts by `ids.index(deck.key)`.

**Where the unscoped lookup lives.** This feature creates exactly one unscoped deck lookup in the whole app: `Deck.find_by!(key: params[:id])` in `DecksController#show` and `#export`, immediately followed by `authorize` — nothing else runs first. Every other lookup stays scoped by association and only changed which column it keys on: `current_user.decks.find_by!(key: …)` in the rest of `DecksController`, in `DeckResultsController`, `Api::DecksController`, the `DeckCardPayload` concern, and `McpTool#find_deck!`. `Admin::DecksController` is the one pre-existing exception — already unscoped, because an admin panel lists everybody's decks, gated by `Admin::BaseController#require_admin!` rather than by anything below.

**`decks.shared`** is a boolean, `NOT NULL`, `default: false`, with hand-written `shared`/`unshared` scopes: Active Record's `dangerous_class_method?` refuses to generate a `public`/`private` enum or scope, since both are `Module` methods, so the column, the scopes, the Share modal and the badge all settle on `shared`/`unshared` instead. Existing decks come out of the migration private. `Decks::Duplicator` builds a copy from an explicit attribute allowlist, so `shared` — like any future column — is excluded from a duplicate by construction; a copy of a shared deck is never itself shared.

**Frontend**: Hotwire (Turbo + Stimulus), Propshaft asset pipeline, importmap for JS. **All views use Phlex components** — see the `phlex-architecture` skill for conventions and patterns. Always use Phlex, never write view logic in ERB.

**Link previews and the app icon.** Every page emits Open Graph and Twitter-card tags through `Ui::OgTags`, which `Layouts::ApplicationLayout` renders **unconditionally** — `OgPreviewHost#og_preview` never answers nil, so a page nobody thought about still previews as Cartodex rather than as a bare URL, from the committed `public/og-default.jpg`. Three surfaces replace that with a banner of their own by assigning `@og_payload`: a deck, an archetype and a card. `Og::*Payload` decides what a banner *says*, `Og::Renderer` draws it (the only file in the app that knows libvips), `Og::Cache` addresses the file. Six rules bite from outside their own files:

- **`og_preview` needs two declarations**, `helper_method` in the concern *and* `register_value_helper` on `ApplicationComponent`, and the concern goes on `ApplicationController` **and** `Oauth::AuthorizationsController` — the layout's second host, which does not descend from the first. `oauth_consent_test.rb` is what catches the omission, as a 500 on the one page in the app that would have it.
- **The assignment lives in the action, after its `includes`.** `Og::DeckPayload` walks the deck cards, the archetype's two member cards and the pool's two bounds, so both `#show` paths carry `Deck.with_standard_pool` plus `archetype: [ :primary_card, :secondary_card ], deck_cards: { card: :pokemon_subtype }`; `ArchetypesController#show` may read **only** `primary_card`/`secondary_card`, because a literal `assert_equal 17` pins its cost in three places.
- **The deck digest folds in the deck-cards' count and newest `updated_at`, not just `deck.updated_at`.** `DeckCard belongs_to :deck` has no `touch: true`, so adding, requantifying or removing a card leaves the deck's timestamp alone — the banner's content would change and its address never would, permanently, under `immutable`.
- **`?v=` is a cache-buster the endpoint never reads.** A client that cached `?v=<old>` re-requests exactly that URL and `Og::Cache` has deleted that file, so keying on it would break every preview once, at the moment its subject changed.
- **`Og::Renderer` escapes Pango markup and names its image loader.** `Vips::Image.text` hands its argument to `pango_layout_set_markup`, so an unescaped `&` — "Anthea & Concordia" and every Tag Team card — was an unrescued 500, and `<b>` in a deck name drew as bold. And it re-enables libvips' `svgload`, which adding `ruby-vips` made ActiveStorage block process-wide; that is only safe because remote bytes go to a loader named from the URL's extension rather than one libvips picked by sniffing.
- **A degraded render is served and not stored.** A failed art is invisible to the digest, so caching an artless banner would pin it at that address until the subject was next edited.

`bin/rails icons:build` rasterises the three icon SVGs into the committed PNGs and needs `:environment` — not for models but because it reads an autoloaded constant to lift that same `svgload` block. `bin/rails og:default_banner` rewrites `public/og-default.jpg`.

**The design system, the global search spotlight, the navbars and the shared form components** are written out in **`docs/architecture/frontend.md`** — the CSS custom-property token system at the top of `application.css` and its three override layers, `/styleguide`, `Search::Spotlight` and the four details that keep its trigger and its field from working against each other, `Ui::NavbarShell` and `Ui::NavLinks.section_for`, `Ui::CardSelect`, and `Ui::StandardPoolNotice`. Read it before adding a component, a navbar entry or a design token.

## Bin Scripts

- `bin/import_deck DECK_NAME [FILE]` — import decklist from file or stdin, fetches card data from web
- `bin/export_decks` — interactive JSON deck export
- `bin/export_deck_ptcg` — export deck in PTCG text format
- `bin/rails 'mcp:token[email@example.com,90d]'` — rotate and print a user's MCP bearer token (shown once; only the digest is stored). Lifetime is `30d`/`90d`/`1y`/`never`, default `90d`. Deprecated: this static token still works, but OAuth 2.1 via Doorkeeper (see `docs/architecture/mcp-and-oauth.md`) is the supported way to connect a client.
- `bin/rails standard_pools:backfill_anchors` — anchor Standard decks and tournaments that predate the `standard_pool_id` column. Run **after** `db:seed`, which creates the pools it needs; idempotent.
- `bin/rails card_labels:resync_fingerprints` — move card label assignments onto their card's current fingerprint after a `force: true` rescrape moves it out from under them, reporting rather than writing whatever it cannot resolve safely.

## Test Setup

Minitest with parallel execution. Fixtures in `test/fixtures/`. System tests use Capybara/Selenium/headless Chrome and live in `test/system/`; they sign in through `Warden::Test::Helpers` (`login_as user, scope: :user`) because the user fixtures store a literal string in `encrypted_password`, so no password would ever authenticate. `ApplicationSystemTestCase` turns `allow_forgery_protection` **on** for the duration of each system test: the test environment disables it, `csrf_meta_tags` then renders nothing, and `requestJson` reads `.content` off a null meta tag — every browser-driven write dies in its `catch` and reports "the request didn't reach the server". Request tests keep the relaxed setting.

**The system suite runs twice, once on each side of the app's single 768px breakpoint**, and the rule is that **every system test is expected to pass on both**. `SYSTEM_TEST_VIEWPORT` picks the side — unset (the default, and what `bin/rails test:system` gives you locally) is desktop at 1400×1400, `mobile` is 390×844; CI has a job per side (`test` and `system_test_mobile`), and `viewport_sweep_test.rb` is the guard that the selected side actually reached the browser. The breakpoint is checked in **JS** (`card_preview_controller.js`, `window.innerWidth <= 768`) as well as in CSS, so "mobile" is not a styling concern that can be assumed cosmetic: below it the card preview stops being a hover pane and becomes a full-screen `<dialog>` whose backdrop eats subsequent clicks.

Two consequences for writing one:

- **Navigation differs.** Below the breakpoint `.navbar-menu` is `display: none` until the hamburger toggles `.navbar-menu--open` onto it, and Capybara will not click what it cannot see. Never click a nav link directly — use `click_nav_link`, which is a plain click above the breakpoint and opens the menu below it (and retries, because the toggle click and the link click straddle a Turbo page swap).
- **A test that asserts about a *width* rather than about a *side* must pin it**, with `drive_at width, height`. **Chrome will not give a window narrower than 500px** — not through `screen_size:`, not through `--window-size`, not through `resize_to` (all three measured) — so the mobile half of the sweep really renders at 500, and a bug that breaks at 344 but not at 500 is invisible to it (exactly #99's). `drive_at` overrides the viewport through CDP, which escapes that floor, clears it on teardown because the browser is shared by the whole run, and skips the half of the sweep its width does not belong to. It is Chrome-driver-only: runs against the devcontainer's remote Selenium skip with a reason.

Passing at both widths is the **floor, not the ceiling**. It stops a test from silently only ever exercising the desktop side; it does not assert anything about mobile-specific behaviour. A test that clicks once and then only asserts will pass below the breakpoint with the preview modal open over the page, since Capybara still considers inert content visible. Mobile-only behaviour needs its own assertions, which is what `card_preview_modal_test.rb` is: the `<dialog>` the preview becomes below the breakpoint, what it shows, and what closes it. The hover pane it replaces above the breakpoint (`card-preview#show`) is still untested.
