# Plan — Cardmarket wishlist, missing copies only (#208)

Spec: `docs/superpowers/specs/2026-10-01-cardmarket-wishlist-missing-copies-design.md`.

## Contract

- `Decks::CardmarketExporter.call(deck, missing_only: false)` → String. With `missing_only: true`
  each line asks for `dc.proxies` on a physical deck and `dc.quantity` otherwise; lines at 0 are
  dropped; no line at all → `""` (the full export keeps its trailing `"\n"`).
- `DeckPolicy#cardmarket_missing? = owner?`.
- `GET /decks/:key/export?style=cardmarket_missing` → `authorize @deck, :cardmarket_missing?`,
  then `{ text: }`, or `{ text: "", notice: "Nothing to buy — every card in this deck is owned." }`
  when the text is blank.
- `Decks::ExportDropdown.new(deck:, owner: false)` — `owner:` replaces `tournament_pdf:`, since
  the component already argues that what a visitor may not have is one decision. When
  `owner && deck.physical?` it renders two items, "Copy as Cardmarket wishlist
  (missing copies)" → `style: "cardmarket_missing"` and "Copy as Cardmarket wishlist (whole deck)"
  → `style: "cardmarket"`; otherwise the single existing item. `ShowView` passes
  `owner: true`, `PublicShowView` does not.
- `clipboard_controller.js#copy`: when the fetched JSON carries `notice`, show it in the label for
  3 s and do not touch the clipboard.

## Steps (one lane, TDD)

1. Exporter tests: physical deck nets `owned_copies`; line at full backing dropped; partially
   backed line uses `Nx` prefix with the netted count (2 of 4 → `2x`), and a netted count of 1
   loses the prefix; non-physical deck under `missing_only` gives full counts; all backed → `""`;
   default style ignores `owned_copies` on a physical deck.
2. Policy/controller tests: owner gets netted text; owner gets notice when nothing to buy; visitor
   of a shared physical deck is refused `cardmarket_missing` (404) and still gets the full
   `cardmarket` export.
3. Menu tests: owner of a physical deck sees both items with their URLs; owner of a non-physical
   deck sees the single item; visitor of a shared physical deck sees the single item and no
   `cardmarket_missing` URL anywhere.
4. System test: owner of a fully backed physical deck clicks "(missing copies)" and the button
   reads the notice.
5. CLAUDE.md: one line under the exporter's bullet.
