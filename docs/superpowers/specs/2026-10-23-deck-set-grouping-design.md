# Deck page grouped by set — design

An explicit request from the owner, no tracker issue: on the deck builder (the owner's deck page,
`Decks::ShowView`, in view and edit modes) offer a second way to list the cards — grouped by the
set (édition) they were printed in, instead of by card type.

## Scope

- **The owner's page only.** `Decks::PublicShowView` (visitors, shared decks, field lists) stays
  grouped by type and gains no control.
- **No storage.** The choice is a URL parameter, `?group=set`. No column, no cookie, no
  `sessionStorage`. Absent, or any other value, means grouping by type, rendered exactly as before
  — the default page emits the same markup and runs the same queries it did.

## The control

A "Group by  Type · Set" pair of links above the card list, the same shape and the same rule as
`Archetypes::CardReport`'s mode links: the current mode stays a link (a tab that cannot be clicked
reads as disabled), and is told apart by `aria-current="page"` and a modifier class. The links are
`deck_path(deck)` and `deck_path(deck, group: "set")`; the default never enters the query string.

## The set view

- **Sections** are the `CardSet` a card belongs to (`cards.card_set_id`), ordered by
  `release_date` **descending** — the newest set first. A set with no `release_date` sorts after
  every dated set; ties fall back to the code, then the id, so the order is total.
- **Cards with no `card_set`** (a printing imported before its set, or whose set was deleted —
  `CardSet has_many :cards, dependent: :nullify`) are grouped by their `cards.set_name` and come
  **after** every linked set, alphabetically by that code. The catalogue holds more `set_name`
  codes than `card_sets` rows (see `Card.in_set_code` in `CLAUDE.md`), so this is a real case.
  One refinement: an unlinked card whose `set_name` equals the code of a set **already present
  in this deck** joins that set's section, so one set never shows as two sections (a deck can
  hold one linked and one unlinked POR printing). That costs no query — it only reads sets the
  deck has loaded anyway.
- **Inside a section**, cards are ordered by set number, numerically where the number is numeric:
  the key is `(alphabetic prefix, integer part, rest)`, so `2 < 10 < 100` and the `GG1`-style
  numbers (100 printings in the catalogue) come after the purely numeric ones of their set and in
  their own numeric order (`GG2 < GG10`). `(set_name, set_number)` is UNIQUE, so no two rows of a
  section tie.
- **Heading**: `Set name (CODE) · N cards` for a linked set, `CODE · N cards` for an unlinked one
  (there is no name to print). N is the **copies** count — the same figure the type view's own
  headings print first (`Pokémon (N — M unique)` sums `quantity`). It is wrapped in the
  `sectionTotal` target `deck-totals` already updates, so a `+`/`−` keeps it true, and the noun is
  re-pluralised by the same controller (`1 card`, `2 cards`) through a new optional
  `sectionNoun` target. The unique count is not printed: the owner's format omits it.
- The grouping lives in `Decks::SetGroups`, a service over the loaded deck cards, so the order is
  one decision held by a unit test rather than spread through the component.

## Which navigation keeps the mode

| Path | Keeps `?group=set` | Why |
|---|---|---|
| Adding a card (search box) | yes | `card_search_controller.js` reloads `window.location.href` |
| `+` / `−`, allocation stepper, removing a card | yes | in place, no navigation |
| Printing swap | yes | in place in type mode; **in set mode the page reloads** (`window.location.href`), because the swapped card now belongs to another section and both headings' counts change |
| Edit → Save / Cancel (header frame) | yes | only the `deck-header` Turbo Frame is replaced; the list is untouched. The Edit and Cancel links also carry `group=set`, so the same links opened in a new tab (a full page) keep it too, and `DecksController#edit` honours the parameter |
| Log result, Share | yes | in place (modal / Turbo Stream) |
| Proxy sheet refusals, the HTML fallback of Share, Versions/Results/Odds/Match stats links, Back to Decks | no | they leave the page or are non-Turbo fallbacks; they land on the default view |

## Cost

`card_set` is preloaded (`deck_cards: { card: [ :pokemon_subtype, :card_set ] }`) **only in set
mode**, so the default page's query count does not move; the set view costs one more statement,
flat in the number of cards (a flat-cost test holds it).

## Assumptions

- Unlinked sections are ordered alphabetically by `set_name` (the owner only said "last").
- A set with no `release_date` sorts after the dated ones, before the unlinked ones.
- An unlinked card whose `set_name` matches the code of a set present in the deck joins that set.
- The heading of an unlinked group is the bare code.
- The mode links point at the show page even from a full-page edit: they leave edit mode.

## Owner may reverse

- **Printing swap in set mode reloads the page.** Alternatives: leave the row where it is until
  the next reload (the row then sits under the wrong set heading, and both headings' counts are
  wrong, until a reload); or move the row client-side (a second implementation of the ordering in
  JavaScript, which this repository cannot test). On the motivating case — a player swapping a
  card to the newest printing to see what the deck holds per set — only the reload shows it in
  its new set at once.
- **Unlinked cards folded into a present set of the same code.** Alternative: always group them
  apart by `set_name`; a deck with one linked and one unlinked POR printing then shows two
  sections, "Perfect Order (POR)" and "POR".
