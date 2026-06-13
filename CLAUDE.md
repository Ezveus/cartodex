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

CI runs four checks (`bin/brakeman`, `bin/importmap audit`, `bin/rubocop -f github`, `bin/rails db:test:prepare test test:system`) then deploys master to production via Kamal when they pass. Kamal config lives in `config/deploy.yml` and `.kamal/`; `bin/kamal` is the deploy CLI. `bin/jobs` runs the Solid Queue worker locally.

## Architecture

**Database**: SQLite3 in every environment. Multi-database setup: `primary` plus `queue` (Solid Queue), `cable` (Solid Cable, dev/prod), and `cache` (Solid Cache, prod). Schema in `db/schema.rb`; secondary schemas in `db/queue_schema.rb`, `db/cable_schema.rb`, `db/cache_schema.rb`.

**Service pattern**: Business logic lives in `app/services/`. Services inherit from `ApplicationService` which provides a `.call(...)` class method that delegates to `new(...).call`. Custom error classes (`ParseError`, `FetchError`) for error handling.

Key services:
- `Cards::Fetcher` — scrapes card data from limitlesstcg.com using Nokogiri, creates/updates Card records with associated Attacks, Abilities, and PokemonSubtypes
- `CardSets::Importer` — scrapes card set data from Limitless TCG, used by `CardSets::ImportJob`
- `Decks::Fetcher` — parses decklist text format (`QUANTITY NAME SET NUMBER`), creates Deck with DeckCards in a transaction, coordinates Cards::Fetcher for each card, and auto-tags the deck with a matching existing archetype via `Decks::ArchetypeDetector`
- `Decks::ArchetypeDetector` — infers a deck's archetype from its notable Pokémon (rule-box attackers first); returns either a matching existing Archetype or candidate Pokémon to pre-fill a new one
- `Decks::Exporter` / `Decks::CardmarketExporter` / `Decks::TournamentPdfExporter` — deck export in JSON, Cardmarket wishlist, and tournament PDF formats (PTCG text export lives in `bin/export_deck_ptcg`)
- `Decks::Duplicator` — duplicates a deck with all its DeckCards
- `HttpFetcher` — Net::HTTP wrapper used by other services

**Jobs** (`app/jobs/`):
- `CardSets::ImportJob` — wraps `CardSets::Importer`
- `Decks::ImportJob` — wraps `Decks::Fetcher`, broadcasts progress via Turbo Streams, persists state via the `Import` model

**Models**: User has_many Decks, Collections, Imports, and TournamentProfiles. Deck belongs_to an optional Archetype (its own archetype), has_many Cards through DeckCards and has_many DeckResults (win/loss tracking with optional Archetype tagging for the opposing deck). Archetype has primary/secondary Pokémon (Card refs), parent/children hierarchy, and has_many DeckResults. Import persists background import status (progress, errors) for reload-safe tracking and retry. TournamentProfile belongs_to User (Play! Pokémon division metadata). CardSet has_many Cards (code/name uniqueness, release_date, `by_release` scope). Card belongs_to CardSet (optional), has_many Attacks, Abilities, and optional PokemonSubtype. Card validations are conditional on `card_type` (Pokémon vs Trainer vs Energy). Card uses a `compute_fingerprint` callback for deduplication.

**Controllers**: API endpoints under `Api::` namespace serve JSON (archetypes, cards, collections, decks with nested deck_cards and deck_results). Admin panel under `Admin::` namespace covers dashboard, card sets (with import), cards (with rescrape), users (with toggle_admin), decks, archetypes (CRUD), and imports (list with error display, delete, retry). Top-level `tournament_profiles` and `deck_results` resources live alongside `decks`. All app routes (except root/health) require Devise authentication.

**Frontend**: Hotwire (Turbo + Stimulus), Propshaft asset pipeline, importmap for JS. **All views use Phlex components** — see the `phlex-architecture` skill for conventions and patterns. Always use Phlex, never write view logic in ERB.

## Bin Scripts

- `bin/import_deck DECK_NAME [FILE]` — import decklist from file or stdin, fetches card data from web
- `bin/export_decks` — interactive JSON deck export
- `bin/export_deck_ptcg` — export deck in PTCG text format

## Test Setup

Minitest with parallel execution. Fixtures in `test/fixtures/`. System tests configured with Capybara/Selenium/headless Chrome (no system tests written yet).
