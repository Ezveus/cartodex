# Standard is a rotating format: a deck records which Standard — Design

Issue: #122 (parent of the format/legality cluster: #27, #61, #125)

## Goal

`decks.format` says `standard` and stops there, but Standard is a rotating format: the name alone does not identify a card pool. A deck — and a tournament — must record **which Standard** it belongs to, and the forms must let the user pick it.

Players already name these pools by their two bounds: the oldest legal set and the newest, `TEF-PBL` today, `TEF-CRI` before it, `SVI-ASC` before the 2026 rotation. That convention is the model.

## Scope

**In:** the pool model, its seeded history, the anchor on `Deck` and `Tournament`, the form field, the label, the "a newer pool exists" nudge, admin CRUD for pools, and the `CardSets::Importer` fix that any date-driven rule depends on.

**Out:** reading the pool for anything. No legality checking, no card-search filtering, no deck-size or copy-limit enforcement. The pool carries the regulation marks so that #27, #61 and #125 can read them without remodelling; this change never reads them itself.

## Confirmed decisions (from the brainstorming interview)

1. **The anchor is pinned and mandatory, never automatic.** A deck built under `TEF-CRI` stays `TEF-CRI` when `TEF-PBL` arrives. Nothing moves it but the user.
2. **Editing a deck whose anchor is stale shows an invitation to update it.** Informational only — no field is written without a click.
3. **Only Standard rotates.** GLC, Expanded and Other are eternal formats and are untouched by this work. They have no anchor, and one left behind by a format change is cleared.
4. **`Tournament` gets an explicit anchor too**, pre-filled from its `date` but editable — a tournament is played under the format legal on its date, which is not the same as "the newest set exists".
5. **A pool is named by its two bounds**, and the upper bound is a single set. When two sets release the same day, follow Limitless's naming: the 2025-07-18 pool is `SVI-BLK`, not `SVI-BLK/WHT`.
6. **Two dates per pool.** `released_on` (the cards exist) drives `current`, i.e. what a new deck is pre-anchored to; `legal_on` (Play! Pokémon tournament legality) drives `at(date)`, i.e. what a tournament on a given day was played under.
7. **Backfill:** tournaments by their `date`; decks onto the current pool.
8. **The numeric construction limits stay out of the database.** Deck size, max-copies, the GLC singleton rule and the basic-energy exception go in a Ruby constant keyed by the existing `format` enum, the day #61 decides hard-block vs advisory. This change does not introduce them.

   Scoped deliberately to the *numeric* limits. A per-format **banlist** is data with a lifecycle — cards get banned mid-season — and belongs in a table, not a constant; so does a per-format block floor if it is ever edited without a deploy. Neither is in this change, and the requirements for both are recorded on #61 rather than here.

9. **Pools are maintained from the admin panel**, not only by the seed. A pool is created roughly every seven weeks — 18 pool-creating events between SVI and PBL, over 40 months — and without an admin screen each one needs a code change, a deploy and a `db:seed` on production before anyone can anchor a deck to the current Standard. The admin panel already imports the set itself, so the flow would break exactly in the middle.

## Facts established before designing (measured, not assumed)

- **`CardSets::Importer#find_or_create_set` never writes `release_date`** — only `code`, `name`, `logo_url`. Every set imported from the admin panel therefore has a NULL release date, and a pool referencing it would have no usable date. This is a prerequisite, not a side quest.
- **The seed's set list has holes.** It jumps PAL (2023-06-09) → TEF (2024-03-22), so OBF, MEW, PAR and PAF are absent, and it stops at CRI (2026-05-22), so PBL is absent.
- **`card_sets` has no `regulation_mark` column** — the mark lives on `cards`. Deriving a pool's lower bound from the legal marks would need a query over cards, and would be wrong for a set whose cards are not imported yet. Both bounds stay explicit FKs.
- **`Tournament` duplicates `Deck`'s format surface verbatim**: the same enum, the same `other_format_name`, the same `clear_inapplicable_classification`, and `FORMAT_LABELS = Deck::FORMAT_LABELS`. It also has a mandatory `date`.
- **The rotation does not split a set cycle.** POR released 2026-03-27 and became tournament-legal ~2026-04-10, the exact day the 2026 rotation took effect — which is why `SVI-POR` never existed. Play! Pokémon aligns set legality with the rotation date, so a pool is created by one event, not two overlapping ones.
- **The blast radius is not small, and the first count of it was wrong.** A grep for `Deck.create` / `Deck.new` found 6 call sites in the test suite; the real figure was **106 across 25 files**, plus 8 more in `test/system/` and 8 for `Tournament`. The shapes the grep missed are `user.decks.create`, `update!` on a fixture, and — the one that reached production code — `.decks.build`, which is how both `DecksController` and `Api::DecksController` create a deck. Fixtures themselves are inserted without validation and so never fail on a conditional presence rule; every explicit construction does. Anyone adding a conditional presence validation to a model this widely constructed should count `build` and association-proxy shapes before estimating.
- **Sourced external facts**, since re-verified line by line by the maintainer and corrected on two counts: PBL released 2026-07-17; the 2026 rotation makes H, I and J legal and took effect 2026-04-10 in person, 2026-03-26 on TCG Live; a new set is tournament-legal roughly two weeks after release. The corrections were that **the `J` mark starts at ASC, not at MEG** — the Mega Evolution block opens on `I`, *Mega Lucario ex* being MEG 77 — and that **ASC's legality is 2026-03-06**, five weeks after release rather than two, because it shipped staggered and Play! Pokémon pushed it past the 2026-02-13 EUIC. Both are recorded in `db/seeds/standard_pools.rb` with the reasoning, because the two-week rule would silently "correct" either one back to a wrong value.

