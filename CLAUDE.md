# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cartodex is a Pokémon Trading Card Game card manager built with Rails 8.1 and Ruby 3.4.1. Features include collection tracking (with webcam scanning), deck management with archetype tagging and per-result win/loss tracking, tournament profiles (Play! Pokémon divisions), and decklist import plus multiple export formats (JSON, PTCG text, Cardmarket wishlist, tournament PDF, image). Card data is scraped from Limitless TCG. An admin panel provides dashboard, CRUD for card sets/cards/users/decks/archetypes/imports, and bulk import/rescrape actions.

## Common Commands

```bash
bin/setup                                    # Initial project setup
bin/dev                                      # Start development server
bin/rails test                               # Run unit tests
bin/rails test:system                        # Run system tests
bin/rails test test/models/card_test.rb      # Run a single test file
bin/rails test test/models/card_test.rb:10   # Run a specific test by line
bin/rubocop                                  # Lint (rubocop-rails-omakase style)
bin/brakeman --no-pager                      # Security scan
bin/importmap audit                          # JS dependency audit
```

CI runs four checks (`bin/brakeman`, `bin/importmap audit`, `bin/rubocop -f github`, `bin/rails db:test:prepare test test:system`) on every push and PR. Production deploy via Kamal is **manual**: trigger the workflow with `workflow_dispatch` (Actions → CI → Run workflow, or `gh workflow run ci.yml`), which re-runs the checks and deploys only if they pass. Kamal config lives in `config/deploy.yml` and `.kamal/`; `bin/kamal` is the deploy CLI. `bin/jobs` runs the Solid Queue worker locally.

## Architecture

**Database**: SQLite3 in every environment. Multi-database setup: `primary` plus `queue` (Solid Queue), `cable` (Solid Cable, dev/prod), and `cache` (Solid Cache, prod). Schema in `db/schema.rb`; secondary schemas in `db/queue_schema.rb`, `db/cable_schema.rb`, `db/cache_schema.rb`.

**Service pattern**: Business logic lives in `app/services/`. Services inherit from `ApplicationService` which provides a `.call(...)` class method that delegates to `new(...).call`, plus a `serialized_transaction` helper (SQLite `BEGIN IMMEDIATE` when no transaction is open, else a savepoint) used by the allocation services to serialize read-then-write under concurrent MCP calls. Custom error classes (`ParseError`, `FetchError`) for error handling.

Key services:
- `Cards::Fetcher` — scrapes card data from limitlesstcg.com using Nokogiri, creates/updates Card records with associated Attacks, Abilities, and PokemonSubtypes
- `CardSets::Importer` — scrapes card set data from Limitless TCG, used by `CardSets::ImportJob`
- `Decks::Fetcher` — parses decklist text format (`QUANTITY NAME SET NUMBER`), creates Deck with DeckCards in a transaction, coordinates Cards::Fetcher for each card, and auto-tags the deck with a matching existing archetype via `Decks::ArchetypeDetector`
- `Decks::ArchetypeDetector` — infers a deck's archetype from its notable Pokémon (rule-box attackers first); returns either a matching existing Archetype or candidate Pokémon to pre-fill a new one
- `Decks::Exporter` / `Decks::CardmarketExporter` / `Decks::TournamentPdfExporter` — deck export in JSON, Cardmarket wishlist, and tournament PDF formats (PTCG text export lives in `bin/export_deck_ptcg`)
- `Decks::Duplicator` — duplicates a deck with all its DeckCards
- `HttpFetcher` — Net::HTTP wrapper used by other services
- **Collection↔deck allocation** (real copies vs proxies): `Allocations::Availability` computes owned/committed/available per exact printing (use `.for_cards` to render a whole page — `.call` is the one-card case of it); `Allocations::OverAllocations` lists over-committed cards; `Allocations::PhysicalDecksByCard` answers "which physical decks hold these cards" in one grouped query, for both the report and its reallocation targets. `Collections::CardAdder`/`QuantitySetter`/`OwnedEquivalents` and `Decks::CardAdder` (greedy real-backing on physical decks)/`OwnedCopiesSetter`/`OwnedCopiesReallocator` (pure conversion between decks)/`DeckCardQuantitySetter` are the write operations, each wrapped in `serialized_transaction`. See the design spec at `docs/superpowers/specs/2026-07-02-collection-deck-allocation-design.md`.

**Jobs** (`app/jobs/`):
- `CardSets::ImportJob` — wraps `CardSets::Importer`
- `Decks::ImportJob` — wraps `Decks::Fetcher`, broadcasts progress via Turbo Streams, persists state via the `Import` model

**Models**: User has_many Decks, Collections, Imports, and TournamentProfiles. Deck belongs_to an optional Archetype (its own archetype), has_many Cards through DeckCards and has_many DeckResults (win/loss tracking with optional Archetype tagging for the opposing deck). Archetype has primary/secondary Pokémon (Card refs), parent/children hierarchy, and has_many DeckResults. Import persists background import status (progress, errors) for reload-safe tracking and retry. TournamentProfile belongs_to User (Play! Pokémon division metadata). CardSet has_many Cards (code/name uniqueness, release_date, `by_release` scope). Card belongs_to CardSet (optional), has_many Attacks, Abilities, and optional PokemonSubtype. Card validations are conditional on `card_type` (Pokémon vs Trainer vs Energy). Card uses a `compute_fingerprint` callback for deduplication (also the equivalence key for suggesting interchangeable printings).

