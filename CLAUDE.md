# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Cartodex is a Pokémon Trading Card Game card manager built with Rails 8.0.1 and Ruby 3.4.1. It supports French and English. Features include collection tracking (with webcam scanning), deck management with win/loss tracking, and decklist import/export. Card data is scraped from Limitless TCG.

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

CI runs all four checks: `bin/brakeman`, `bin/importmap audit`, `bin/rubocop -f github`, and `bin/rails db:test:prepare test test:system`.

## Architecture

**Database**: SQLite3 (all environments). Schema in `db/schema.rb`.

**Service pattern**: Business logic lives in `app/services/`. Services inherit from `ApplicationService` which provides a `.call(...)` class method that delegates to `new(...).call`. Custom error classes (`ParseError`, `FetchError`) for error handling.

Key services:
- `Cards::Fetcher` — scrapes card data from limitlesstcg.com using Nokogiri, creates/updates Card records with associated Attacks, Abilities, and PokemonSubtypes
- `Decks::Fetcher` — parses decklist text format (`QUANTITY NAME SET NUMBER`), creates Deck with DeckCards in a transaction, coordinates Cards::Fetcher for each card
- `HttpFetcher` — Net::HTTP wrapper used by other services

**Models**: User has_many Decks and Collections. Deck has_many Cards through DeckCards. Card has_many Attacks, Abilities, and optional PokemonSubtype. Card validations are conditional on `card_type` (Pokémon vs Trainer vs Energy).

**Controllers**: API endpoints under `Api::` namespace serve JSON. All app routes (except root/health) require Devise authentication.

**Frontend**: Hotwire (Turbo + Stimulus), Propshaft asset pipeline, importmap for JS.

## Bin Scripts

- `bin/import_deck DECK_NAME [FILE]` — import decklist from file or stdin, fetches card data from web
- `bin/export_decks` — interactive JSON deck export
- `bin/export_deck_ptcg` — export deck in PTCG text format

## Test Setup

Minitest with parallel execution. Fixtures in `test/fixtures/`. System tests use Capybara with Selenium/Chrome.
