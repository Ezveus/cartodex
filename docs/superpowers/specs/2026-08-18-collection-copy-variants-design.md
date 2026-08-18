# Copy-Distinguishing Attributes: Language & Finish — Design

**Date:** 2026-08-18
**Status:** Approved
**Issue:** #89 (which merged #58, foil-aware allocation)
**Spawned:** #111 (Japanese set import), #112 (Cardmarket export grammar)

## Goal

Let the collection record what a copy physically **is** — its language and its finish — so that
"3 English Poké Ball and 1 French" and "2 standard and 1 reverse holo" become expressible for a
single printing. Ownership is the only thing this serves: allocation, decks and exports are
deliberately untouched.

## Vocabulary

- **Printing** — one exact card as `Card` already models it: a set plus a collector number. Unchanged.
- **Copy** — one physical card the user holds. Several copies of the same printing may differ.
- **Variant** — the `(language, finish)` pair that distinguishes copies of one printing.
- **Region** — the print run a `CardSet` belongs to (`international`, `japan`, …). Decides which
  languages that set's printings exist in.
- **Rarity** — a property of the *printing*, already in `cards.rarity`. Not a variant.
- **Attribute** — a property of the *copy*. Language and finish are attributes.

The rarity/attribute split is Cardmarket's own, stated on its Pokémon listing page: "Listing
regular holofoil cards (**a rarity**) and reverse holo (**an attribute**) is the most common mistake
sellers make on Cardmarket." It is the rule this whole design turns on.

## Confirmed decisions (from the brainstorming interview)

1. **Language and finish are properties of the ownable** — a `collections` row. Not of the printing,
   not of the deck slot.
2. **Which languages are possible is a property of the set.** A copy's language must be one the
   set's region is actually printed in.
