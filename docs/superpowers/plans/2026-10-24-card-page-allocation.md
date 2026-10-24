# Card page allocation — plan

Spec: `docs/superpowers/specs/2026-10-24-card-page-allocation-design.md`. One lane (server + view
are ~5 files; a second lane would cost more than it returns).

## Contract

- `Allocations::PhysicalDecksByCard#call` rows become `{ id:, key:, name:, owned_copies: }`, ordered
  by `LOWER(decks.name), decks.id`. Existing readers use `:id`, `:key`, `:name` only.
- `CardsController#show`, signed in only:
  - `@allocation = Allocations::Availability.call(user: current_user, card: @card)`
  - `@committing_decks = Allocations::PhysicalDecksByCard.call(user: current_user, card_ids: [@card.id], holding: :holding_real_copies).fetch(@card.id, [])`
  - Visitor: both nil, no query.
- `Cards::ShowView.new(..., allocation:, committing_decks:)` renders `Cards::AllocationSection`
  when `allocation` is present.
- `Cards::AllocationSection` (Phlex): a `turbo-frame#card-allocation` carrying
  `data-controller="card-allocation"`, value `url` (= `card_path(card)`), and
  `data-action="collection-quantity:changed@window->card-allocation#refresh"`.
  Prints Owned N, Committed N, Available N, the over-allocation note (hidden unless committed > owned, with
  link to `over_allocations_path`), and a list of decks (`link_to name, deck_path(key)` + "N cop(y|ies)"),
  or "No physical deck uses a real copy of this printing." when empty.
- `card_allocation_controller.js`: `refresh()` sets the frame's `src` to `urlValue` the first time
  and calls `reload()` after. No arithmetic in JS.

## Tests

1. Controller: signed in → numbers and deck links appear, with per-deck counts; a non-physical
   deck and a proxy-only physical deck holding the card are not listed; another member's physical
   deck is not listed and does not count.
2. Controller: over-allocated (committed > owned) → note with the excess and the link.
3. Controller: visitor → no section, and query count equals a page without the feature
   (assert no `deck_cards` query).
4. Service: `owned_copies` per row and name ordering.
5. System: increment the counter on a card committed 1 with 1 owned → Available goes 0 → 1;
   decrement twice (remove) → over-allocation note appears.
6. Component: count pluralisation ("1 copy" / "2 copies").