**Allocation model** (collection as physically-owned inventory): `Collection.quantity` is the number of copies **owned** (source of truth; unique per user+card). `DeckCard.owned_copies` is how many of its copies are **real** (backed by owned cards); `quantity` is the total, `proxies = quantity − owned_copies` (unique per deck+card). Only decks with `physical == true` consume the collection. Invariant: `Σ owned_copies(card) over physical decks ≤ owned(card)` — exceeded only by a collection decrease, which is allowed and leaves a tolerated, surfaced over-allocation (never auto-corrected). User has an `api_token_digest` (SHA-256 of a per-user MCP bearer token — see `User.authenticate_api_token` / `regenerate_api_token`).

**Controllers**: API endpoints under `Api::` namespace serve JSON (archetypes, cards, collections, decks with nested deck_cards and deck_results). Admin panel under `Admin::` namespace covers dashboard, card sets (with import), cards (with rescrape), users (with toggle_admin), decks, archetypes (CRUD), and imports (list with error display, delete, retry). Top-level `tournament_profiles` and `deck_results` resources live alongside `decks`. All app routes (except root/health) require Devise authentication.

**MCP server**: An MCP (Model Context Protocol) endpoint is mounted at `POST /mcp` (`Mcp::ServerController`, top-level route **outside** the Devise `authenticate` block), using the `mcp` gem's `StreamableHTTPTransport` (stateless). Auth is a per-user bearer token (`Authorization: Bearer <token>`) matched against `api_token_digest`; authentication is split into `identify_token_user` (resolves the token, never halts) and `reject_unauthenticated!` (issues the 401) so that two rate limiters can sit between and after them: a per-IP one (`IP_RATE_LIMIT_TO`/min, `unless: -> { @current_user }`) that throttles anonymous token spam **before** the 401 without spending an authenticated client's budget, and a per-user work quota (`USER_RATE_LIMIT_TO`/min, keyed by `@current_user.id`) **after** it. Both are plain `before_action`s, so order is load-bearing; both pass an explicit `name:` so their cache keys stay distinct. Tokens carry an optional expiry (`api_token_expires_at`, `NULL` = never), rejected at `User.authenticate_api_token`, and record their last use at hourly granularity. Users manage the token from `/settings` (`SettingsController`, `McpTokensController`); the generate action answers with a Turbo Stream so the raw value never passes through the session cookie. Tool classes live in `app/mcp/` — an autoloaded root, so they are **top-level constants** (e.g. `AddCardToDeckTool`, not namespaced), subclassing `McpTool` (shared helpers `current_user`/`find_deck!`/`find_card!`/`text`/`positive_quantity?`). Read tools return JSON text, write tools return a summary string; both delegate to services and never hold business logic. Register a new tool by adding it to `Mcp::ServerController::TOOLS`. Tool names drop the `_tool` suffix of the class name. The eight+ tools cover collection/deck reads plus `add_card_to_collection`, `set_collection_quantity`, `add_card_to_deck`, `set_deck_card_owned_copies`, `reallocate_owned_copies`, `set_deck_card_quantity`, `list_over_allocations`, `suggest_owned_equivalents`.

**Frontend**: Hotwire (Turbo + Stimulus), Propshaft asset pipeline, importmap for JS. **All views use Phlex components** — see the `phlex-architecture` skill for conventions and patterns. Always use Phlex, never write view logic in ERB.

**Design system**: A single CSS-custom-property token system lives at the top of `app/assets/stylesheets/application.css` (neutrals, brand `--flare`, a per-energy-type palette, semantic result colours, elevation, and `--font-*` roles), with two override layers at the bottom of the file (base typography/dark navbar; energy-typed badges + holo treatment). Self-hosted fonts (Archivo / IBM Plex Sans / IBM Plex Mono) are in `app/assets/fonts`. `Card::TYPE_TOKENS` maps each energy type to its colour token — use it (not literal hexes) when colouring by type. A living reference renders the real tokens and components at **`/styleguide`** (`Styleguide::PageView`, non-production only); update it when adding components or tokens.

## Bin Scripts

- `bin/import_deck DECK_NAME [FILE]` — import decklist from file or stdin, fetches card data from web
- `bin/export_decks` — interactive JSON deck export
- `bin/export_deck_ptcg` — export deck in PTCG text format
- `bin/rails 'mcp:token[email@example.com,90d]'` — rotate and print a user's MCP bearer token (shown once; only the digest is stored). Lifetime is `30d`/`90d`/`1y`/`never`, default `90d`.

## Test Setup

Minitest with parallel execution. Fixtures in `test/fixtures/`. System tests configured with Capybara/Selenium/headless Chrome (no system tests written yet).
