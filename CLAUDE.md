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

**`Tournament` is the shared public event; `TournamentEntry` is one member's private participation in it.** Any member may catalogue an event, and every other member's entry hangs off the same row — what a given player did there belongs on the entry, not the event. `(name_normalized, date)` is UNIQUE and *is* the event's identity — the same division of labour as `(set_name, set_number)` on `Card`: the model validation exists for the readable error, the index for the guarantee. `normalize_name` runs `before_validation` here, in addition to `NameNormalizable`'s own `before_save`, because the uniqueness check has to see the normalized value before the record is validated, not only once it is saved. It **squishes** as well as downcasing, and so does the query side (`normalize_for_match`) — fold only what is stored and a name typed with a double space becomes unfindable: a name arrives copy-pasted, with a trailing space or a double space where a line wrapped, far more often than it arrives typed, and without the squish one real event gets two catalog rows that render identically and both answer the same search. The split migration's `merge_key_name` mirrors the same rule, since rows written before it carry an unsquished `name_normalized`. `participant_count` stays on `TournamentEntry`, not `Tournament`, because Play! Pokémon ranks a placement against the size of *that player's age division*, not the event's attendance — two entries at the same event legitimately carry two different counts. Entry uniqueness is two partial indexes, `(tournament_id, tournament_profile_id)` where a profile is attached and `(tournament_id, user_id)` where it is not, because SQLite treats NULLs as distinct — the same trap `Archetype`'s old `(primary_pokemon_id, secondary_pokemon_id)` index fell into (see **Archetype identity** below): a single index on `(tournament_id, tournament_profile_id)` alone would never see two profile-less entries from the same player collide. **Both ends of a participation refuse to be deleted out from under it.** `Tournament has_many :entries` and `Deck has_many :tournament_entries` are `dependent: :restrict_with_error`, as is `TournamentProfile`'s — unlike `User`'s `:destroy` or `created_tournaments`' `:nullify`. On the event that stops another member's participation vanishing because the catalog entry's creator deleted it; on the deck it stops the *player's own* record of a placement, CP and profile vanishing behind a confirmation that only ever mentioned cards and results, and it is the one cascade that used to leave the event standing while the attendance disappeared. `TournamentsController#destroy` and `DecksController#destroy` therefore both branch on `destroy`'s return value and name the count in the alert — `restrict_with_error`'s own message names the association, not what is in the way. **`User has_many :tournament_entries, dependent: :destroy` is declared ahead of `:decks` and `:tournament_profiles`, and the order is load-bearing**: dependent callbacks run in declaration order, so "Cancel my account" only works because the entries go first — `UserTest` covers exactly that, and moving the line back below either association turns it red. The other half of the same rule lives on the entry: `TournamentEntry` refuses to change `deck_id` while `deck_results` are attached to it, because `DeckResult#entry_belongs_to_same_deck` is only checked when the *result* is saved and nothing re-checks it when the entry moves underneath — the update would otherwise succeed and leave every attached match invalid. Refusing rather than detaching keeps the decision with the user, the same call the two `restrict_with_error`s make. **An event's sheet is paginated** (`TournamentStanding::SHEET_PER_PAGE`, 50). A hand-typed sheet is
a handful of rows; a Worlds field is a thousand, on a page that is public and deliberately carries
no rate limit ("one page load per click"), and that preloads three associations for every row it
renders. Two things had to move for a page boundary to be drawable at all. `as_a_sheet` now orders
the divisions **in SQL** by `TournamentStanding.division_order`, an Arel CASE over `DIVISIONS` — `ORDER BY division` is
alphabetical (junior, masters, senior) while players read junior, senior, masters, and
`Standings::Table` had always regrouped them for display, so with the two orders disagreeing a
boundary drawn in SQL falls where the reader never sees it: page two opening in the middle of a
division page one appeared to finish. And **everything that points at a row now points at the page
it is on**, anchored to it: the redirect after every write that leaves the row standing (a refused
`#claim` included — the row is still there and the alert is about it), the duplicate-name hint on
the form, and Cancel. "Back to the event" is the top of page one, which need not hold what the
member just typed. `Tournaments::Standings::Row.sheet_position` is the one place that answers it,
beside `dom_id` because the anchor *is* the row's identity, and in one place because three copies
of "which page is it on" drift; it reads `TournamentStanding.page_of`, one `pluck` of ids over one
event's field rather than a COUNT predicate that would restate the scope's ordering somewhere else.
`#destroy` reads the page *before* the row goes and clamps it *after*, since deleting the only row
of the last page otherwise leaves a `?page=` that no longer exists in the address bar and in any
link shared from it. `#show` clamps an out-of-range `?page=` to the last page rather than rendering
an empty table under "No standings recorded for this event yet." — which is false, and which a
public URL will be asked for; `#index` got the same clamp for the same reason, having told the same
lie about the catalog since it was written. There is **no Turbo Frame** here,
unlike the three listings that have one: those wrap a debounced filter field where a keystroke
would otherwise pay for the whole surrounding page, nothing on this page fires on its own, and a
frame would capture every link inside the rows — the deck link, Edit, Delete, "This is me" — each
of which would then need `data-turbo-frame="_top"`. `Ui::Pagination` is the markup all four
listings now share; `turbo_action: "replace"` is opt-in on it, because inside a frame it is what
puts `?page=` into the address bar at all while on an ordinary page it would only overwrite the
history entry, so Back from page 2 would skip page 1.

`Tournament.with_standard_pool` is a deliberate twin of `Deck`'s, for the same measured reason — `StandardPool#name` reads both of its bounds, and dropping the scope took the catalog page from 11 queries to 23. A view that reaches the event through `entry.tournament` throws that preload away and lazily re-reads all four rows, which is why `Tournaments::Entries::ShowView` takes `tournament:` as its own keyword rather than deriving it.

**Entry uniqueness is per Play! Pokémon profile, not per user**, and every reader of it has to be plural. A parent tracking their own and their child's profiles legitimately has two participations in one event, so `TournamentsController#show` loads `@my_entries` — a singular `find_by` picked one of them arbitrarily and left the other unreachable from the only page that links to it — and the event page renders one button per entry, labelled with the player name once there is more than one to tell apart. It keeps offering "Record another participation" while the reader still owns a profile this event holds no entry for; that test is deliberately *narrower* than `one_entry_per_player` and deliberately not a restatement of it, so a reader it says no to loses a button rather than meeting a form that then refuses them. **A visitor gets none of it.** `can_record` — `policy(Tournament).create?`, passed by the ERB — guards `entry_action` as a whole rather than its `empty?` branch, because a visitor's `my_entries` is `[]` by construction and the empty case *is* the "Record your participation" button: a primary-styled link to the sign-in page, which is the navbar's job to offer and not this page's. `create?` and not `mine?` on purpose, even though both answer `user.present?` today and therefore no test can tell them apart — the question here is "may this reader record a participation", and reading it as "may they see their own list" is what would make the button vanish from every event page, silently, the day one of the two grows a condition. One **deck** can likewise carry two participations in one event, which is why `TournamentEntry#picker_label` — the label both tournament pickers print, kept on the model for the reason `Card#printing_label` is — names the profile: `"Name (date)"` alone prints the two options identically. Both pickers read the *loaded* association rather than building a fresh relation over it (`Decks::ResultModal`, `DeckResults::EditView`), because `picker_label` reads the event **and** the profile and both controllers preload the pair; a relation rebuilt with its own `includes` ignores the preload and N+1s on the profile, which a plain query count cannot see — the entry `SELECT` it repeats is served by the query cache. Flat-cost tests in `DecksControllerTest` and `DeckResultsControllerTest` are what actually hold that down.

**A `TournamentStanding` is a line of the event's own public sheet; a `TournamentEntry` is a
member's private participation in it.** They are two tables and not one because the players a
sheet records have no account here — a standing therefore hangs off the `Tournament`, carries a
free-text `player_name` plus its normalized mirror, and is governed as a **wiki**: any signed-in
member may add, correct or delete any row (`TournamentStandingPolicy` answers `user.present?` to
every write), with `created_by` the only trace of who typed it. That policy reads no `admin?`,
unlike `TournamentPolicy`, because there is no moderation question a member cannot already
answer. `(tournament_id, player_name_normalized, division)` is UNIQUE and *is* the row's identity
— the model validation exists for the readable error, the index for the guarantee, the same
division of labour as `(set_name, set_number)` on `Card`. `normalize_player_name` runs
`before_validation` **and** `before_save`, for the reason `Tournament#normalize_name` does, and it
**squishes**: a player name arrives copy-pasted off a standings sheet far more often than it
arrives typed. `NameNormalizable` is not included — it normalizes `name`, not `player_name`, and
nothing searches standings by player. The cascades are opposites on purpose:
`Tournament has_many :standings, dependent: :destroy` (the sheet is the event's, so it goes with
it) while `TournamentEntry has_one :standing, dependent: :nullify` (deleting my private record
must not erase a public row other members read). `Archetype has_many :tournament_standings,
dependent: :restrict_with_error` — unlike its own `:nullify` cascades on `decks` and
`deck_results` — because `archetype_id` is `NOT NULL` on a standing, `:destroy` would silently
erase another member's public record, and leaving the association off entirely would raise a bare
`ActiveRecord::InvalidForeignKey` from a reachable admin destroy; `Admin::ArchetypesController#destroy`
branches on the return value and names the count in the alert, the same shape `TournamentsController#destroy`
and `DecksController#destroy` already use for their own `restrict_with_error` cascades.
`User has_many :created_standings, class_name: "TournamentStanding", foreign_key: :created_by_id,
dependent: :nullify` — an authorship trail, not a participation, so it nullifies like
`created_tournaments` rather than cascading like the entries above it. A `before_destroy` takes
the field list with the row, but **only a list nobody owns** — nothing points a standing at an
owned deck today, and the guard is what stops a future caller detonating a member's deck through a
standings delete.

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

