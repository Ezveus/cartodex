# /decks sorted by last update, re-sortable by name

## Request

`/decks` lists a member's decks most recently updated first by default, and can be re-sorted
alphabetically.

## Decisions (owner, 2026-09-23)

1. **"Updated" means the deck, its list and its results.** `DeckCard` and `DeckResult` both get
   `belongs_to :deck, touch: true`.
2. **The spotlight's deck group follows the same order.** Its "See all N decks" link lands on
   `/decks`, and `DecksController#index` sorted by name only so that the first rows of that page
   were the rows the spotlight had just shown. Both now sort most recently updated first.

## Why the column had to change meaning

Before this change `decks.updated_at` did not move when a card was added, requantified or removed
(`DeckCard` had no `touch`), nor when a result was recorded. Measured on the development database:
**7 of the 47 owned decks** carry a deck card updated more than a minute after the deck's own
`updated_at`. Sorting on the column as it was would have sunk exactly the decks a member had just
been editing.

`Og::DeckPayload#digest` records that `touch: true` was rejected once, as "moving `updated_at` on
every allocation write app-wide to serve this one feature". The objection was about the banner's
cost, and the product meaning now decides it: every `DeckCard` writer (`Decks::CardAdder`,
`BulkCardAdder`, `DeckCardQuantitySetter`, `OwnedCopiesSetter`, `OwnedCopiesReallocator`,
`PrintingSwapper`, `Decks::Fetcher`) acts on a deck the member named, so each of them is an edit of
that deck. `Collections::VariantMover` is the one collection service that mentions `owned_copies`,
and it writes no deck card. The digest keeps its deck-card terms, which still guard the writes that
skip callbacks (`update_all`, `insert_all`, fixtures).

**Consequences worth knowing:**

- `belongs_to … touch: true` goes through `touch_later`, which merges every touch in one
  transaction into a single `UPDATE decks`. A 60-card import therefore adds one statement inside
  `Decks::Fetcher`'s `BEGIN IMMEDIATE`, not 60. A test pins this.
- A reallocation moves copies between two decks, so it bumps both.
- Recording a result now changes the deck's banner digest, so the banner is rendered one more time
  per recorded result.
- `DecksController#share` writes `shared` through `update_column`, so sharing a deck does not move
  `updated_at`. That was already true and stays true, since sharing changes who can see a deck,
  not what the deck is.

## Sort

- The sort is chosen with a `sort` query param. Its default value `""` means most recently updated
  first (`updated_at DESC, id DESC`). `name` means alphabetical (`LOWER(name) ASC, id ASC`).
  Any other value falls back to the default.
- The name sort ignores case: SQLite's default `BINARY` collation puts `abc` after `Zoroark`.
  `LOWER` folds ASCII only, so accented initials are not folded. One of the 47 owned decks starts
  with a lowercase letter and none starts with an accented one.
- `id` breaks ties so that the order is deterministic.
- The sort is a `Ui::FilterSelect` in the existing filter bar, submitted live into the
  `deck_results` frame like the other selects. `turbo_action: "replace"` writes it into the URL, so
  a reload keeps it. Nothing persists it across visits.
- **The sort counts as a non-default state for "Clear".** `card-filter`'s `#anyFilterSet` reads
  every field of the form, so choosing *Name* shows "Clear", and "Clear" brings the page back to
  its default view, sort included. Leaving the sort out would have taken a JS change plus
  rewriting the Clear link's `href` live from outside the frame, for no gain a member would notice.
- `/decks/shared` is out of scope. It keeps `created_at DESC`.
- No index is added. A member owns a few dozen decks, and the sort runs over the `user_id` subset.
