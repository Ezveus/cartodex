# Collection & Deck MCP Server — Design

**Date:** 2026-07-01
**Status:** Approved

## Goal

Expose an MCP (Model Context Protocol) server, **mounted inside the Rails app**, that lets an MCP
client (Claude Code / Claude Desktop) manage a user's Cartodex data:

- Add cards to the collection.
- Link cards to a deck.
- Move a card from the collection into a deck, and back out of a deck into the collection.

## Key decisions

- **Transport:** HTTP endpoint mounted in the Rails app.
- **Auth:** per-user API token sent as `Authorization: Bearer <token>`. Every tool call is scoped to
  the authenticated user.
- **Move semantics:** collection↔deck moves are *real quantity transfers*, floored at 0, with **no
  ownership enforcement** (you may move a card into a deck even if the collection quantity is short;
  quantities never go negative).
- **Card identification:** tools reference a card by `card_id`. Read-only helper tools let the
  assistant resolve ids and inspect state first. The card must already exist in the DB (cards are
  scraped from Limitless elsewhere; this MCP does not scrape).

## Library & wiring

Use the **official `mcp` Ruby gem** mounted via a dedicated Rails route + controller
(`Mcp::ServerController`).

- A `before_action` authenticates the `Authorization: Bearer <token>` header, finds the `User`, and
  rejects unknown/missing tokens with a JSON-RPC error before any tool runs.
- The request is handled by an `MCP::Server` instance; the authenticated `User` is passed through
  `server_context` so tools act on the correct account.
- Exact transport wiring (Streamable HTTP with SSE vs. plain JSON-RPC POST handling via
  `server.handle_json`) will be verified against the installed gem version during planning, and the
  route will be excluded from Devise's `authenticate :user` block (it uses token auth, not the
  session).

**Alternative considered:** the `fast-mcp` gem has a Rails railtie but authenticates with a single
static/global token, which does not fit per-user scoping. The official gem is preferred for that
reason.

## Tools

All tools are scoped to the authenticated user. Write-tool quantities default to `1`.

### Write tools

- `add_card_to_collection(card_id, quantity=1)` — increments the user's `Collection` entry for the
  card, creating it if absent. Does not touch decks.
- `add_card_to_deck(deck_id, card_id, quantity=1)` — "relier à un deck": increments the `DeckCard`,
  creating it if absent. Does **not** touch the collection.
- `move_card_to_deck(deck_id, card_id, quantity=1)` — transfer: `Collection −N` (floored at 0),
  `DeckCard +N`. Transactional.
- `move_card_from_deck(deck_id, card_id, quantity=1)` — transfer: `DeckCard −N` (the `DeckCard` row
  is destroyed if it reaches 0), `Collection +N`. Transactional.

### Read tools

- `search_cards(query, set_code=nil, limit=nil)` → `[{id, name, set_name, set_number, card_type}]`
- `list_decks()` → the user's `[{id, name, format}]`
- `list_collection(query=nil)` → `[{card_id, name, quantity}]`
- `list_deck_cards(deck_id)` → `[{card_id, name, quantity}]`

Every tool returns a human-readable text summary (e.g. the resulting quantities). Deck- and
card-scoped tools validate that the `deck_id` belongs to the user and that the `card_id` exists,
returning a tool error otherwise.

## Business logic & structure

Following the repo's service pattern (`app/services/`, `ApplicationService.call`):

- `Decks::CardTransfer.call(user:, deck:, card:, quantity:, direction:)` — handles both directions
  (`:in` = collection→deck, `:out` = deck→collection) transactionally, flooring quantities at 0 and
  destroying a `DeckCard` that reaches 0.
- The simple add operations reuse small services (or the existing `find_or_initialize_by` +
  increment logic already present in `Api::CollectionsController` / `Api::DeckCardsController`,
  extracted for reuse).

**MCP tool classes stay thin**: parse arguments, call the service / ActiveRecord, return a text
summary. Tool classes live under `app/mcp/tools/` (or similar), one class per tool.

## Auth mechanics

- Migration: add `api_token:string` to `users` (unique index). Use `has_secure_token :api_token`.
  Backfill tokens for existing users in the migration.
- Rake task `mcp:token[email]` prints a user's token (and can regenerate it) for pasting into an MCP
  client config.

## Testing

- Service test for `Decks::CardTransfer`: both directions, flooring at 0, destroy-on-zero, and
  cross-user isolation.
- Request/controller tests for the mount point: valid token routes to the right user; missing/bad
  token is rejected before any tool runs; one representative end-to-end tool call.

## Out of scope

- Scraping new cards from within the MCP (cards must already exist).
- A UI for viewing/regenerating the API token (rake task only for now).
- Deleting collection entries or decks via MCP.