**The event carries three field sizes, and `TournamentEntry#participant_count` survives beside
them.** `junior_participant_count`/`senior_participant_count`/`masters_participant_count` are
read through `Tournament#participant_count_for(division)` and cap a standing's `placement` — per
division, because Play! Pokémon ranks a placement against the size of *that player's* age
division. The entry's own column is not a duplicate and is not derivable from them: an entry with
no `tournament_profile` has no division, so there is nothing on the event to read.
`TournamentStanding::DIVISIONS` is `TournamentProfile::DIVISIONS` mapped to Strings rather than a
second list — and `TournamentProfile#division` answers with a **Symbol**, which the enum column
will not take, so the prefill calls `.to_s` and asks about the *event's* date rather than today
(a division is fixed for a whole season). A participation with no `TournamentProfile` has no
division to copy, so `prefill_attributes` drops the key entirely — which is why
`Tournaments::Standings::Form` passes an explicit `selected:` (`DEFAULT_DIVISION`, `"masters"`)
rather than letting the browser pre-pick the first option and silently publish a Masters player as
a Junior. `placement_hint` reads that same default, or the form would offer "leave blank if nobody
remembers" beside a select already reading Masters at an event whose masters field size is known.

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

**The field-list import reuses `Decks::Fetcher` and deliberately not `Decks::ImportJob`.** That
job broadcasts the finished deck into `#decks-grid` and replaces `#deck-count`, which would file a
tournament field list in the contributor's own deck list — the one thing an ownerless deck must
not be. `Tournaments::StandingListImportJob` broadcasts the standing's own row instead
(`Tournaments::Standings::Row.dom_id`, which is why that row is its own Phlex component rather
than a block inside `Ui::DataTable`), to the **contributor's** `:notifications` stream, rendered
through `ApplicationController.renderer.render(component, layout: false)` rather than a direct
`.call`: `Phlex::Rails::Helpers::Routes` overrides `url_options`/`default_url_options` to delegate
to `view_context`, and Rails' `url_for` consults those **even for `_path` helpers** — so a
component using `link_to`/`button_to` cannot render outside a request. `Decks::ImportJob` gets
away with the direct call for two independent reasons: `Decks::DeckCard` calls
`Rails.application.routes.url_helpers.deck_path` as a **module method**, bypassing the override,
*and* it is rendered with `with_actions: false` so `link_to`/`button_to` never run. The broadcast
row's own `button_to` (claim/unclaim, delete) carries no CSRF token and works only because Turbo
attaches `X-CSRF-Token` from the *live page's* own meta tag before submitting — a plain form
submit or a client that skipped Turbo would 422; this is now exercised by a system test that
clicks a button on a row a live broadcast delivered, not merely asserted in a comment. The
broadcast passes `claimable_entries` rather than leaving `Row`'s `[]` default: it replaces the row
wholesale, so a contributor with an unrecorded participation at this event watched their own "This
is me" button disappear until the next reload. A failed
broadcast must not rewrite a successful import: the job's broadcast has its own `rescue` that only
logs, and the outer `rescue` reports failure only for an error raised before the deck lands — the
import's work is the deck, the broadcast is a notification about it. **The job is enqueued with
ids, not records**, unlike `Decks::ImportJob` and `CardSets::ImportJob`, and the reason is
governance: those two are handed a user and an import, neither of which can vanish mid-flight,
while any member may delete this standing — or the event, which cascades onto it. Handed records,
GlobalID raises `ActiveJob::DeserializationError` **before** `#perform` is entered, where the
method's own `rescue` cannot see it: the `Import` would sit at `"pending"` forever, with
`Admin::ImportsController#retry` refusing this kind and no other way to clear it. As ids the
deletion is an ordinary lookup miss, raised as `StandingDeleted` and reported down the same path as
a bad decklist. The `rescue` also **destroys the deck it just created** when the `update!` attaching
it fails: `Decks::Fetcher` commits its own transaction, so the list lands first, and what is left
otherwise is exactly the orphan the re-import path guards against — ownerless, `shared: true`,
referenced by nothing, unreachable. It re-reads `deck_id` from the database rather than off the
record, because `update!` assigns the association *before* it validates, so a failed attach leaves
the in-memory `standing` pointing at the new deck while nothing was written. The pending state renders as
a `Ui::ImportingList` beside the standings table, not as a spinner inside the row: a per-row
spinner would cost a `tournament_standing_id` on `imports` for a state every contributor already
sees listed beside the table — a decision, not an oversight. `imports` does carry a nullable
`tournament_id`, which is a different column answering a different question: *which page* is
waiting. Without it `TournamentsController#show` listed every pending `standing_list` import the
reader had anywhere, so an import started at one event appeared under another event's
"Importing…" heading — and since the item's DOM id is `importing-<import id>`, the first event's
completion broadcast then removed a row from a page it had nothing to do with. `Tournament has_many
:imports, dependent: :nullify`, like `created_tournaments`: an `Import` is the member's own record
of work they asked for and outlives its subject, the way a deck import already outlives the deck. `Ui::ImportingList` gained a `list_id:` keyword (defaulting
to `"importing-decks"`, so its two pre-existing callers are unchanged), because two lists on one
page must not share a DOM id. `Decks::Fetcher` gained
`shared:`/`format:`/`standard_pool:`/`other_format_name:` keywords and accepts a `nil` user: a
field list is anchored to **the event's** pool, not to `StandardPool.current`, because the event
has a date and it is the only thing that knows which pool was legal — and
`clear_inapplicable_classification` drops the pool when the format is not Standard and the custom
name when it is not Other, so neither a GLC event's list nor a Standard one needs a special case. The deck's name is
`"<player> — <event> (<date>)"` because `/decks/shared` prints no author and the name is the only
thing that can situate the list. `Import::KINDS` gained `standing_list`, and
`Admin::ImportsController#retry` **refuses** it explicitly rather than falling through the `case`:
the decklist text is not stored, so there is nothing to re-run. (The `"deck"` branch of that same
`case` has never worked — it re-enqueues `@import.label` as the *decklist*, which is the deck's
name. Pre-existing, out of scope, recorded so the new kind is not wired into the same silence.)
The archetype `Decks::Fetcher` detects stays on the deck and never overwrites the standing's own:
the standing's was declared by a human making a record, detection exists to guess when nobody has,
and a disagreement between the two is information rather than a conflict.

**Out of scope here, and the obvious next issue:** aggregation of any kind — no per-event
metagame breakdown, no cross-event metagame page. The archetype FK and the `division` column are
chosen so that a breakdown is a `group` over one table when it ships. Also out: claiming a row as
a player with no account (claiming *is* a member linking their own participation), importing
standings from RK9, and Championship Points on a standing. (Importing them from Limitless is no
longer out — see the next section.)

**Bulk import of a field from Limitless TCG** (`/admin/standings_imports`) turns one archetype's
tournament history — `limitlesstcg.com/decks/<deck_id>/results`, measured at 176 event headings and
1569 placement rows for deck 280 — into `Tournament` and `TournamentStanding` rows. Five services
and a job, all two levels deep like every other service here: `Tournaments::LimitlessResults`
(fetch + parse the results page), `Tournaments::LimitlessDecklist` (one decklist → the PTCG text
`Decks::Fetcher` already parses), `Tournaments::StandingsImportPlan` (reads, never writes),
`Tournaments::StandingsImporter` (writes), `Tournaments::StandingsImportUndo`, and
`Tournaments::LimitlessImportJob`. The design record is
`docs/superpowers/specs/2026-09-05-limitless-standings-import-design.md`; the decisions that are
not obvious from the code:

**The `/JR` and `/SR` suffix on an event's href is an age division, not a different event.**
`/tournaments/518`, `/tournaments/518/SR` and `/tournaments/518/JR` are the three halves of one
tournament, and the heading repeats the suffix in the name — so it is stripped, and the 176
headings collapse to 116 events (measured against the live page). Left in, every import would add
a permanent second public catalog row per division per event, which is the one mistake here no
later correction undoes cheaply. A suffix `DIVISION_BY_SUFFIX` does *not* know yields a **nil**
division and keeps its name suffix, so a third division surfaces as a refused row instead of being
filed as Masters.