3. **A French, Japanese or reverse-holo copy satisfies a deck slot backed by real copies.**
   Allocation stays variant-blind. (Level C of #89 — a variant-aware deck slot — is rejected.)
4. **The collection breaks a printing down by variant.** `UNIQUE (user_id, card_id)` widens.
   (Level B of #89.)
5. **A deck slot never expresses a variant preference.** `deck_cards` is untouched.
6. **The variant is optional, via a non-NULL `"unknown"` sentinel.** A user who does not care keeps
   exactly one row per printing, as today; rows are split only where it matters.
7. **`finish` supersedes `collections.foil`,** which is dropped in the same migration. #89 required
   that dead column to be given a meaning or removed.
8. **`finish` carries no `holo` value.** Holo is a rarity and already lives on `cards`.
9. **The vocabularies are Ruby constants, validated, not database enums.** New reverse patterns ship
   every set; a typo must still be refused.
10. **Nothing about the Cardmarket export changes** — its grammar cannot carry either attribute
    (see Out of scope).

## Data model

### `card_sets`

```ruby
add_column :card_sets, :region, :string, null: false, default: "international"

remove_index :card_sets, :code
add_index :card_sets, [ :region, :code ], unique: true
```

Every existing row is international by construction: that is the Limitless tree
`CardSets::Importer` scrapes. The default therefore asserts nothing false.

The index widens because Limitless disambiguates its two trees **by path, not by code** —
`/cards/SVI` against `/cards/jp/M6` — and codes do collide (`XY7` is a Japanese set; the XY era has
international codes too). Kept global, the first Japanese import would die on an incomprehensible
uniqueness error. Two lines now, strictly equivalent while only international sets exist.

```ruby
class CardSet < ApplicationRecord
  REGION_LANGUAGES = {
    "international" => %w[en fr de es it pt],
    "japan"         => %w[ja],
    "korea"         => %w[ko],
    "taiwan"        => %w[zh-Hant],
    "china"         => %w[zh-Hans],
    "thailand"      => %w[th],
    "indonesia"     => %w[id]
  }.freeze

  validates :region, inclusion: { in: REGION_LANGUAGES.keys }

  def allowed_languages = REGION_LANGUAGES.fetch(region)
end
```

The region is the fact; the languages are derived. No per-set `allowed_languages` column to
maintain. A set that predates its region's Portuguese printings is a refinement a personal
inventory does not need; if it ever does, it is a per-set override, not a redesign.

**Why the set decides.** The western six share the international numbering — a French Base Set card
really is `10/102`. Every other region has its own set releases: Korea and Traditional Chinese
follow Japanese structure on international release dates, Simplified Chinese diverges in card
*design* (exclusive logo embossment, altered holo effects), Thailand has had sets available nowhere
else, Indonesia has its own releases. Recording `ja` against a western collector number would
assert a printing that does not exist.

### `collections`

```ruby
add_column :collections, :language, :string, null: false, default: "unknown"
add_column :collections, :finish,   :string, null: false, default: "unknown"
remove_column :collections, :foil, :boolean

remove_index :collections, [ :user_id, :card_id ]
add_index :collections, [ :user_id, :card_id, :language, :finish ],
          unique: true, name: "index_collections_on_user_card_and_variant"
```

Order is load-bearing: the columns arrive before the index, and because existing rows are already
unique on `(user_id, card_id)`, adding two constant columns leaves them unique — the migration
cannot fail on real data.

`null: false` is not cosmetic. SQLite treats two `NULL`s as distinct in a unique index, so with
nullable columns `(user, card, NULL, NULL)` would insert twice and the uniqueness would protect
nothing. The sentinel holds the invariant, not the index alone.

```ruby
class Collection < ApplicationRecord
  LANGUAGES = (%w[unknown] + CardSet::REGION_LANGUAGES.values.flatten).freeze
  FINISHES  = %w[unknown standard reverse_holo poke_ball_reverse master_ball_reverse].freeze

  validates :finish, inclusion: { in: FINISHES }
  validate  :language_allowed_by_set
  validates :user_id, uniqueness: { scope: [ :card_id, :language, :finish ],
                                    message: "already has this printing in this variant" }

  private

  # The set decides which languages exist for its printings: a Japanese copy cannot hang off a
  # western collector number, because that printing does not exist under that number. When the card
  # has no set — Card belongs_to :card_set is optional — nothing narrows the union.
  def language_allowed_by_set
    return if language == "unknown"

    allowed = card&.card_set&.allowed_languages || LANGUAGES
    errors.add(:language, "is not printed for this set") unless allowed.include?(language)
  end
end
```

`standard` means "the copy as its rarity defines it" — non-holo for a Common, holo for a Holo Rare.
Named that way rather than `normal`, which would wrongly suggest non-holo. A Holo Rare is
`rarity: holo` + `finish: standard`; a `finish` that repeated the rarity would let two columns
contradict each other about the same card.

The reverse patterns are real and multiplying: Prismatic Evolutions ships three reverse series
(108 standard, 100 Poké Ball, 67 Master Ball), Terastal Festival ex introduced Master Ball with
textured etching, Ascended Heroes adds further styles. Hence a validated Ruby constant: adding the
next pattern is one line, no migration. Validated rather than free-form because a typo would fork a
row in silence and make the user believe they own 1 + 1 instead of 2 — the exact failure this
feature exists to remove.

`finish` is **not** region-scoped, unlike `language`: the reverse patterns originate in Japanese
sets and reach international ones, so every region offers the full list.

Consequence, and a healthy one: for the six non-international regions `language` has exactly one
legal value. The model therefore *demonstrates* that the western six are the only genuine
multi-language case, instead of hardcoding it — and a Japanese copy becomes recordable the day a
Japanese set exists (#111).

## Operations

### Writes that change

`Collections::CardAdder` and `Collections::QuantitySetter` take `language:` and `finish:`, both
defaulting to `"unknown"`, and key their `find_or_initialize_by` on `(card, language, finish)`.
Every current caller — the webcam scan, the card page's `+`, `AddCardToCollectionTool` — keeps
working untouched. Their existing tests must pass **unmodified**; if any needs touching, the default
is wrong.

### `Collections::VariantMover` (new)

The split operation: "one of these four is French".

```ruby
Result = Struct.new(:source, :target, :merged, :source_removed, keyword_init: true)

def initialize(user:, card:, from_language:, from_finish:, to_language:, to_finish:, quantity:)
```

Guards mirror `Decks::OwnedCopiesReallocator`: `ArgumentError` for a non-positive quantity, for
identical source and target variants, and for a source that holds fewer copies than asked. Inside
one `serialized_transaction`: `find_by!` the source, `find_or_initialize_by` the target, increment
the target, then destroy the source if it hits zero or decrement it otherwise.

**Why one service and not `QuantitySetter` + `CardAdder`.** Those two writes would dip the owned
total between them, and since `Σ owned_copies(card) ≤ owned(card)` is *surfaced* rather than
enforced, a concurrent reader would see an over-allocation that never existed.

**Why the target uses `find_or_initialize_by` where `OwnedCopiesReallocator` uses `find_by!`.**
Splitting a variant off is precisely the case where the target row does not exist yet.

**Why a `Result` rather than the pair.** After the transaction nothing in the database says whether
the target pre-existed or was just created, nor that the source is gone — the same reason
`Decks::PrintingSwapper` returns one. Both facts are decided inside the transaction.

The source row is destroyed at zero rather than kept at `quantity: 0` as `QuantitySetter` leaves
it. The asymmetry is deliberate: an empty variant row records nothing, while occupying a slot in the
unique index and a tile in the grid to say "zero French copies", which absence already says.

### Reads that must change

Four places conflate "one collection row" with "one card". They are imprecise today and wrong once
a printing can have variants:

- **`Collections::OwnedEquivalents`** maps one entry per row with `owned: collection.quantity`, so a
  printing owned in two variants is listed twice, each claiming a fraction. Group by `card_id` and
  sum before building entries. #89 asks what "owned" means once a printing has variants; the answer
  is the total, as everywhere else.
- **`ListCollectionTool`** emits one entry per row but fills `owned:` from
  `availability[card_id].owned` — the card total, repeated on every row. It gains per-row `quantity`,
  `language` and `finish`, keeping `owned`/`committed`/`available` at card level.
- **`CardsController#show`** reads `collections.find_by(card_id:)&.quantity` as though it were the
  total. It becomes `@collection_rows` plus `@collection_quantity = @collection_rows.sum(&:quantity)`
  — the rows themselves are needed for the button rule below.
- **`Api::CollectionsController#update`/`#destroy`** identify a row by `card_id`, which no longer
  identifies one. See the API section.

### Reads verified unchanged

`Allocations::Availability` and `Allocations::OverAllocations` already do
`group(:card_id).sum(:quantity)`, so they sum across variants with **zero changes** — the allocation
model needs no work at all. `CollectionsController#index` and `ListCollectionTool`'s scope
legitimately want one row per variant; that is the point.

Untouched deck-side: `Allocations::Backing`, `Allocations::PhysicalDecksByCard`, `Cards::Printings`,
`Decks::PrintingSwapper`, `Decks::CardAdder`, `Decks::OwnedCopiesSetter`,
`Decks::OwnedCopiesReallocator`, `Decks::DeckCardQuantitySetter`, `deck_cards`, both exporters, the
tournament PDF.

## JSON API

`/api/collections/:id` takes the meaning it should always have had: **the row's own id**, not a
`card_id`. `create` carries `card_id, quantity, language, finish` and stays an upsert per variant.
The only consumer is `collection_quantity_controller.js`.

`collection_json` gains `language` and `finish`. It already carries both `quantity` (the row) and
`owned` (the card total); they are equal today and will now diverge, so the variant has to be in the
response for the divergence to read as intentional rather than as a bug.

The move gets its own controller, following `deck_card_printings`:

```ruby
resources :collections, only: [ :index, :create, :update, :destroy ] do
  # Moving copies between variants converts two rows and can destroy one, so it is not an update of
  # the row it starts from — the same reason the deck-card printing swap has its own action.
  resource :variant, only: [ :update ], controller: "collection_variants"
end
```

`PATCH /api/collections/:collection_id/variant` → `Api::CollectionVariantsController`, answering
with what the page needs to rewrite both tiles in place: `merged`, `source_removed`, the source's
remaining quantity (`0` when it was removed — the key is always present, so the client never has to
distinguish absent from zero), and the target's id, quantity and variant. Errors follow the shape
`Api::DeckCardPrintingsController` already uses: `ArgumentError` →
`{ errors: [ e.message ] }` with `:unprocessable_entity`, `ActiveRecord::RecordNotFound` →
`:not_found`.

## Web UI (Phlex)

**Collection page.** One tile per variant. Each tile carries
`collection_quantity_collection_id_value`, a variant badge rendered only when the variant is not
`unknown/unknown`, and a split control: quantity, target language, target finish. The language
options come from `collection.card.card_set&.allowed_languages` — this is where the region model
pays off: an international card offers six languages, a Japanese card offers one and the control
collapses to finish alone.

**Card page.** The `+`/`−` buttons need a rule, because a total spread over several variants gives
`−` no non-arbitrary target:

- no row at all → `+` creates the `unknown` variant;
- exactly one variant, whatever it is → the page operates on it;
- more than one → `−` and remove are replaced by a link to the collection page.

The common case, and always the case for a fresh collection, keeps the buttons live.

`collection_quantity_controller.js` gains `collectionIdValue` alongside `cardIdValue`, and retains
the `id` returned by the create POST, which it currently discards — without it the first `−` after
a `+` would have no row to target.

Badge and split control go into `/styleguide`, which CLAUDE.md requires be kept current.

## MCP tools

`AddCardToCollectionTool` and `SetCollectionQuantityTool` gain optional `language` and `finish`,
with `Collection::LANGUAGES` / `FINISHES` as `enum` in the `input_schema`. The schema cannot express
the regional rule — it depends on the card's set — so the model validation carries it, surfaced by
the `rescue ActiveRecord::RecordInvalid` already in both tools. The message therefore matters: "is
not printed for this set" has to be enough for a client that cannot see the database.

`MoveCollectionVariantTool` (new, `required_scope "mcp:write"`) wraps `Collections::VariantMover`
and is added to `Mcp::ServerController::TOOLS`, exposed as `move_collection_variant`.

`SuggestOwnedEquivalentsTool` inherits the `OwnedEquivalents` grouping fix and changes nothing
itself.

## Testing

Two database-level tests assert choices rather than behaviour, and are the reason those choices are
safe:

- two rows `(user, card, "unknown", "unknown")` must be **rejected**, which pins the widened index.
  It does **not** pin `null: false`, contrary to what an earlier draft of this spec said: the row it
  inserts takes the column default, so it stays green with both columns nullable. The sentinel needs
  its own test — a NULL written past the validations, expecting `ActiveRecord::NotNullViolation` —
  because SQLite treats two NULLs as distinct in a unique index and would let
  `(user, card, NULL, NULL)` insert twice.
- two `CardSet`s sharing a `code` in different regions must **coexist**, and be rejected within the
  same region.

Model: `finish` inclusion; `language` accepted/refused per the card's set (international takes `fr`,
refuses `ja`; japan takes `ja`, refuses `fr`); `unknown` always accepted; a card with no set falls
back to the union. `CardSet#allowed_languages` and `region` inclusion.

Services: `CardAdder`/`QuantitySetter` defaulting to `unknown` and keying on a given variant, with
their existing tests unmodified. `VariantMover` on the happy path, merging into a pre-existing target
(`merged`), the source destroyed at zero (`source_removed`), insufficient quantity and identical
variants raising, and — the point of the service — the owned total unchanged across the move.
`OwnedEquivalents` returning one entry per printing, with the summed total, when owned in two
variants.

Requests: `create` with a variant; `update`/`destroy` by row id; `collection_json` carrying the
variant; `Api::CollectionVariantsController` on the move, the merge and both error mappings.

System, at **both viewports**: splitting a printing from the grid, both tiles appearing, the total
unmoved; and the card page's counter becoming a link once several variants exist. Navigation through
`click_nav_link`, never a direct click. Note that `ApplicationSystemTestCase` enables forgery
protection, so the new JSON endpoint must be reached with a CSRF token or every browser-driven write
dies in `requestJson`'s `catch`.

Every one of these is to be seen **red** before the implementation that turns it green: a test
prescribed by a plan and never observed failing proves nothing.

Fixtures: `test/fixtures/collections.yml` loses its four `foil:` keys and gains one row in a real
variant, placed on a `(user, card)` couple no existing test asserts totals for — a second row on an
asserted couple would shift numbers elsewhere. If a test moves anyway it gets fixed, not
worked around.

## Implementation staging

This is one feature but more than one plan's worth of work, and the repo has a precedent for
splitting it: the allocation model shipped as `2026-07-02-collection-deck-allocation-design.md`
followed by `2026-07-03-allocation-ui-api-design.md`. The same three stages apply here, in order,
each independently shippable and green:

1. **Migration, models, services.** Both migrations, `CardSet`, `Collection`, the two writers,
   `VariantMover`, the `OwnedEquivalents` fix. Nothing user-visible changes; every existing test
   still passes.
2. **API and UI.** The `:id` semantics change, `Api::CollectionVariantsController`,
   `collection_json`, the Stimulus controller, the collection tiles, the card-page button rule, the
   styleguide entries.
3. **MCP.** The two writers' new parameters, the `ListCollectionTool` fix,
   `MoveCollectionVariantTool`.

Stage 1 carries the whole correctness argument, so it is where the sabotage-verified tests matter
most. Stages 2 and 3 are surfacing.

## Out of scope

- **Importing Japanese or other regional sets.** The `region` column exists; no scraper fills it.
  Filed as #111, and reachable — `limitlesstcg.com/cards/jp/<CODE>`. Korean, Chinese, Thai and
  Indonesian have no Limitless data at all and stay unreachable regardless.
- **The Cardmarket export, unchanged and deliberately.** `AddDeckList` accepts one grammar,
  `[quantity[x]] <product name> [(V.n)] [(Expansion)]`, documented across Cardmarket's per-game help
  pages. Neither language nor finish appears in it; an annotated line would be rejected, not
  enriched. Both attributes are set on Cardmarket after the paste, per entry or via Bulk
  Modification. The genuine gap the research found in that exporter — no `(Expansion)`, and a bare
  `V1` suffix where the grammar documents `(V.1)` — is #112.
- **Variant-aware deck slots** (level C of #89). Rejected: a French or reverse copy fills the slot.
- **The tournament PDF.** Play! Pokémon decklists do not carry language.
- **`first_edition`, `cosmos_holo`, `shadowless`.** Excluded from `FINISHES`. Cardmarket treats
  `first_edition` as an attribute *distinct* from finish — a copy can be 1st Edition **and** reverse
  holo — so folding it in would recreate the rarity/attribute confusion this design exists to avoid.
- **Translated card names.** #89 and #90 already settle that card data stays in its source language.
  A language attribute records what a copy is, not how to display it.

## Known seams

- **The four Asian language codes are only reachable through #111.** Until a Japanese `CardSet`
  exists, `language: "ja"` is refused on every card in the database. That is the validation working,
  not a gap to route around.
- **Per-set language overrides are unmodelled.** Portuguese did not exist for the earliest
  international sets, so the region's list is generous for them. Harmless for an inventory; a
  per-set override if it ever matters.
- **The card page's `−` defers to the collection page above one variant.** A variant picker on the
  card page would remove the deferral; it is not worth building before the split flow has been used.
- **A `Variant` value object was considered and dropped.** The `(language, finish)` pair recurs in
  the writers' kwargs, the unique index, the API params, the tool schemas and the views. Flat
  keyword arguments won on the grounds of least machinery; if a fifth call site appears, revisit.

## Sources

Domain claims are drawn from Cardmarket's own help pages —
[Finding and Listing Pokémon Cards](https://help.cardmarket.com/en/finding-and-listing-pokemon-cards),
[Add Cards to Wants List](https://help.cardmarket.com/en/add-cards-to-wants),
[How to Add a Pokémon Decklist to Wants](https://help.cardmarket.com/en/how-to-add-a-pkmn-decklist-to-wants),
[How to Add a Magic Decklist to Wants](https://help.cardmarket.com/en/how-to-add-a-mtg-decklist-to-wants) —
plus [an overview of the Asian markets](https://godofcards.com/en-cy/blogs/god-of-cards-blog/asiatische-pokemon-karten-im-uberblick)
and PokéBeach's set guides for the reverse-holo patterns
([Prismatic Evolutions](https://www.pokebeach.com/2025/01/prismatic-evolutions-set-guide-full-card-list-secret-rares-cut-cards-products-and-more),
[Ascended Heroes](https://www.pokebeach.com/2026/01/ascended-heroes-to-feature-multiple-reverse-holo-styles)).