## Data model

### `standard_pools`

One row per period of the Standard calendar.

| column | notes |
|---|---|
| `first_card_set_id` | FK `card_sets`, NOT NULL — lower bound, set by the rotation |
| `last_card_set_id` | FK `card_sets`, NOT NULL — upper bound, set by the newest release |
| `regulation_marks` | `json`, NOT NULL, e.g. `["H","I","J"]` |
| `released_on` | date, NOT NULL — when the pool's cards exist |
| `legal_on` | date, NOT NULL — when the pool is legal in Play! Pokémon events |

Unique index on `(first_card_set_id, last_card_set_id)`: that pair *is* the pool's name, and two rows must not claim it.

```ruby
belongs_to :first_card_set, class_name: "CardSet"
belongs_to :last_card_set,  class_name: "CardSet"
has_many :decks,       dependent: :restrict_with_error
has_many :tournaments, dependent: :restrict_with_error

def name = "#{first_card_set.code}-#{last_card_set.code}"   # "TEF-PBL"

def self.current      = where(released_on: ..Date.current).order(released_on: :desc).first
def self.at(date)     = where(legal_on: ..date).order(legal_on: :desc).first
```

`restrict_with_error` rather than the `:nullify` that `Archetype has_many :decks` uses, and the difference is not stylistic: an archetype is a tag, so dropping it is harmless, whereas a NULL anchor on a Standard deck is unsavable on its next edit. A referenced pool is corrected, never deleted.

Two design points worth stating, because both look like redundancy:

**Neither date is derivable, which is why both are columns.** A pool born from a set release has `released_on` equal to that set's release date; a pool born from a rotation with no new set keeps the previous pool's upper bound, and only the rotation date says when it changed. And `legal_on` is a Play! Pokémon decision (release + ~2 weeks, or the announced rotation date), derivable from nothing in the schema.

**`current` filters on `released_on <= today` rather than taking the newest row.** The moment a pool for an announced-but-unreleased set is seeded, it must not become the default anchor for new decks before its date.

The `legal_on` / `released_on` split also leaves room for the in-person vs TCG Live divergence (2026-04-10 vs 2026-03-26) without remodelling. This change does not model that divergence; `legal_on` holds the in-person date.

### The anchor on `Deck` and `Tournament`

Each gets `standard_pool_id`, nullable in the database and required by validation — the `other_format_name` pattern exactly:

```ruby
belongs_to :standard_pool, optional: true
validates :standard_pool, presence: true, if: :standard?

# in clear_inapplicable_classification:
self.standard_pool_id = nil unless standard?
```

Clearing is what makes the eternal formats genuinely eternal: switching a deck to GLC drops the anchor rather than keeping a Standard pool nobody can see.

Three existing paths the validation would otherwise break, and which land in the same change:

- **`Decks::Fetcher`** calls `Deck.create!(user:, name:)`, so `format` takes the `"standard"` column default and the user is never asked. It anchors the imported deck to `StandardPool.current`. This is the silent assumption #125 flags; it becomes explicit and visible in the edit form instead of invisible.
- **`Decks::Duplicator`** copies `other_format_name` and would silently drop the anchor. A duplicate of a `TEF-CRI` deck stays `TEF-CRI`.
- **`Tournament`** pre-fills `StandardPool.at(date)` when the date is known, `current` otherwise.

