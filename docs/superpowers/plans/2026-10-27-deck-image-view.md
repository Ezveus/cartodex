# Deck image view — plan

Spec: `docs/superpowers/specs/2026-10-27-deck-image-view-design.md`.

1. `DecksController#deck_view` → `params[:view] == "images" ? :images : :list`. `owner_show`
   assigns `@view`; in `:images` it sets `@states = Decks::FingerprintStates.deck_only(@deck.deck_cards)`
   instead of `owner_states`. `public_show` assigns `@view`. ERBs pass `view:`.
2. `Decks::ModeLinks.new(label:, current:, modes: [[value, label, href]])` — the `.deck-group-modes`
   markup `ShowView#group_links` draws today, reused for "Group by" and "View". Hrefs keep the
   other parameter.
3. `Decks::CardTile.new(printing:, name:)` — `li.deck-card-tile` holding a `.deck-card-item` with
   the preview data/actions (`RowMarkup#deck_line` grows a `css_class:` keyword), an `<img>` from
   `card.image_url` (`loading: lazy`) or a placeholder, and `span.deck-card-qty` with the bare number.
4. `Decks::ImageGrid.new(sections:)` → `DeckSections` with `row:` returning one `CardTile` per
   in-deck printing of the row (`row.printing ? [row.printing] : row.state.in_deck`). `DeckSections`
   accepts a lambda returning one component or an array.
5. `ShowView` (owner): `view:` param; in images — no card search, no `deck_rows_target: "sections"`,
   `ImageGrid`; "View" links beside "Group by". `PublicShowView`: `view:` param, "View" links, grid.
6. CSS: `.deck-show-main--images .deck-card-list` → grid `repeat(auto-fill, minmax(120px, 1fr))`, 90px below the breakpoint (110px gave two columns at 375px — measured),
   no row border; badge `::before { content: "×" }`.

Tests: controller (both pages, the param, mode links keep the other param, query counts),
components (tile markup contract, placeholder, set view), Vitest (`collectCards` on tile markup),
system (grid renders and export reads it, both viewports; geometry: tiles side by side).
