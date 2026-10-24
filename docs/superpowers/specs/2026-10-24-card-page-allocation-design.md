# Card page: where my copies are

## Request

On a card's page, a signed-in member sees how many of their copies are free, how many are taken,
and which decks take them.

## Decisions

- **Per exact printing.** The numbers are `Allocations::Availability` for this `card_id`, the same
  key the allocation model and the page's own "In collection" counter use. MEG 113 and ASC 113 are
  counted apart. Summing over the fingerprint was weighed and refused by the owner: it would put two
  different "owned" figures on one page.
- **"Taken" means committed real copies in physical decks** — `DeckCard#owned_copies` summed over
  the member's `physical` decks. A proxy slot and a TCG Live deck take nothing from the collection,
  so neither is listed. The deck list is `Allocations::PhysicalDecksByCard` with
  `holding: :holding_real_copies`, which now also returns each row's `owned_copies` and orders by
  deck name.
- **Vocabulary follows the collection page**: *Committed* and *Available*, the words
  `Collections::IndexView` already prints for the same three numbers.
- **Over-allocation is stated, not hidden.** `available` is clamped at 0, so a member who sold
  copies a deck still counts would read "0 available" and nothing else. When committed exceeds
  owned the section says by how much and links to `/over_allocations`.
- **The counter stays live, and the server recomputes.** The "In collection" counter writes through
  `/api/collections` without reloading. On each `collection-quantity:changed` event the section, a
  Turbo Frame (`card-allocation`), reloads itself from the card page. Client arithmetic from the
  event's `delta` was the first draft and was dropped: a member may own one printing as several
  `collections` rows (language, finish — `index_collections_on_user_card_and_variant`), the counter
  edits one of them, and owned is their sum. One request per click buys a figure computed by the
  same `Availability` that computed it the first time.
- **Owned is printed in the section too**, from `Availability` (summed over variants), so the three
  numbers it prints are consistent with each other. They are *not* always consistent with the
  pre-existing "In collection" counter, which reads one arbitrary row (`find_by(card_id:)`): a member
  holding a printing as two variant rows sees two owned figures. Latent today — nothing in `app/`
  calls `Collections::VariantMover`, the only writer of a non-`unknown` variant, and the development
  database holds no such pair — and left to the counter's owner rather than fixed here.
- **A deck row says "real copies"**: `owned_copies`, not the deck's quantity, which may be larger
  with the rest played as proxies.
- **Visitors get nothing**: the section renders only for a signed-in reader and every query is
  scoped by `current_user`. A visitor's page issues no extra query.

## Measured (development database)

- 15 physical decks, 115 `deck_cards` rows holding real copies.
- 15 (member, printing) pairs are committed in more than one deck, at most 4 — the list is short.
- No over-allocated printing in development; the note is exercised by tests only.

## Out of scope

- Other printings' copies (the fingerprint view).
- Changing allocations from the card page (the deck page and `/over_allocations` do that).