## Data and seeding

**`CardSets::Importer`** learns to parse the set's release date from the Limitless page and assigns it with the same `||=` guard as `name` and `logo_url`, so a hand-seeded date is never overwritten by a scrape.

**Missing sets** are added to `db/seeds/card_sets.rb`: OBF, MEW, PAR, PAF and PBL (2026-07-17).

**Pool history** is seeded from the 2025 rotation forward. Earlier rotations have a Sword & Shield lower bound, and no Sword & Shield set exists in `card_sets`, so those pools are not expressible — seeding them would mean inventing set rows to hang them off. The seed is shaped so that a new pool is one more line, never a migration.

The row set is derived mechanically rather than curated, so that "did we miss a pool?" has an answer: **one pool per pool-creating event, from the 2025 rotation onward** — every set release moves the upper bound, every rotation moves the lower bound. Two sets released the same day are one event and one pool, named per the Limitless convention (which also covers the energy subsets: SVI/SVE, MEG/MEE). A rotation that falls on a set's legality date, as 2026's did, is likewise one pool, not two.

`legal_on` uses the officially announced date, per set. It is usually the second Friday after the US release, but it is **not a formula**, which is why it is stored rather than computed: *Ascended Heroes* shipped staggered — its ETB only arrived 2026-02-20 — so Play! Pokémon pushed its legality to 2026-03-06, five weeks after release and past the 2026-02-13 EUIC. Derived, `at(2026-02-13)` would have claimed ASC was legal at a tournament where it was not.

Promo sets are out of this model on purpose: their legality is per-card, not per-set, and a promo enters a pool through its regulation mark like any other card. They are never a pool bound.

**The seed data is the one place in this change where an error is silent.** The per-set release dates, the per-rotation legal marks and every `legal_on` will be sourced and submitted for review before the seed is committed.

## Backfill

Both tables are backfilled in the same change, since the validation makes an unanchored Standard record unsavable through any form.

**The backfill is a rake task, not part of the migration** — `bin/rails standard_pools:backfill_anchors`, behind `StandardPools::AnchorBackfill`, on the `archetypes:resync_fingerprints` precedent. A migration cannot do it: the pools it needs come from `db/seeds`, which runs *after* `db:migrate`, so a migration would find an empty table. The deploy order on an existing database is therefore `db:migrate` → `db:seed` → `standard_pools:backfill_anchors`, and the task is idempotent so a corrected seed can be re-applied.

- **Tournaments** take `StandardPool.at(date)` — the date is real and the answer is exact.
- **Decks** take `StandardPool.current`. `created_at` is not the date a deck was built (importing an old decklist today stamps today), so anchoring on it would fabricate a precision the column does not have. The current pool is visibly wrong for an old deck rather than plausibly wrong, and the stale-anchor nudge is what invites the user to fix it.
- **Rows whose format is not Standard** are left NULL, which is what `clear_inapplicable_classification` would do anyway.
- A tournament whose `date` predates the oldest seeded pool gets `nil` from `at(date)`; it falls back to the oldest pool rather than staying NULL, because NULL is unsavable on the next edit.

## Forms, display, API

**The field.** `Decks::ClassificationFields` gains a conditional `standard_pool_id` select, twin of `other_format_field`: options are `StandardPool` ordered by `released_on` descending, labelled by `#name`. The `deck-classification` Stimulus controller today toggles exactly one field (`toggleOther`); it becomes a `toggle` driving both targets rather than growing a second near-copy.

Pre-selection is `StandardPool.current` for a new record and the record's own pool on edit, so the mandatory field costs the common case nothing.

**The stale-anchor nudge**, rendered server-side in the same component, only for a persisted record whose anchor is not the expected pool — never on a creation form, where it would be meaningless:

> This deck is anchored to **TEF-CRI**. **TEF-PBL** has released since — update it if you still play this deck.

For a tournament the comparison is against `StandardPool.at(date)`, not `current`: a March 2026 tournament anchored to `TEF-PBL` is a data-entry error, not a deck to refresh.

**Label.** `Deck#format_label` (and `Tournament#format_label`) returns `"Standard (TEF-PBL)"` when an anchor is present and `"Standard"` when it is not. One method changes and the deck badge, deck list, search results and tournament view follow with no edit.

**Strong params.** `:standard_pool_id` joins the `permit` lists in `decks_controller` and `tournaments_controller`.

