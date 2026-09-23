# Plan — archetype deck list, analysis on its own page

Spec: `docs/superpowers/specs/2026-09-23-archetype-deck-list-design.md`.

Test invocation: unit suite in the container (`cartodex-test:4.0.6`, volume `cartodex-bundle-406`,
`bin/rails test`), system tests on the host (`bin/rails test test/system/<file>` for one file,
`bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system` for the suite).

One implementer, not lanes: the controller tests assert on rendered markup, so the server and view
halves share every test file. Splitting them would mean two agents editing
`archetypes_controller_test.rb`.

## Frozen contract

- Route: `get :analysis, on: :member` → `analysis_archetype_path(archetype)`, `/archetypes/:slug/analysis`.
- `ArchetypesController#analysis` (today's `#show` body, verbatim), `#show` (the list).
- `ArchetypesController::ANALYSIS_RATE_LIMIT_TO = 60`, limiter name `"archetypes-analysis"`.
- `ArchetypesController::LEGACY_REPORT_PARAMS = %w[pool venue group]`.
- `ArchetypePolicy#analysis? = true`.
- `Archetypes::DeckList.call(archetype:, viewer:, page:)` → `Result(own_decks:, decks:, page:, pages:, total:)`, `PER_PAGE = 24`.
- `Archetypes::DeckList.caption_for(deck)` → String or nil (field-list caption).
- `Decks::DeckCard.new(..., caption: nil, archetype_badge: true)`; `Decks::PublicBadges.new(deck:, linked: false, archetype_badge: true)`.
- `Archetypes::ShowView` → the list view; `Archetypes::AnalysisView` ← today's `ShowView`.
- Views: `app/views/archetypes/show.html.erb` renders `ShowView`, and the new `analysis.html.erb` renders `AnalysisView`.

## Tasks

1. **Move the report** (pure refactor, no new behaviour).
   - Route, policy `analysis?`, `publicly_reachable :analysis`, the `#analysis` action with today's
     `#show` body, the rate limiter `"archetypes-analysis"` at 60.
   - Rename `Archetypes::ShowView` → `AnalysisView`, and add the header link back to the list.
   - `SampleSelector` form action and `CardReport#path_for` → `analysis_archetype_path`.
   - Move every report test in `archetypes_controller_test.rb`, `archetype_metagame_test.rb`,
     `sample_selector_test.rb`, the card report component test, `og_tags_test.rb`,
     `public_access_test.rb`, `archetypes_rate_limit_test.rb` and `navbar_active_section_test.rb`
     to the analysis path. Styleguide references to `Archetypes::ShowView` follow.
   - Gate: the suite stays at 2087 runs, green, before any new test.
2. **DeckList service**, TDD: `test/services/archetypes/deck_list_test.rb` — rule A both
   directions, the NULL trap, order (date, placement, no-standing deck, id tiebreak), a deck in
   two standings listed once, private decks never public, own decks private+shared ordered by
   name, pagination and clamp, captions.
3. **DeckCard / PublicBadges keywords**, TDD in their component tests.
4. **List page**: `#show` renders `Archetypes::ShowView` (header, Your decks, Decks, pager,
   empty state), 301 for the legacy params, flat-cost test, `@og_payload`.
5. **System test** for the list → analysis path, both viewports; adjust the existing metagame
   system test's entry point.
6. **Docs**: `docs/architecture/archetype-metagame.md`, `docs/architecture/public-surface.md`,
   `CLAUDE.md` (the public route list, "`#show` costs 17 queries", the Og section's
   "`ArchetypesController#show` may read only…", the rate-limit count), and the controller's
   header comment.
