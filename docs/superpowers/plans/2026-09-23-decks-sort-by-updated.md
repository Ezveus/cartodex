# Plan — /decks sorted by last update

Spec: `docs/superpowers/specs/2026-09-23-decks-sort-by-updated-design.md`.

## Frozen contract

- `Deck.recently_updated` → `order(updated_at: :desc, id: :desc)`
- `Deck.alphabetical` → `order(LOWER(decks.name) ASC, decks.id ASC)`
- `DecksController#filter_params[:sort]`: `"name"` or `nil`
- `Decks::IndexView::SORT_OPTIONS = [["Recently updated", ""], ["Name (A–Z)", "name"]]`

## Steps

1. `DeckCard` and `DeckResult`: `belongs_to :deck, touch: true`.
2. `Deck`: the two scopes.
3. `DecksController#index`: replace `order(:name)` with `sort_decks(scope)` (name → `alphabetical`,
   anything else → `recently_updated`), add `sort` to `filter_params`, and update the two comments
   that tie the order to the spotlight.
4. `Search::Global`: the deck group uses `recently_updated`. The shared-deck group keeps its name
   order.
5. `Decks::IndexView`: a sort select in the filter bar.
6. `Og::DeckPayload#digest`: fix the comment, which says `DeckCard` has no touch.
7. `CLAUDE.md`: record the `touch` decision and the spotlight coupling.

## Tests

- Model: create, update and destroy of a `DeckCard` bump the deck's `updated_at`, and the same
  three for a `DeckResult`.
- Model: a bulk add inside a transaction issues exactly one `UPDATE "decks"`.
- Controller: the default order is `updated_at DESC`, with fixtures where the name, id and
  `created_at` orders all disagree with it.
- Controller: `sort=name` sorts case-insensitively.
- Controller: an unknown `sort` falls back to the default.
- Controller: the sort survives a filter, and it applies on a frame request too.
- Controller/view: the select renders with the chosen option selected.
- Spotlight: decks come back most recently updated first.
- Spotlight: the first rows equal the first rows of `/decks?q=` for the same query.
