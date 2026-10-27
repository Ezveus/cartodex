# Deck image view

A deck page, the owner's and the public one, can show its list as a grid of card images instead of
text rows. Asked for on 2026-10-27; three choices were settled by the owner before any code:

- **Read-only.** The grid carries no stepper, no ⇄, no real/proxy figure, on either page. Editing
  stays in the list view.
- **One tile per in-deck printing, with a ×N badge** — not N fanned copies.
- **The grid follows "Group by"** on the owner's page (type or set). The public page has no
  "Group by" and stays by type.

## Address

`?view=images`, beside `?group=set`, never stored — the rule `DecksController#deck_grouping`
already follows. Any other value is the list. Both mode controls are links that keep the other
parameter, so `?group=set&view=images` is reachable from either side. `#edit`, the header form and
its Cancel do **not** carry `view`: in place, only the `deck-header` frame is replaced and the grid
behind it stays; the full-page edit (no JavaScript) lands on the list, which is where editing
happens anyway.

## What a tile is

Each section is a `Decks::Layout` section, so headings, counts and order are the list's own. A
type-view row (one card, possibly several printings) gives one tile per in-deck printing, in the
state's printing order; a set-view row is already one printing.

A tile is a `.deck-card-item` carrying `data-card-preview-url` and a `.deck-card-qty`, because
`deck_image_export_controller.js#collectCards` reads exactly that, document-wide. With the grid on
screen and no list rendered, the image export would otherwise find nothing — it throws "No cards to
export". The badge's text is the bare number and the "×" is drawn by CSS: `collectCards` runs
`parseInt` on the text, and `parseInt("×4")` is `NaN`, which its filter then drops — every card
silently missing from the exported image.

## Images

The `<img>` loads `cards.image_url` straight from the Limitless CDN, lazily, as `/cards` and the
collection grid already do — **not** through `CardsController#image`. That proxy exists for the
canvas export (cross-origin pixels) and is rate-limited per address for visitors
(`IMAGE_RATE_LIMIT_TO` = 300/min); a grid through it would spend a visitor's budget at 26 images a
page (median distinct printings per deck in development: 26, min 6, max 42, over 4391 decks). The
tile keeps the preview hover/click, which does use the proxy, as the list rows do.

A card with no `image_url` (0 of 5222 in development today, but nothing forbids it) prints as a
framed placeholder carrying its name and set, never a broken image.

## Cost

The grid needs only the deck's own rows, so the owner's image view builds its states with
`Decks::FingerprintStates.deck_only` — no catalogue read, no availability. The owner's page in the
image view therefore costs **fewer** queries than the list (asserted); the public page costs the
same literal as its list.

## Out of scope

Proxy markers on the owner's grid, editing on the grid, remembering the view across visits.
