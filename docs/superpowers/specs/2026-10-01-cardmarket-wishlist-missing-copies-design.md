# Cardmarket wishlist: only the copies still to buy (#208)

## Need

Exporting a physical deck to a Cardmarket wishlist asks for `dc.quantity`, the deck's full count,
so the wants list includes copies the member's collection already backs.

## Decisions (settled with the owner on 2026-10-01)

1. **A second export style, `cardmarket_missing`, beside the existing `cardmarket`.** The full
   count stays reachable — buying a second copy of a deck is a real use — so nothing about the
   existing style changes.
2. **It is the owner's alone.** `DeckPolicy#cardmarket_missing? = owner?`, the same shape as
   `tournament_pdf?`. The export endpoint is public, and `owned_copies` is collection data:
   `Decks::PublicBadges` already refuses to show a visitor the "Proxies" badge for exactly that
   reason. A visitor netting the owner's collection off their own shopping list would also be
   wrong on its face — the visitor owns none of it.
3. **The line count is `DeckCard#proxies` on a physical deck, `quantity` otherwise.** A
   non-physical deck's `owned_copies` is 0 by validation (`owned_copies_zero_unless_physical`),
   so `proxies` would already equal `quantity`; the branch states the rule instead of letting it
   happen by accident. A line at 0 is dropped.
4. **Nothing to buy is said, not copied.** The JSON answer is `{ text: "", notice: "…" }` and
   `clipboard_controller` shows the notice in the button's label instead of writing an empty
   clipboard.

## Scope boundaries (from the issue)

- Only `owned_copies` is netted off, never free copies in the collection
  (`Allocations::Availability`): backing is not re-derived automatically, and doing so would be a
  different feature.
- Another printing of the same card (`fingerprint`) does not count — that is
  `Collections::OwnedEquivalents` and the printing swap.

## Measurements (development database, 2026-10-01)

- 49 owned decks, 13 physical. Their 340 rows: 67 backed by at least one real copy, 59 fully
  backed, 0 with `owned_copies > quantity` (refused by `owned_copies_within_quantity`).
- 0 rows of a non-physical deck carry `owned_copies > 0`.
- One physical deck (31 rows) is fully backed, so "nothing to buy" is a state that exists today.

## The menu goes stale, the answer does not

`Decks::ExportDropdown` sits outside `Decks::HeaderFrame`, so editing `physical` in place does not
re-render it. The menu offers the two Cardmarket items when the deck is physical at render time;
the server decides the count from the deck as it is at request time. A deck turned non-physical
in place therefore answers the "missing copies" item with its full count — correct content under
a label that is stale until the next load.