**The archetype is the admin's declaration, and the tier and format are guesses shown before they
are written.** `archetype_id` is `NOT NULL` on a standing and a deck-results page *is* one
archetype, so the admin picks it once; nothing is detected and no archetype is created (detection
still tags the *deck*, never the standing). `tournaments.tier` defaults to `regional` in the
schema, which would file Worlds as a Regional and then hand a claimant 350 CP instead of 600
through `CP_REFERENCE` — so it is derived from the name by a pattern table and printed per event in
the preview. Limitless's `standard-jp` becomes format `other` with `other_format_name`
`"Standard (JP)"`: writing it as `standard` would force a western `StandardPool` onto a Japanese
event, the same lie a missing pool is refused for. (The decklists are safe either way — Limitless
normalises even a Champions League list to English set codes, so issue #111 does not bite here.)

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

**An existing standing is never rewritten, but a NULL `deck_id` is filled in** — a row naming an
archetype with no list is the common case, and attaching one overwrites nothing, so a run reports
*created*, *enriched* and *skipped* as three different numbers. Enrichment is recorded on its own
half of the receipt (`imports.enriched_standing_ids`) because undo treats the two oppositely: it
deletes the rows the run *made* and only takes the field list back off the rows it did not.
Without that split an enrich-only run was unundoable in both directions at once — the receipt was
empty, and `standing_params` does not permit `deck_id`, so the member whose row it was could not
detach the list either.

**The event lookup is `find_by || create!`, never `find_or_create_by`**, whose `name_normalized:`
key `before_validation :normalize_name` promptly overwrites with nil, failing validation and
returning an unpersisted record without raising. It rescues **`RecordInvalid` as well as
`RecordNotUnique`**, and the validation is the likely path: `name_and_date_are_unique` is a
non-atomic `exists?` that fires long before the UNIQUE index can, so a member cataloguing the event
between the preview and the write surfaces as `RecordInvalid` — rescuing only the index error
blocked every row of that event instead of reusing the row somebody else had just made.

**The preview is a GET and the job refuses a plan that has changed.** A POST that renders a body is
an error to Turbo ("Form responses must redirect"), and every render-a-body branch in this app is a
422 or JSON. The job re-fetches rather than trusting a plan carried through the browser, and the
confirm form carries the row count the admin saw: without that check, Limitless publishing an event
between the two clicks silently imports rows nobody approved. A run is capped (`max_rows:`, default
300 — a keyword so a test can prove the refusal with two rows) and gives up after five consecutive
*rows* lost to a transport failure. Per row and not per request, because a row makes up to sixteen
of them: the card pages are fifteen sixteenths of a run's traffic, so a rate limit that lets the
decklist page through and refuses those is still a run that has stopped working — and a counter
cleared by any one successful request would never reach five. A decklist that merely will not parse
is neither counted nor forgiven. The run records both halves of its receipt on the `Import`, and
**undo lives on `Admin::ImportsController#undo`**, beside the row it acts on: it destroys the
created rows nobody has claimed, takes the field list back off the enriched ones with
`update_column` (for the reason `#unclaim` uses it), keeps the claimed rows and says how many, and
leaves the events alone.
`Import::KINDS` gains `limitless_standings`, whose `tournament_id` stays nil because a run spans
many events, and `Admin::ImportsController#retry` became an allowlist (`deck`, `card_set`) rather
than a chain of refusals — its `case` has no `else`, so a new kind used to destroy the row and
enqueue nothing.

**`HttpFetcher` gained a `User-Agent` and real timeouts** (10 s connect, 30 s read, against
Net::HTTP's 60/60), and rescues timeouts and connection errors into `FetchError` — the class every
caller already handles, so `CardsController#image` still answers 502 rather than 500. It also
refuses a URI that is not `URI::HTTP`, the backstop behind the caller-side rule that a Limitless
deck id must match `/\A\d+\z/` before it is interpolated into a URL.

**Still out of scope, and worth knowing:** `play.limitlesstcg.com`'s online "best finishes" (they
are online-only tournaments with no age divisions, and cataloguing them would fill the public
`/tournaments` list with events no member attended); and attendance and W/L/T, which the results
page does not carry. Pagination of `tournaments#show`'s sheet *was* the prerequisite named here and
ships alongside this — see the paragraph on `SHEET_PER_PAGE` above. A sheet imported from one
archetype's page is still a *partial* sheet and nothing says so; that is a property it shares with
every hand-typed sheet, and marking one complete would mean knowing when it is.

**The archetype catalog and one archetype's metagame report** (`/archetypes`, `/archetypes/:id`)
are the aggregation the two sections above deferred, and they add **no column** — everything they
read already exists. Four services, all two levels deep: `Archetypes::MetagameScope` (which
standings count), `CardStats` (the deck report), `Performance` (the record), `IndexCounts` (the
listing's four numbers, in one grouped query). The design record is
`docs/superpowers/specs/2026-09-05-archetype-metagame-stats-design.md`; what is not obvious from
the code:

**Three things the page refuses to say, each measured rather than assumed**, because each is
something a later reader will be tempted to add. There is **no metagame share**: a sheet imported
from one archetype's Limitless page holds only that archetype's rows, so the database never sees
the field and cannot produce a fraction of it — every figure is worded *recorded in Cartodex*, and
the index's ordering is "most recorded", a statement about who has run an import. There is **no
win rate**: `Tournaments::StandingsImporter` never writes `wins`/`losses`/`ties`, and on the
production data exactly **1 of 94** standings carries a W-L-T, the one somebody typed. And there
is **no ACE SPEC category and no functional one** (Gust, Switch, Recovery): every ACE SPEC carries
`rarity` `"Ultra"` and so do 93 ordinary Trainers, the string "ACE SPEC" appears in `effect` on
**0 of 4720** cards, and what a card *does* is not scraped at all. The categories are exactly what
`card_type` plus the scraped `subtype` know — Pokémon, Supporter, Item, **Tool, Stadium**, Special
Energy, Basic Energy — plus an **`other` bucket that is rendered, not dropped**: it is unreachable
on today's catalogue and exists so a Trainer subtype the scraper learns tomorrow surfaces as a
labelled bucket instead of vanishing from a report that still sums to a plausible-looking 60. Tool
before Stadium, because that is the order `Decks::ShowView::TRAINER_SUBTYPE_LABELS` prints a
decklist in and a member reading both pages should not have to re-find the sections. Both
spellings of the tool bucket are mapped (`Cards::Fetcher#parse_subtype` can emit `"Pokémon Tool"`;
all 76 tools in the catalogue carry `"Tool"`) — a pair `TRAINER_SUBTYPE_LABELS` did **not** carry
until this feature. It knew `"Pokémon Tool"` alone, so all 76 of them fell under "Other" on every
deck page; the fix (both keys, and grouping on the label rather than on the raw subtype so one
deck holding both spellings gets one section instead of two identically titled ones) is a
pre-existing bug closed in passing here. `Decks::PublicShowView#trainer_section` still iterates
the raw pairs and would print two "Tool" headings for such a deck — the visitor's half of the same
fix, outstanding.

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

**A selector of one option is not a choice — and neither is one offering two labels for one
sample.** `MetagameScope::Result#selectable?` is what drops the control entirely
(`Archetypes::SampleSelector` renders no form when it is false), and it is deliberately **not**
`options.size > 1`: an archetype with standings in exactly one pool and nowhere else gets
"TEF-PBL — 4 lists" beside "All formats — 4 lists", two labels for the same four lists, and on the
production data that is the common shape rather than a corner case. It is
`pool_options > 1 || (pool_options == 1 && unpooled?)` — one pool *plus* a GLC or Expanded event
is a genuine choice, while an archetype whose every standing sits outside Standard has
"All formats" as its **only** option however many events that spans, so `unpooled?` cannot answer
on its own without rendering a `<select>` of one. `fuller_sample_available?` is the other half of
the same honesty: the notice under the selector promises a fuller sample one click away, and that
promise is false on the sample that is already the largest. `Result` carries no `standings_count`:
it had one, nothing but the styleguide's stub ever read it, and the rule is the one
`DeckPolicy::Scope` was removed under — the relation is there for a caller who wants the number.

**The report is keyed on `cards.fingerprint`, and one measurement shows both halves of why.**
Across those 93 lists there are **81 distinct card ids, 72 fingerprints and 70 names**: 81→72 is
the key folding nine reprints into the card they are, and 72→70 is the key *refusing* to fold —
**Hoothoot** is three genuinely different cards there (TEF 126 at 70 HP, PRE 77 at 80 HP, SCR 114
at 70 HP with other attacks) that a player picks between, and keying on the name would have read
"Hoothoot 100 %, 1-2 copies" and hidden the choice, the same conflation `Decks::ArchetypeDetector`
was moved off names to avoid. The key in the SQL is not the bare column but
`CardStats::GROUPING_KEY`, `COALESCE(cards.fingerprint, 'card:' || cards.id)`, and the difference
is not cosmetic: SQL gathers **every** NULL into one group, so `GROUP BY cards.fingerprint` folds
two unfingerprinted cards in one list into a single row whose copies are their sum and whose name
is whichever `MIN()` picked — a Supporter reported at 6 copies, the other card gone from a report
that still sums to a plausible 60, and nothing raised. `compute_fingerprint` is a `before_save`,
so only `update_column`, `insert_all` or a fixture can produce such a card; keeping it visible
under its own id is deliberate, since dropping it is the same silent disappearance in a different
costume — the state `Decks::ArchetypeDetector` refuses to match on and `Archetypes::FingerprintSync`
reports rather than writes. That grouping scatters Hoothoot's three rows in a table sorted by
inclusion, so rows are grouped by **name** inside a category and ordered by the share of lists
playing *any* version — and that share is a **distinct count of lists, never the sum of the
printings'**, computed as the **union of the entries' own list sets** rather than by looking a
name up in a second index: Hoothoot's three versions total 111.9 % across a name played by
73.1 %, because a list may play two of them. Taken from the entries the group holds, the number
above a set of sub-rows is a fact about those sub-rows by construction; keyed on a name the query
chose and read back by the name of the printing the report chose, the two halves could disagree,
and an unfingerprinted card showed a group at 0 % sitting above its own 100 % sub-row. The
printings inside a group are ordered by `set_number.to_i` before `.to_s`, because `set_number` is
a String holding a number most of the time and `"SV107"` the rest — sorted lexically, "114" comes
before "77". The page says so in words; presenting the sub-rows as an additive
decomposition is the one mistake this layout invites. Copies stay on the printing and never on the
name for the same reason — a "1-4" merged from two versions describes no list — and a split name
is never marked *fixed*, since which printing is still a choice. Quantities are summed per
`(deck, fingerprint)` **before** the histogram: two printings of one card in one list are two
legal `DeckCard` rows (`(deck_id, card_id)` is UNIQUE) and one card in that list; counted
separately the card appears in more lists than exist, each at a fraction of its copies, and
nothing raises. Measured occurrences in production: zero, because Limitless normalises what it
publishes — the step stays for the hand-typed lists, which are under no such discipline. A mode
tie is reported as a tie, never resolved in silence.

**One page prints "N lists" four times over, and the four are one number by construction.** The
sample selector, the card report's denominator, the performance panel and the index row each ask
a different service, so agreement is a property that has to be built rather than assumed, and two
things broke it. `CardStats#lists_count` used to be derived from the `deck_cards` rows, which is
"lists holding at least one card" and not "lists" — a field list that resolved no printing gave
the page two denominators and computed every percentage over the one it did not show; it is now
`@standings.distinct.count(:deck_id)`, the same question the other three ask. And all four count
**`COUNT(DISTINCT deck_id)`**, because `index_tournament_standings_on_deck_id` is not unique and
two standings legitimately point at one deck — two players registering the same 60 cards. A
single test builds both shapes at once and asserts the four numbers equal.

**The performance panel counts all standings; the card report counts only the listed ones**, which
is why `MetagameScope` exposes two relations rather than letting one number stand for both — a
placement is a result whether or not anybody typed the decklist. `unlisted_count` and
`unplaced_count` are the two gaps that follow, named on the page rather than left as subtractions:
`by_placement` has no band for "unknown", so its column sums to `placed_count` and not to
`standings_count`. Its placement bands are fixed
(1st, 2-4, 5-8, …) and deliberately **not** `Tournament::TOP_CUT_BANDS`, which maps an *attendance*
to a cut size for `TournamentEntry#top_cut_size`: telling whether a placement made the cut needs
the event's field size, and the importer writes none — all three `*_participant_count` columns are
nil on every imported event. `by_division` walks `TournamentStanding::DIVISIONS` because
`group(:division)` comes back alphabetical (junior, masters, senior) while players read junior,
senior, masters — the correction the standings sheet had to make in SQL for its page boundaries.

**Member-only, and opening the pages to visitors is seven edits, not three** — the list lives in
the comment atop `ArchetypesController` and was produced by applying the obvious three and reading
what broke *and what did not*. Three make the route reachable and are each covered by a test that
goes red without them: move the resource out of `authenticate :user`, `include PubliclyReachable`
with `publicly_reachable :index, :show`, flip `ArchetypePolicy` from `user.present?` to `true`.
**Four more decide what a visitor then sees, and no test would report any of them missing**: the
per-IP `rate_limit … unless: -> { user_signed_in? }` sized like `tournaments#index`'s 60/min
(deliberately absent now — no anonymous request can reach the route, so nothing could exercise it,
and a limiter nobody can exercise is a limiter nobody knows works); `nav_link "Archetypes"` in
`Ui::PublicNavbar`, without which a visitor on those pages lights **zero** navbar entries, a hole
`NavbarActiveSectionTest` cannot see because it names no visitor archetype page; dropping
`Search::Global#archetype_scope`'s `Archetype.none` branch, whose trap is the opposite kind — its
test keeps *passing* while defending a rule that has become false, so it has to be inverted in the
same commit; and the two archetype links a public page withholds today, `Tournaments::Standings::Row`'s
`if @viewer.present?` guard and `Decks::PublicBadges` (which passes no `href:` at all) — the
standings sheet and a shared deck are both public, and a link to a sign-in wall is worse than no
link, right up until the wall is gone. `Ui::ArchetypeBadge` gained the optional `href:` that all
three sites pass or withhold; `Search::Global`'s fifth group prefixes its option ids
`spotlight-option-archetype-` for the reason `shared_decks` had to. The two archetype rows in
`public_access_test.rb` move from `owner_only_gets` to `public_gets` that day, and three tests
asserting today's refusal turn round with them.

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
`ORDER BY` is something SQLite accepts — worth knowing against #62. `#show` costs **16 queries**,
and a flat-cost test in `ArchetypesControllerTest` holds it there — measured identical at 3 and at
10 lists in the test, and by hand at 93.

**No cache, and the threshold was written before the measurement.** On a synthetic 1500-list
archetype (39 000 `deck_cards` rows): `MetagameScope` 4 queries / 15.6 ms, `CardStats` 3 / 137.3 ms,
`Performance` 4 / 6.1 ms, `IndexCounts` 1 / 2.0 ms — ≈161 ms, and the count does
not move with the sample. `CardStats` is **4** queries since its `lists_count` stopped being
derived from the rows it had already fetched, so the total is thirteen; the added query is one
`COUNT(DISTINCT deck_id)` over one archetype's standings, served by
`index_tournament_standings_on_archetype_id`, and the timings above predate it. The honest version key for a cache entry would be a `MAX(updated_at)`
over the archetype's standings, the kind of unindexed aggregate `Card.filter_values` had to be
corrected away from. `CardStats` is 85 % of the cost and is where a cache would go if the
collection grows past roughly twice that size.

**Out of scope, deliberately:** cross-archetype comparison and any page spanning archetypes (it
would need a complete field, which no import produces), per-division card statistics (junior and
senior hold 3 and 2 of the 94 measured standings), matchup data, and exporting the report.

`StandardPool` is one period of the rotating Standard calendar: two `CardSet` bounds — the oldest legal set, moved by the annual rotation, and the newest, moved by every release — plus the legal `regulation_marks` and **two** dates. `(first_card_set_id, last_card_set_id)` is UNIQUE because that pair *is* the pool's name, `TEF-PBL`, which is what players call it. `released_on` says the cards exist and drives `StandardPool.current`, the anchor a new deck is pre-selected to; `legal_on` says Play! Pokémon considers the pool legal and drives `StandardPool.at(date)`, which is what a tournament asks — a set is tournament-legal about two weeks after it ships, so neither date derives from the other. `Deck` and `Tournament` each carry a `standard_pool_id`, required by validation when the format is `standard` and cleared otherwise (the `other_format_name` pattern): **only Standard rotates**, the other three formats are eternal and have no anchor. The anchor is **pinned** — nothing moves it automatically, and `Ui::StandardPoolNotice` merely invites the user to. `has_many :decks, dependent: :restrict_with_error`, unlike `Archetype`'s `:nullify`, because a NULL anchor on a Standard deck is unsavable on its next edit. Deck-construction rules are deliberately **not** here: see #61.

`db/seeds/standard_pools.rb` is a **bootstrap, not the source of truth**: pools are maintained from the admin panel, so the seed is keyed on the bound pair and **skips any row that already exists** rather than reasserting its values — otherwise every `db:seed` would silently revert an admin correction. Two of its values are not derivable and carry comments saying so: the `J` regulation mark starts at ASC, not MEG (the Mega Evolution block opens on `I` — *Mega Lucario ex* is MEG 77), and ASC's `legal_on` is 2026-03-06, five weeks after release rather than the usual two, because it shipped staggered and Play! Pokémon pushed legality past the 2026-02-13 EUIC. Re-deriving either with the two-week rule reintroduces a bug.

**Archetype identity is a fingerprint pair, not a card pair.** `primary_card_id`/`secondary_card_id` say which printing to *display*; `(primary_fingerprint, secondary_fingerprint)` is UNIQUE and says which archetype it *is* — two archetypes built from two printings of the same cards are duplicates, not siblings. A missing secondary is the **empty string, never NULL**: the previous `(primary_pokemon_id, secondary_pokemon_id)` index looked unique but SQLite treats NULLs as distinct, so duplicate single-member archetypes got through it for as long as it existed. Members may be **any** `card_type`, which is what lets a Trainer engine (Lost Zone Box, Mill/Stall) be an archetype at all. The denormalised columns back the index and **nothing else** — detection joins `cards` and reads the live fingerprint — which is what makes drift after a re-scrape harmless and lets `Archetypes::FingerprintSync` repair it out of band. `Archetype.search` spells its second join alias by hand (`secondary_cards_archetypes`), derived from the association name, so renaming that association breaks the scope at *query* time, not at load time.

**Allocation model** (collection as physically-owned inventory): `Collection.quantity` is the number of copies **owned** (source of truth; unique per user+card). `DeckCard.owned_copies` is how many of its copies are **real** (backed by owned cards); `quantity` is the total, `proxies = quantity − owned_copies` (unique per deck+card). Only decks with `physical == true` consume the collection. Invariant: `Σ owned_copies(card) over physical decks ≤ owned(card)` — exceeded only by a collection decrease, which is allowed and leaves a tolerated, surfaced over-allocation (never auto-corrected). Deck-level proxy state is **derived, never stored**: `Deck#has_proxies?` is `physical? &&` any `deck_card` with `owned_copies < quantity`, with `Deck.with_proxies` / `Deck.without_proxies` (over `DeckCard.with_proxies`) as the SQL counterpart backing the deck-list filter. The `physical` half is load-bearing on both sides — a non-physical deck's cards sit at `owned_copies 0` by construction, so the bare per-card test would match every TCG Live deck. The `decks.has_proxies` column and its form checkbox are gone (issue #56); because the badge now derives from data the deck page edits in place, every write in `Api::DeckCardsController` answers with a `deck: { has_proxies: }` key — including the card-removal case, which answers `{ removed: true }` instead of a body-less 204 — and the `deck-proxies` Stimulus controller toggles the badge, which the show header always renders (hidden when it does not apply). User has an `api_token_digest` (SHA-256 of a per-user MCP bearer token — see `User.authenticate_api_token` / `regenerate_api_token`).

**Controllers**: API endpoints under `Api::` namespace serve JSON (archetypes, cards, collections, decks with nested deck_cards and deck_results). `Api::DeckCardPrintingsController` (`GET …/cards/:card_id/printings`, `PATCH …/cards/:card_id/printing`) is separate from `Api::DeckCardsController` because that one identifies a row by its card id — the very thing a printing swap changes; the two share the deck lookup and the row JSON through the `DeckCardPayload` concern. Its swap response also carries what the page needs to rewrite the row in place: `merged`, `max_owned`, `over_allocated` and `image_path`. Admin panel under `Admin::` namespace covers dashboard, card sets (with import), cards (with rescrape), users (with toggle_admin), decks, archetypes (CRUD), standard pools (CRUD, no show page — a pool is five fields and the index shows all of them), and imports (list with error display, delete, retry). Top-level `tournament_profiles` and `deck_results` resources live alongside `decks`. `DeckResultsController` and `Api::DeckResultsController` both permit `tournament_entry_id` now, so a result can be attached to the participation it was played at. `Tournaments::EntriesController` routes under `resources :entries` — the URL reads `/tournaments/:tournament_id/entries/:id` — while the model is `TournamentEntry`, which is why its forms pass an explicit `url:`: polymorphic `form_with` would otherwise build `tournament_tournament_entries_path`, which does not exist. `Tournaments::StandingsController` is the same shape one level further: `resources :standings` under `tournaments`, no show and no index (the sheet lives inside `tournaments#show`, and a row is six fields), and forms that likewise pass an explicit `url:`. App routes require Devise authentication except the surface `PubliclyReachable` opens — `home#dashboard`, `search#show`, all of `resources :decks` (and, by nesting, its `deck_results` routes), all of `resources :cards`, and `tournaments#index`/`#show` (with `resources :tournaments` now carrying **two** nested resources out of `authenticate :user` by nesting alone — `entries` and `standings`, the same way `resources :decks` carries `deck_results`) — plus the always-unauthenticated `root`, `/up`, `/mcp` and the OAuth endpoints; each of the five `PubliclyReachable` controllers still calls `authorize` on every action, so "no session required" is not "no check performed". See **Shared decks** below.

**MCP server**: An MCP (Model Context Protocol) endpoint is mounted at `POST /mcp` (`Mcp::ServerController`, top-level route **outside** the Devise `authenticate` block), using the `mcp` gem's `StreamableHTTPTransport` (stateless). Auth accepts two bearer credentials, tried in that order: an OAuth 2.1 access token (`Doorkeeper::AccessToken.by_token`, gated on `#accessible?` which covers expiry and revocation together) and, as a fallback, the deprecated legacy per-user static token matched against `api_token_digest`. The bearer scheme is matched case-insensitively per RFC 7235. A resolved OAuth token also fires `revoke_previous_refresh_token!` (`rotate_refresh_token`): Doorkeeper rotates refresh tokens lazily and triggers that hook only from `doorkeeper_authorize!`, which this controller does not use, so without the call no refresh token would ever be retired. It retires the whole superseded row, access token included. Rotation bounds a *passively* leaked refresh token; it is **not** RFC 9700 reuse detection (deliberately not implemented — a replay is indistinguishable from a legitimate double refresh under the concurrency grace window), so the remedy against an attacker who actually redeems a stolen token is the user revoking the connection. Authentication is split into `identify_token_user` (resolves either credential into `@current_user` and `@current_scopes` — an Array of scope strings for OAuth, `nil` for the legacy token meaning full access — never halts) and `reject_unauthenticated!` (issues the 401) so that two rate limiters can sit between and after them: a per-IP one (`IP_RATE_LIMIT_TO`/min, `unless: -> { @current_user }`) that throttles anonymous token spam **before** the 401 without spending an authenticated client's budget, and a per-user work quota (`USER_RATE_LIMIT_TO`/min, keyed by `@current_user.id`) **after** it. Both are plain `before_action`s, so order is load-bearing; both pass an explicit `name:` so their cache keys stay distinct. The 401 challenges per RFC 9728 with a `WWW-Authenticate: Bearer resource_metadata="…/.well-known/oauth-protected-resource/mcp"` header, byte-identical whether the token was absent, unknown, expired or revoked. Legacy tokens carry an optional expiry (`api_token_expires_at`, `NULL` = never), rejected at `User.authenticate_api_token`, and record their last use at hourly granularity. Users manage the legacy token from `/settings` (`SettingsController`, `McpTokensController`); the generate action answers with a Turbo Stream so the raw value never passes through the session cookie. Tool classes live in `app/mcp/` — an autoloaded root, so they are **top-level constants** (e.g. `AddCardToDeckTool`, not namespaced), subclassing `McpTool` (shared helpers `current_user`/`find_deck!`/`find_card!`/`text`/`positive_quantity?` — `find_deck!(user, key)` is `user.decks.find_by!(key:)`, so every tool argument that names a deck is `deck_key:`/`from_deck_key:`/`to_deck_key:`, a string, never the numeric id; see **Shared decks** below). Read tools return JSON text, write tools return a summary string; both delegate to services and never hold business logic. Register a new tool by adding it to `Mcp::ServerController::TOOLS`. Tool names drop the `_tool` suffix of the class name. The eight+ tools cover collection/deck reads plus `add_card_to_collection`, `set_collection_quantity`, `add_card_to_deck`, `set_deck_card_owned_copies`, `reallocate_owned_copies`, `set_deck_card_quantity`, `set_deck_card_printing`, `list_over_allocations`, `suggest_owned_equivalents`, `list_printings`.

**OAuth 2.1 authorization server**: Doorkeeper 5.9.6 (`config/initializers/doorkeeper.rb`) makes Cartodex an OAuth 2.1 authorization server and RFC 9728 protected resource — this is the supported way to connect an MCP client; the static bearer token above is deprecated but still accepted. `grant_flows` is authorization_code-only, `force_pkce` is on (patched to also cover confidential clients, which DCR always produces — see the design spec for why this matters), `pkce_code_challenge_methods` is `%w[S256]` only, and scopes are `mcp:read` (default) / `mcp:write` (optional, refusable at consent), backstopped by `enforce_configured_scopes`. Clients self-register via RFC 7591 at `POST /oauth/register` (`Oauth::RegistrationsController` → `Oauth::ClientRegistrar`), gated by a redirect-URI host allowlist (`claude.ai`, `claude.com`, and the loopback hosts `localhost`/`127.0.0.1`, the only ones allowed plain HTTP) plus its own per-IP rate limit. Two discovery documents — `GET /.well-known/oauth-authorization-server` and `GET /.well-known/oauth-protected-resource(/mcp)` (`Oauth::MetadataController`) — are derived from the request host rather than `ENV["URL"]`, so they always describe the host the client actually called. Consent at `/oauth/authorize` (`Oauth::AuthorizationsController`, subclassing Doorkeeper's, with `layout -> { Layouts::ApplicationLayout }` so the page reads as Cartodex instead of falling through to the gem's own layout) renders a Phlex screen (`Oauth::ConsentView`) showing the client's self-declared name and redirect host, with `mcp:write` a refusable checkbox (`mcp:read` is checked and disabled, mirrored into a hidden field since a disabled checkbox never submits) and `narrow_scopes_to_consent` translating the checked boxes into the `scope` param Doorkeeper actually reads on the consent POST — the rendered form never posts a bare `scope` field, so without this step every consent would silently fall back to `default_scopes`. Those same two scopes gate which tools even reach `tools/list`: `McpTool.required_scope` defaults to `mcp:read`, the seven write tools declare `mcp:write`, and `McpTool.permitted_for` filters `Mcp::ServerController::TOOLS` against `@current_scopes` before `MCP::Server` is built — an out-of-scope tool is invisible rather than merely refused (a `nil` scope list, from the legacy token, keeps full access). `Oauth::ResourceIndicator`, shared by `/oauth/authorize` and `/oauth/token` through the `Oauth::ResourceIndicatorEnforcement` concern, validates an RFC 8707 `resource` parameter against the single canonical URI `<root>/mcp` when present, and accepts its absence — Cartodex has exactly one protected resource today. Users manage connected OAuth applications — grouped by application, union of scopes across **unrevoked** tokens, a revoke button — at `/settings` (`Settings::ConnectedAppsSection`, `ConnectedAppsController`), alongside the legacy token section. "Connected" is `revoked_at: nil` on both sides, deliberately not `#accessible?`: an expired access token still carries a live refresh token, so filtering by expiry would hide working connections from the only revocation control there is. The **"connected since" date does not come from tokens** — rotation revokes the superseded token row, so the oldest live token is only as old as the last refresh; it is the newest `AccessGrant` (revoked or not — Doorkeeper revokes grants on redemption) at or before the oldest unrevoked token, falling back to that token when no grant exists. `#destroy` revokes the application's outstanding `AccessGrant`s too, so an unredeemed authorization code cannot resurrect a revoked connection. `Oauth::PurgeStaleApplicationsJob`, scheduled daily in production (`config/recurring.yml`), deletes applications registered more than 7 days ago that were never authorized (no access grant or token), bounding growth from open registration. See the design spec at `docs/superpowers/specs/2026-08-14-mcp-oauth-authorization-design.md` for the reasoning behind the trickier choices (PKCE on confidential clients, the redirect-host allowlist, no HTTP 403 step-up).

**Shared decks — deck identity.** A `Deck` is addressed by its `key`, not `decks.id`, everywhere the address crosses a boundary of the app: the URL segment, JSON, an MCP tool argument, a Stimulus value. `decks.id` stays the primary key and the target of every foreign key, so a `<select>` of decks (the tournament entry form) and an internal write param (`over_allocations#reallocate`'s `from_deck_id`/`to_deck_id`) still carry the integer — those reference a row, not a page. `Deck::KEY_BYTES = 16` (`SecureRandom.urlsafe_base64(16)`, 22 URL-safe characters, 128 bits) is assigned by `assign_key`, wired as `before_validation :assign_key, if: -> { key.blank? }` — `before_validation` rather than `before_create` so the callback and the `presence` validation agree, and the `key.blank?` guard both stops an update from rewriting the key and heals a row a callback-bypassing insert left keyless. There is no uniqueness validation — the UNIQUE index on `key` is the guarantee, the same division of labour as `(set_name, set_number)` on `Card`. `Deck#to_param` returns the key, which is why 35 of the app's `deck_path`/`deck_url` call sites needed no edit to start emitting it; two sites the helper cannot reach on its own needed one anyway — `over_allocations/index_view.rb`'s `deck_path(d[:key])`, fed by `Allocations::PhysicalDecksByCard` now plucking `decks.key` alongside `decks.id` (kept, since the reallocation form's `<select>`s still need the row), and `/decks/compare?ids[]=…`, whose `DecksController#compare` maps `params[:ids]` to strings, looks up `Deck.where(key: ids)`, and re-sorts by `ids.index(deck.key)`.

**Where the unscoped lookup lives.** This feature creates exactly one unscoped deck lookup in the whole app: `Deck.find_by!(key: params[:id])` in `DecksController#show` and `#export`, immediately followed by `authorize` — nothing else runs first. Every other lookup stays scoped by association and only changed which column it keys on: `current_user.decks.find_by!(key: …)` in the rest of `DecksController`, in `DeckResultsController`, `Api::DecksController`, the `DeckCardPayload` concern, and `McpTool#find_deck!`. `Admin::DecksController` is the one pre-existing exception — already unscoped, because an admin panel lists everybody's decks, gated by `Admin::BaseController#require_admin!` rather than by anything below.

**`decks.shared`** is a boolean, `NOT NULL`, `default: false`, with hand-written `shared`/`unshared` scopes: Active Record's `dangerous_class_method?` refuses to generate a `public`/`private` enum or scope, since both are `Module` methods, so the column, the scopes, the Share modal and the badge all settle on `shared`/`unshared` instead. Existing decks come out of the migration private. `Decks::Duplicator` builds a copy from an explicit attribute allowlist, so `shared` — like any future column — is excluded from a duplicate by construction; a copy of a shared deck is never itself shared.

**`PubliclyReachable`** ties three things together that must not come apart: it `skip_before_action :authenticate_user!` for the actions named, it makes `verify_authorized` an `after_action` mandatory on **every** action of the including controller, and it `rescue_from`s both `ActiveRecord::RecordNotFound` and `Pundit::NotAuthorizedError` onto one `not_found` renderer, so an unknown key and a private deck answer identically. `DecksController` overrides that renderer: a request with **no session** is sent to sign-in instead of the static 404 — still one answer for "unknown key" and "not yours", so still no existence oracle, but not a dead end for the owner whose session expired while their own bookmark still points at the deck. A **signed-in** request keeps the 404, since sign-in has nothing to offer someone already signed in. `CardsController` deliberately does not do this: nothing in the catalog is private, so a missing card is a missing card. `TournamentsController` is the second includer to override the concern's handling, for the opposite reason: an event's existence is not a secret, it is *listed* at `/tournaments`, so hiding a refused edit behind the shared 404 would conceal nothing and give the member nowhere to go. It leaves the module's `not_found` alone and instead declares its own `rescue_from Pundit::NotAuthorizedError, with: :refuse_with_redirect` after the `include`, which redirects to the event with an alert when the refusal carries an `:id` and to the catalog when it does not — four of the eight actions carry none, and a redirect helper that assumed one would answer a refusal with an `UrlGenerationError` 500; `rescue_from` matches in reverse declaration order, so this later handler wins over the concern's shared one for that one exception, while `ActiveRecord::RecordNotFound` is untouched and still renders the static 404 — an unknown id and a real event you may not edit still answer differently, because what must stay hidden for a deck may stay visible for an event. `HomeController` (`dashboard`), `SearchController` (`show`), `DecksController` (`show`, `export`, `shared`), `CardsController` (`index`, `show`, `image`) and `TournamentsController` (`index`, `show`) include it — the five route entries that left the app-wide `authenticate :user` block, and `resources :decks` and `resources :tournaments` each carry a nested resource's routes out with them as a side effect of nesting alone: `deck_results` under `decks`, `entries` **and `standings`** under `tournaments`. `DeckResultsController` is the deliberate exception: its routes ride out by nesting, but it does **not** include the concern, keeps `authenticate_user!` as its only gate, and gets no `verify_authorized` — it still calls `authorize @deck, :results?` after `current_user.decks.find_by!(key: …)`, but nothing enforces that call being present. `Tournaments::EntriesController` is a second deliberate exception of the same kind: its routes ride out by nesting under `tournaments` alone, it too keeps `authenticate_user!` as its only gate and gets no `verify_authorized` — every action does call `authorize`, but, as with `DeckResultsController`, nothing enforces that it must. `Tournaments::StandingsController` is a third: same nesting, same `authenticate_user!`-only gate, same absent `verify_authorized`, and it carries its own `rescue_from Pundit::NotAuthorizedError` for the one action in the app — `#unclaim` — where a signed-in member can hit a real Pundit refusal that nothing else here rescues. The blind spot the concern's own comment names: a halting `before_action` skips the remaining callbacks *and* the `after_action`, so on a signed-out request to an owner-only action, `authenticate_user!` redirects before `verify_authorized` ever runs — a missing `authorize` on `edit`/`update`/`destroy`/`duplicate`/`stats`/`share` is invisible to a signed-out request. `test/controllers/public_access_test.rb` covers the gap by making the same request signed in, per action rather than per controller, since an over-broad `skip_before_action` is exactly the bug being guarded against.

**The policies say yes to a nil user, and no admin ever wins by fiat.** `ApplicationPolicy` is written by hand rather than generated: `current_user` is `nil` on every public page, and Pundit's generator template sometimes `raise`s on a nil user, which would make the whole public surface impossible. `DeckPolicy#show?`/`#export?` is `owner? || record.shared?`; every write, plus `stats?`, `tournament_pdf?` and `results?`, stays `owner?` (a nil user owns nothing, so a visitor fails every one of them); `shared_index?` is unconditionally `true`, since `/decks/shared` is one page for a visitor and a member alike. The deck-sharing confidentiality boundary never yields to an admin shortcut: no `DeckPolicy` query checks `user.admin?`, and an admin who wants to read a private deck goes through `Admin::DecksController`'s own gate and its own unscoped lookup, not through the deck's normal URL — a policy shortcut can never quietly widen what the boundary allows. `TournamentPolicy` is the one policy in the app that reads `admin?`, and it does not break this rule: nothing about an event is hidden — it is listed at `/tournaments` — so an admin correcting a catalog entry gains no read they did not already have, and moderating it widens no confidentiality boundary the way a deck-policy shortcut would. `TournamentEntryPolicy` is the case that would matter, and it grants an admin nothing: a participation stays `owner?`, full stop. There is **no `DeckPolicy::Scope`**: the spec asked for one ("the decks I may see"), it was built, and it was removed because nothing in `app/` called it — `/decks` is the owner's own decks, `/decks/shared` is `Deck.shared`, and the spotlight wants those two as separate result groups rather than as their union, so a policy object kept alive by its own test would only drift. `ApplicationPolicy::Scope` stays as the contract the next one starts from. `CardPolicy` (`index?`, `show?`, `image?`), `DashboardPolicy#show?` and `TournamentPolicy#index?`/`#show?` all answer `true` unconditionally — not ceremony, but the written trace of "the card catalog, the dashboard and the event catalog are public", and what stops `verify_authorized` from having a blind spot over those three controllers. The response to an unauthorized or unknown deck is **404, never 403**: a 403 would say "this key names a real deck, you may not see it", turning a scan of random keys into an existence oracle for private decks — and existence is exactly what has to stay hidden, since a shared deck isn't a secret link, it is *listed* at `/decks/shared`. 404 for "private" and 404 for "not found" are indistinguishable on purpose — and for a request with no session, where both become the same redirect to sign-in, they still are (see `PubliclyReachable` above).

**Public views are separate files, not a flag.** `Decks::PublicShowView` and `Decks::PublicDeckCardItem` contain none of the owner's affordances (inline editing, allocation steppers, printing picker, result logging, the actions dropdown…), so unlike a conditional sprinkled through `Decks::ShowView` this view *cannot* leak what it does not contain. `Decks::DeckCard#public_listing:` is one keyword switching off three things together — the owner's `ClassificationBadges`, the foil "hot deck" flag (which prints the win rate, a record decision keeps private), and the compare checkbox (whose controller a public page never loads) — because they are one decision, and the next caller cannot get one of them wrong by passing only two of three. What the two views legitimately share is extracted rather than copied: `Ui::CardPreview` and `Ui::CardPreviewModal` (two components, not one, because `Decks::CompareView` places the pane inside `.deck-compare-content` and the dialog outside it, and because `card_preview_controller.js` reads five targets across them), `Decks::ExportDropdown` (`tournament_pdf: false` by default — the owner's fifth item reads one of their profiles), and `Ui::FilterSelect` for the two deck listings' filter bars, which `Cards::IndexView` deliberately does not use since it styles its selects `.cards-search-select`. `deck_image_export_controller.js` reads four DOM hooks that both the owner's and the public card rows must keep: the `.deck-card-item` class, the `data-card-preview-url` attribute, a `.deck-card-qty` element, and an `h1` inside `.deck-show-header` (which names the downloaded file) — lose any one and the export silently produces an empty image rather than erroring.

**The Share control is two components, not one.** `Decks::ShareModal` renders the `<dialog>`; `Decks::ShareFrame`, inside it, is the only thing `PATCH /decks/:key/share` re-renders, via Turbo Stream. They stay separate because a stream that replaced the dialog would render a second, closed `<dialog>` nested inside the open one, which goes blank — only the frame may be swapped. The toggle is a real checkbox preceded by a hidden `input[name=shared][value=0]`: an unchecked bare checkbox posts nothing at all, `ActiveModel::Type::Boolean.new.cast(nil)` is `nil`, and `shared` is `NOT NULL` — the hidden field is what a bare checkbox needs, and what the form builder's `check_box` would have added for free. The write is `update_column`, not `update!`: `update!` rejoins `validates :standard_pool, presence:, if: :standard?`, so a Standard deck whose anchor is still NULL (a row from before that column, or an environment that skipped `standard_pools:backfill_anchors`) could be neither shared nor unshared — the toggle has no business asking whether the rest of the record is valid, and nothing caches on the deck's `updated_at`. The action answers through `respond_to`, because `share` has only a `.turbo_stream.erb` behind it and an unbranched `Accept: text/html` request would raise `MissingTemplate` *after* the flag had committed.

**Nothing is indexable, anywhere, for now.** `XRobotsTagMiddleware` (`app/middleware/`), inserted at position 0 of the stack by `config/application.rb` — `require_relative`'d there rather than referenced by name, since Zeitwerk's autoloader does not exist yet when that line runs — sets `x-robots-tag: noindex, nofollow` with `||=` on every response the app emits (the key is spelled lowercase: a controller's `Rack::Headers` is case-insensitive, but `Rack::Files`, the routing 404 and `HostAuthorization`'s 403 answer with a plain `Hash`, where any other spelling is both a Rack 3 SPEC violation and an `||=` that cannot see a directive already set): controller actions, Warden's own sign-in redirect (`Devise::FailureApp` subclasses `ActionController::Metal` directly, so a `before_action` or `config.action_dispatch.default_headers` — reaching only what mixes in `ActionController::DefaultHeaders` — would both miss it), `rate_limit`'s 429, any `ActionController::API` controller, the static 404, even a host-authorization 403. `Layouts::ApplicationLayout` carries the matching `<meta name="robots">` for what has a `<head>`, but the header is what also covers the JSON API and the image proxy, neither of which has one. `public/robots.txt` stays deliberately permissive — no `Disallow`, with a comment saying so — because a path a crawler may not fetch is a path whose `noindex` it never reads, and a URL somebody linked from outside can still surface as a bare result regardless; the way to keep something out of search results is to let the crawler in and hand it the directive, not to block the crawl.

**All three navbars go through `Ui::NavbarShell`**, the admin one included. The shell exists for the test suite as much as for looks: below 768px `.navbar-menu` is `display: none` until the `navbar` Stimulus controller adds `.navbar-menu--open`, and `click_nav_link` drives exactly that — so a navbar missing the toggle fails every mobile system test that navigates while looking like a Capybara visibility bug. `Ui::AdminNavbar` was the last one carrying its own copy of that markup, and therefore the only one that would not pick up a fix made in the shell; it now passes `brand_label:` and `nav_class:`, the two things that actually differed. Moving it was invisible to the suite until `test/system/admin_navigation_test.rb` existed, since nothing had ever visited the admin panel through its navbar. `nav_link` lives in `Ui::NavLinks`, a module rather than a method on the shell: the shell takes its links as a block, and a block is evaluated in the *caller's* context. **What lights an entry is a nav section, not a controller name.** `Ui::NavLinks.section_for(controller_name, action_name)` resolves a request to exactly one section, keyed on `(controller_name, action_name)` through a `SECTION_OVERRIDES` table rather than the controller name alone: `decks#shared` becomes `"shared_decks"` because `DecksController` serves both deck lists, and `tournaments#mine` becomes `"my_tournaments"` for the same reason — `TournamentsController` serves both the public catalog and the member's own entries. Every other route falls through to its controller name unchanged, and `nav_link` takes the sections that light it, so "one entry is lit" holds by construction rather than by two independent rules agreeing. Keying on `controller_name` alone is what used to light "Decks" and "Shared decks" together on every deck page. A link declaring **two** sections is the visitor's navbar: it has no "Decks" entry, so its "Shared decks" link is what a shared deck's own page must light, while the member's navbar splits the same pages between its two entries. `test/controllers/navbar_active_section_test.rb` asserts the count as well as the label, per page and per navbar — a rule that lights two entries and a rule that lights none fail it differently.

**`RateLimitStore`** (`app/lib/rate_limit_store.rb`) is a top-level constant rather than one on `ApplicationController`, because `Mcp::ServerController` inherits `ActionController::API` and could not reach a constant nested there; it proxies to `Rails.cache` at call time, not captured at class load, so tests can swap in a real store. Six `rate_limit`s back this feature, all per-IP and `unless: -> { user_signed_in? }` so an authenticated user never spends a visitor's budget: `SearchController` at 120/min, `CardsController#index` at 60/min, `CardsController#image` at 300/min, `DecksController#shared` at 60/min, `DecksController#export` at 30/min, and `TournamentsController#index` at 60/min — each sized for what its endpoint actually amplifies rather than copied from `Mcp::ServerController`'s 30/min, since the image proxy caches no bytes server-side and one deck's image export is up to 60 parallel requests to it (a deck holds at most 60 cards), so 300/min leaves five exports a minute per IP. `#shared` gets `#index`'s 60 because it is the same shape — a field debounced at 300 ms driving a paginated listing — and `#export` gets 30 because nothing fires it automatically (it is a click on a dropdown item; the image export goes to the proxy, not here) while each request preloads a whole deck's `deck_cards → card → attacks/abilities`. `TournamentsController#index` gets the same 60 as `#shared`, for the same reason: the tournament catalog is the identical shape, a debounced field driving a paginated listing behind a Turbo Frame. That parity is only true because `tournaments.date` is indexed (`20260904083908`) — `#index` orders by it and the `(name_normalized, date)` UNIQUE key has the wrong leading column to serve that sort, so before the index every anonymous request sorted the whole table and 60/min would have rationed an amplifier instead of removing it, which is precisely what the `/cards` story below says not to do. The `LIKE '%…%'` search stays a scan either way. Unlike `#shared` it carries no `return if …frame_request?` short-circuit, and needs none: nothing renders or queries outside its frame, so a frame request and a plain one cost the same. `DecksController#show` and `TournamentsController#show` get none: one page load per click, no live control behind it. `/decks/shared` was likewise made cheap before it got a limiter: its filter form now targets a Turbo Frame (`Decks::SharedIndexView::FRAME_ID`, the same short-circuit `#index` has had), so a keystroke pays the pager's COUNT and the page of rows rather than the archetype-options query and the whole surrounding page — 9 queries down to 7, and no layout render at all. Its pager links sit inside that frame and therefore carry `data-turbo-action="replace"`, or the frame would swap while the address bar stayed on page 1; the deck rows escape it the other way, through `Decks::DeckCard`'s own `data-turbo-frame="_top"`. Both listings load their page with `.to_a`, because the view asks `any?` before iterating and on an unloaded relation that is a `SELECT 1 … LIMIT 1` beside the query about to run anyway; `HomeController`'s showcase does the same. `/cards` was made cheap *before* it got a limiter: `CardsController#index` used to `includes(:cards)` the entire catalog just to print a per-set count in the sidebar, now a grouped `Card.group(:card_set_id).count`, and its two `rarity`/`regulation_mark` filter-value scans (neither column is indexed) moved to `Card.filter_values`, behind `Rails.cache.fetch` on a fixed key with a one-hour TTL, invalidated by `Card.forget_filter_values` from the only two things that can add a value — `CardSets::Importer` and `CardSets::RescrapeJob` (a `force: true` rescrape is the only thing that rewrites an existing card's text). It was keyed on `Card.maximum(:updated_at)`, which is itself an unindexed full-table aggregate: a scan on every request, spent protecting an entry nothing ever invalidated — rate-limiting an endpoint that still scanned the whole catalog three times would have rationed an amplifier instead of removing it.

**`Search::Global` takes `user: nil`.** A visitor's deck scope becomes `Deck.none` and never touches the database, but the tournament scope does not follow it: the catalog is public, so `tournament_scope` runs `Tournament.name_matching(@query)` unconditionally. Only `deck_scope` skips the database for a visitor — cards (`apply_card_name_filter(Card.all, …)`), shared decks (`Deck.shared`) and tournaments all query. The fourth group, `shared_decks`, is `Deck.shared` excluding the searcher's own (`where.not(user: @user) if @user`) so a member's own shared deck never appears in both the "my decks" and "shared decks" groups of one result list. Its DOM ids are prefixed `spotlight-option-shared-deck-` rather than `spotlight-option-deck-` for the same reason: `Search::ResultsList` derives option ids from `deck.id`, and one deck rendered under two groups would otherwise emit the same id twice and break the spotlight's keyboard navigation.

**Deferred to #142, out of scope here:** author attribution on a shared deck, any public view of a deck's results or stats or of a collection (the tournament catalog and an event's page are public as of #148 — a member's *participation* in one is not), copying someone else's shared deck, comments/likes/counters, sitemap and Open Graph metadata, revoking a link once it has been shared, an MCP tool that shares or unshares a deck, and server-side byte caching for the image proxy (which would make its rate limiter unnecessary rather than merely bearable).

**Frontend**: Hotwire (Turbo + Stimulus), Propshaft asset pipeline, importmap for JS. **All views use Phlex components** — see the `phlex-architecture` skill for conventions and patterns. Always use Phlex, never write view logic in ERB.

**Design system**: A single CSS-custom-property token system lives at the top of `app/assets/stylesheets/application.css` (neutrals, brand `--flare`, a per-energy-type palette, semantic result colours, elevation, and `--font-*` roles), with three override layers at the bottom of the file (base typography/dark navbar; energy-typed badges + holo treatment; the deck row's narrow-screen rules). Those layers are all single-class specificity, and a media query adds none — so a responsive rule that has to beat one of them says so in its selector (the last layer is scoped to `.deck-card-list`) rather than relying on sitting later in the file, which the next layer appended below would silently undo. Self-hosted fonts (Archivo / IBM Plex Sans / IBM Plex Mono) are in `app/assets/fonts`. `Card::TYPE_TOKENS` maps each energy type to its colour token — use it (not literal hexes) when colouring by type. A living reference renders the real tokens and components at **`/styleguide`** (`Styleguide::PageView`, non-production only); update it when adding components or tokens.

**Global search.** `Search::Spotlight` is reachable from every page, and a page carries **exactly one** of it — `Search::ResultsView::FRAME_ID` is a DOM id and Turbo resolves a frame by id, so a second spotlight would swallow the first one's results. `Ui::SearchTrigger` (a magnifier plus the ⌘K hint) is rendered by `Ui::NavbarShell` **outside `.navbar-menu`**, because below 768px that menu is `display: none` until the hamburger opens it and a search you must unfold a menu to reach is not reachable from anywhere; CSS `order`, not DOM order, puts it right of the links above the breakpoint. Where the page has no field of its own the trigger opens `Search::Overlay`, a `<dialog>` wrapping the same component; on the dashboard and the styleguide, which render one inline, `SearchOverlayHost#search_overlay?` suppresses the dialog and the trigger focuses the field already there. That concern is included by `ApplicationController` **and** by `Oauth::AuthorizationsController` — `Layouts::ApplicationLayout` has two hosts, and a layout helper missing on the second is a 500 on the consent screen alone. The `search-overlay` Stimulus controller sits on `<body>` (the trigger is in the navbar, the field is elsewhere) and owns ⌘K / `/` outright: `dashboard-search` no longer binds them, since the shortcut may have a dialog to unfold first. Esc is handled on the dialog rather than left to its native cancel — the field's own Esc handler calls `preventDefault`, which kills it; the event still bubbles, so one press empties the query and closes the overlay. The admin panel is out: `Layouts::AdminLayout` renders neither the overlay nor the controller, so `Ui::AdminNavbar` passes `search: false`.

Four details keep the trigger and the field from working against each other, each with a system test behind it. The trigger carries **`data-search-surface`**, which `dashboard-search#clickOutside` treats as inside the search: that watcher sits on the document, so the click that opens the search reaches it *after* `open()` ran, and collapsing there dismissed the panel the click had just restored — leaving the arrows and Enter dead until the query text changed. The dialog's padding lives on a **`.search-overlay-content` wrapper**, because a click reported against the dialog element is precisely how `clickBackdrop` recognises a click outside the panel, so padding on the dialog itself made the visible ring around the field a dismiss zone. **`turbo:before-cache` closes it**: the overlay's usual exit is a result that navigates away, and a snapshot cached with an open `<dialog>` restores it *non-modal* — no backdrop to click, and `open()` reads it as already open, so nothing on the page can dismiss it again. And only the trigger takes the navbar's free space: **`.navbar-right`'s `margin-left: auto` is zeroed when a trigger precedes it** (the admin navbar, which has none, keeps it), since two auto margins split that space and park the magnifier mid-navbar — the same construct the mobile block fixes for the hamburger. The **⌘K hint is written by the controller on connect**, never by the template: `shortcut()` takes Ctrl+K just as readily, only the client knows which key this keyboard has, and it writes `hintTargets` rather than the first one because the styleguide renders the shipped trigger beside the navbar's own.

`Ui::CardSelect` (Stimulus `card-select`) is the card autocomplete behind all three archetype pickers — the admin form, `Ui::ArchetypePicker` and the deck result modal. `Ui::ArchetypePicker` used to be `Decks::ArchetypeField`, soldered to a deck (it read `@deck.key` for the Suggest button and `@deck.archetype&.name` for the input's value); it now lives under `Ui::` and takes an **optional** `deck_key:`, because the tournament standings form renders the same picker for a row that has an archetype and no deck. `deck_key: nil` renders no Suggest button — the only thing here a deck is needed for — and the `archetype-picker` Stimulus controller already tolerates the missing value, since `deckKey` is declared as a String value and Stimulus defaults an absent one to `""`. It searches **every** card type and never deduplicates results by name: which printing an archetype designates is the user's choice, so collapsing them would hide every option but the first. The endpoint behind it (`Api::CardsController`) caps how many printings of one name may take its 20 slots (`PRINTINGS_PER_NAME`), ranked newest-first over the whole match rather than over a fetched prefix — otherwise a heavily reprinted card fills the list and a differently named card is unreachable whatever the user types; the older printings are reached by naming the set, which the query parser already understands. All three pickers fill their input with `Card#printing_label` ("Name (SET NUMBER)"), the same label the admin form pre-fills, because a bare name does not say which printing the hidden id now holds.

`Ui::StandardPoolNotice` tells a user their deck or tournament is anchored to a Standard pool other than the expected one, and is **informative only** — the anchor is pinned by design and nothing moves it automatically. It lives under `Ui::` because both the deck and tournament forms render it, and **no string it emits may name a record type or mention a date**: a deck has no date, and a tournament's mismatch can run in either direction (its anchor may be older *or* newer than the pool its date calls for). The `expected` pool it is handed differs by caller — `StandardPool.current` for a deck, `StandardPool.at(date)` for a tournament — because those are different questions: a deck's mismatch is staleness, a tournament's is a data-entry error.

## Bin Scripts

- `bin/import_deck DECK_NAME [FILE]` — import decklist from file or stdin, fetches card data from web
- `bin/export_decks` — interactive JSON deck export
- `bin/export_deck_ptcg` — export deck in PTCG text format
- `bin/rails 'mcp:token[email@example.com,90d]'` — rotate and print a user's MCP bearer token (shown once; only the digest is stored). Lifetime is `30d`/`90d`/`1y`/`never`, default `90d`. Deprecated: this static token still works, but OAuth 2.1 via Doorkeeper (see MCP server, above) is the supported way to connect a client.
- `bin/rails standard_pools:backfill_anchors` — anchor Standard decks and tournaments that predate the `standard_pool_id` column. Run **after** `db:seed`, which creates the pools it needs; idempotent.

## Test Setup

Minitest with parallel execution. Fixtures in `test/fixtures/`. System tests use Capybara/Selenium/headless Chrome and live in `test/system/`; they sign in through `Warden::Test::Helpers` (`login_as user, scope: :user`) because the user fixtures store a literal string in `encrypted_password`, so no password would ever authenticate. `ApplicationSystemTestCase` turns `allow_forgery_protection` **on** for the duration of each system test: the test environment disables it, `csrf_meta_tags` then renders nothing, and `requestJson` reads `.content` off a null meta tag — every browser-driven write dies in its `catch` and reports "the request didn't reach the server". Request tests keep the relaxed setting.

**The system suite runs twice, once on each side of the app's single 768px breakpoint**, and the rule is that **every system test is expected to pass on both**. `SYSTEM_TEST_VIEWPORT` picks the side — unset (the default, and what `bin/rails test:system` gives you locally) is desktop at 1400×1400, `mobile` is 390×844; CI has a job per side (`test` and `system_test_mobile`), and `viewport_sweep_test.rb` is the guard that the selected side actually reached the browser. The breakpoint is checked in **JS** (`card_preview_controller.js`, `window.innerWidth <= 768`) as well as in CSS, so "mobile" is not a styling concern that can be assumed cosmetic: below it the card preview stops being a hover pane and becomes a full-screen `<dialog>` whose backdrop eats subsequent clicks.

Two consequences for writing one:

- **Navigation differs.** Below the breakpoint `.navbar-menu` is `display: none` until the hamburger toggles `.navbar-menu--open` onto it, and Capybara will not click what it cannot see. Never click a nav link directly — use `click_nav_link`, which is a plain click above the breakpoint and opens the menu below it (and retries, because the toggle click and the link click straddle a Turbo page swap).
- **A test that asserts about a *width* rather than about a *side* must pin it**, with `drive_at width, height`. **Chrome will not give a window narrower than 500px** — not through `screen_size:`, not through `--window-size`, not through `resize_to` (all three measured) — so the mobile half of the sweep really renders at 500, and a bug that breaks at 344 but not at 500 is invisible to it (exactly #99's). `drive_at` overrides the viewport through CDP, which escapes that floor, clears it on teardown because the browser is shared by the whole run, and skips the half of the sweep its width does not belong to. It is Chrome-driver-only: runs against the devcontainer's remote Selenium skip with a reason.

Passing at both widths is the **floor, not the ceiling**. It stops a test from silently only ever exercising the desktop side; it does not assert anything about mobile-specific behaviour. A test that clicks once and then only asserts will pass below the breakpoint with the preview modal open over the page, since Capybara still considers inert content visible. Mobile-only behaviour needs its own assertions, which is what `card_preview_modal_test.rb` is: the `<dialog>` the preview becomes below the breakpoint, what it shows, and what closes it. The hover pane it replaces above the breakpoint (`card-preview#show`) is still untested.