**MCP.** `ListDecksTool` returns `format: "standard"` — the ambiguity this issue exists to remove. It gains `standard_pool: deck.standard_pool&.name`.

## Admin panel

`resources :standard_pools` under `namespace :admin`, full CRUD, following the `resources :archetypes` precedent — a small reference table maintained by hand — plus an entry in `Ui::AdminNavbar` beside "Archetypes".

**The form pre-fills everything that does not change.** A set release moves only the upper bound, so `first_card_set_id` and `regulation_marks` come from `StandardPool.current` and `legal_on` is proposed as `released_on + 14 days`. What is left to type is the new set and its release date — exactly the part a human knows and the schema does not. The annual rotation is the one case where the lower bound and the marks are touched, and it is the one case worth typing in full.

**The index** lists pools by `released_on` descending: name, marks, both dates, which one is current, and the number of decks and tournaments anchored to each. The count is what makes a deletion attempt legible before it is refused.

**Consequence: the seed becomes a bootstrap, not the source of truth.** It stays idempotent on the natural key `(first_card_set_id, last_card_set_id)`, which the unique index already guarantees, so re-running it after admin edits neither duplicates nor overwrites.

**Not added:** a "create the pool" action on the card-set import page. The pre-filled form covers the same need without a second path to maintain.

## Out of scope

- Legality checking of any kind, including the card-search filter in the deck builder (#27) and deck size / copy limits (#61, #125).
- A pool filter on `/decks`; the format filter is unchanged.
- A `regulation_mark` column on `card_sets` — the need for it was considered and dropped.
- Modelling the TCG Live vs in-person rotation dates separately.
- The JSON, Cardmarket and PDF exports, none of which currently emit the format.

## Known seams

- **`StandardPool.current` returning nil** on a database with no pools makes every Standard deck unsavable. Seeds are part of setup, so a fresh deploy that skips them fails loudly rather than quietly — and with the admin screen the fix no longer needs a deploy. Acceptable, and worth an explicit test.
- **The pool history stops at the 2025 rotation.** A deck genuinely built under a 2024 Standard cannot be anchored truthfully; it will be backfilled onto the current pool like every other existing deck.
- **The upper-bound convention is a judgement call** on a double release, inherited from Limitless. A future double release asks the same question again; the seed comment records the rule so the answer is not re-derived.
- **`Tournament`'s anchor is not kept in sync with its `date`.** Change the date after saving and the anchor stays; the nudge surfaces the mismatch rather than fixing it.

- **Between a set's release and its legality date, `current` and `at(Date.current)` disagree** — about two weeks a year. `current` already names the new pool, so a new deck is pre-anchored to a Standard that is not yet legal in an event, which is right for building and wrong for the tournament three days away. `current` is a pre-selection the user can change and `at(date)` is exact for tournaments, so this is a recorded imprecision, not a bug. Found while deriving the seed table, not while designing.

## Testing

- **Model:** `#name`; `current` ignoring a pool whose `released_on` is in the future; `at(date)` on `legal_on`; the conditional presence validation and the clearing of the anchor on a format change — on `Deck` **and** `Tournament`.
- **Services:** `Decks::Duplicator` preserves the anchor; `Decks::Fetcher` anchors to `current`; `CardSets::Importer` fills `release_date` and does not overwrite a seeded one.
- **Admin:** the pool CRUD requires an admin (the `Admin::BaseController` guard); the new form pre-fills the lower bound and marks from the current pool; deleting a referenced pool is refused and says so, rather than nulling an anchor.
- **System:** picking a pool when creating a deck and seeing it in the badge; the nudge present on a deck anchored to an older pool. Both viewports, as the repo requires.
- **Backfill:** `StandardPools::AnchorBackfill` is a service, so it is tested like one — tournaments by `at(date)`, decks on `current`, non-Standard rows left alone, an event older than the whole history falling back to the oldest pool, idempotency, and the empty-database case reporting rather than writing. Moving the backfill out of the migration is what makes this testable at all.

  One run only real rows can exercise is **still outstanding**: the worktree the backfill was built in has an empty development database (seeded pools, no users, no decks, no tournaments), so `standard_pools:backfill_anchors` there reported `0/0` — vacuous, not a verification. The substitute was a rolled-back run over the fixtures, which anchored 2 decks and 2 tournaments. Running the task against real rows, after `db:seed`, in the main checkout, is the maintainer's step and has not happened.
- Every new test is verified by breaking the implementation first — a test that has never been red proves nothing.
