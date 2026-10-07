# Proxy sheet — implementation plan

Spec: `docs/superpowers/specs/2026-10-07-proxy-sheet-design.md`.

One lane: the view half is one menu item and one system test, below the size where a second
implementation agent pays for itself.

## Contract

- `Decks::ProxySheetExporter.call(deck, missing_only: false)` → PDF bytes (String), or raises
  `Decks::ProxySheetExporter::NothingToPrint` / `TooManyPrintings`.
  - Constants: `CARD_WIDTH = 6.0.cm`, `CARD_HEIGHT = 8.5.cm` (Prawn measurement extensions),
    `COLUMNS = 3`, `ROWS = 3`, `MAX_PRINTINGS = 60`, `FETCH_THREADS = 8`,
    `ART_OPEN_TIMEOUT = 3`, `ART_READ_TIMEOUT = 5`.
  - `slots` (private, tested through `#layout`): the ordered list of DeckCards, one per copy.
  - Copies per row: `missing_only && deck.physical? ? deck_card.proxies : deck_card.quantity`.
- `DeckPolicy#proxy_sheet_missing? = owner?`.
- Route: `get :proxy_sheet, on: :member` → `DecksController#proxy_sheet`, `params[:missing] == "1"`.
- Rate limit `name: "decks-proxy-sheet"`, `PROXY_SHEET_RATE_LIMIT_TO = 10`, unless signed in.
- `Decks::ExportDropdown`: `proxy_sheet_items`, links with `data-turbo="false"`.

## Tasks (TDD, each test seen red first)

1. Service geometry: page is A4; every image drawn at exactly 170.08 × 240.94 pt; 9 per page; grid
   centred; 60 copies → 7 pages; order Pokémon/Trainer/Energy then name.
2. Service copies: `missing_only` on physical prints `proxies`; on non-physical prints `quantity`;
   all backed → `NothingToPrint`; > 60 printings → `TooManyPrintings`.
3. Service images: each distinct URL fetched once; PNG with alpha is embedded as JPEG; failed fetch
   (FetchError, or bytes that are not an image) → placeholder with name and set/number text, other
   cards still drawn.
4. Cut marks: drawn only outside the grid rectangle.
5. Policy: `proxy_sheet_missing?` owner-only; listed in the policy test's owner/visitor arrays.
6. Controller: PDF for owner, for a visitor on a shared deck; 404 for visitor on a private deck;
   `missing=1` refused (404) for a non-owner on a shared deck; NothingToPrint → redirect + notice;
   TooManyPrintings → redirect + alert; rate limit per visitor, owner not throttled.
7. Public access test row for `#proxy_sheet`.
8. Dropdown: owner on physical deck sees two items, owner non-physical one, visitor one (whole deck,
   no `missing=1` link); links have `data-turbo="false"`.
9. CLAUDE.md: export list sentence and deck-identity "sixth lookup" sentence.
