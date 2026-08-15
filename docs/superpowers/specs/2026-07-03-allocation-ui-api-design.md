# Surface the Allocation Model in the Web UI & JSON API — Design

**Date:** 2026-07-03
**Status:** Approved
**Issue:** #55
**Builds on:** `2026-07-02-collection-deck-allocation-design.md` (the domain model + MCP tools this feature now exposes to the web UI and JSON API).

## Goal

The collection↔deck allocation model (real copies vs proxies, committed/available, over-allocation)
is currently reachable only through the MCP tools. Make it **visible and controllable** in the web UI
and the `Api::` JSON endpoints, reusing the existing services. No business logic moves into views or
controllers — they stay thin, delegating to services exactly as the MCP tools do.

## Vocabulary

Reuses the terms from the base design: **owned** (`collections.quantity`), **real / owned copy**
(`deck_cards.owned_copies`), **proxy** (`quantity − owned_copies`), **committed** (Σ `owned_copies`
over the user's physical decks), **available** (`max(0, owned − committed)`), **over-allocated**
(`committed > owned` — tolerated and surfaced, never auto-corrected).

## Confirmed decisions (from the brainstorming interview)

1. **Scope is display + interactive controls**, not display-only. The web UI both surfaces
   real/proxy/committed/available and lets the user adjust `owned_copies` and reallocate reals
   between decks — replicating the MCP write tools in the UI.
2. **Over-allocation surfacing = dedicated page + banner + per-deck badge.** A `/over_allocations`
   page lists each over-allocated card with its contributing decks; a discreet banner appears at the
   top of `/collections` and `/decks` when the over-allocation set is non-empty; and decks holding an
   over-allocated card get a "to review" badge (the indicator the issue asks for).
3. **Reallocation lives on the over-allocations page**, not on every deck-card item — it needs a
   source-deck→target-deck choice that would overload the per-card row.
4. **The collection-index N+1 is left as-is**, tracked separately by issue #59. This feature reuses
   `Allocations::Availability` per card and does not optimise the aggregate query.
5. **`has_proxies` reconciliation is out of scope** (issue #56). The manual boolean stays; this
   feature derives proxy state from `owned_copies` for display and does not touch the flag.

## Architecture

Layering is unchanged: **views/controllers delegate to services; services own all logic.** The only
model addition is one derived reader.

### 1. Model

- `DeckCard#proxies` → `quantity - owned_copies`. A single tested reader replacing the ad-hoc
  `quantity − owned_copies` computed inline in the spec and (soon) in views. No other model change.
- `has_proxies` is untouched (issue #56).

### 2. JSON API

All three controllers use inline `render json:` with private `*_json` helpers today; we extend those
helpers and route create/update through the allocation services (currently they bypass them with
plain `save`/`update`, which is why UI-added cards on physical decks read as 100% proxy).

- **`Api::DeckCardsController`**
  - `deck_card_json` gains `owned_copies` and `proxies`.
  - `create` → `Decks::CardAdder` (greedy real backing) instead of additive `save`.
  - `update` with a `quantity` → `Decks::DeckCardQuantitySetter` (recaps `owned_copies`).
  - `update` with an `owned_copies` → `Decks::OwnedCopiesSetter` (bounded by availability).
  - Permit `:owned_copies` in addition to `:card_id, :quantity`.
- **`Api::CollectionsController`**
  - `collection_json` gains `owned`, `committed`, `available` (from `Allocations::Availability`).
  - `create` → `Collections::CardAdder`; `update` → `Collections::QuantitySetter`.
- **`Api::DecksController`**
  - `deck_json` gains `physical` and `tcg_live`; its nested `deck_card_json` gains
    `owned_copies` and `proxies`.

Invalid/out-of-bounds service calls surface as a 422 with the service's error message, matching the
existing controllers' error handling.

### 3. Web UI (Phlex components)

- **`Decks::DeckCardItem`** (per deck-card row): below the quantity control, a `2 réelles · 1 proxy`
  badge and a **stepper for `owned_copies`**, bounded to `0 … min(quantity, available + current
  owned_copies)`, wired via a new Stimulus controller to the `owned_copies` API update
  (`Decks::OwnedCopiesSetter`). A `⚠ sur-allouée` marker when the card is over-allocated.
- **`Collections::IndexView`** tile: a `poss. N · engagé M · dispo K` line per card, from
  `Allocations::Availability`.
- **Per-deck "to review" badge**: `Decks::ClassificationBadges` (shared by the deck list tile and the
  show header) gains a badge when the deck holds an over-allocated card.
- **`/over_allocations` page** (`OverAllocations::IndexView`, backed by a new
  `OverAllocationsController#index` calling `Allocations::OverAllocations`): one row per
  over-allocated card with owned/committed and the contributing decks, each row offering the
  **reallocate** control (`Decks::OwnedCopiesReallocator`: pick source deck → target deck).
- **Over-allocation banner**: a small shared component rendered at the top of `/collections` and
  `/decks` when `Allocations::OverAllocations` is non-empty, linking to `/over_allocations`.

### 4. Routing

- New top-level authenticated resource: `resources :over_allocations, only: [:index]`.
- New API update semantics reuse existing `Api::` routes (no new routes needed there).

## Data flow

1. UI action (stepper / reallocate / quantity) → Stimulus → `Api::` endpoint (or the
   `over_allocations` action for reallocation).
2. Controller → the matching service inside `serialized_transaction` (already the case in the
   services).
3. JSON response carries the recomputed `owned_copies`/`proxies` (or availability), letting the
   Stimulus controller update the row without a full reload; Turbo handles the over-allocation
   banner/badge refresh where a full render is simpler.

## Error handling

- Service validation failures (e.g. `owned_copies` beyond availability, negative quantity) → the
  controller returns 422 with the message, as the existing API actions already do for `save` errors.
- The over-allocation state itself is never an error — it is displayed, never blocked (base design
  decision #5).

## Testing

- **Model**: `DeckCard#proxies`.
- **API controllers**: each new field is present; `create`/`update` route through the services
  (e.g. adding to a physical deck backs reals; setting `owned_copies` beyond availability → 422;
  collection create/update go through the setters).
- **Phlex render tests**: `DeckCardItem` (real/proxy badge + stepper bounds + over-allocated marker),
  collection tile (owned/committed/available line), `ClassificationBadges` "to review" badge,
  `OverAllocations::IndexView`, and the banner component (present iff over-allocations exist).

## Out of scope

- Batching the collection-index availability N+1 → **issue #59**.
- Reconciling / deprecating `Deck#has_proxies` → **issue #56**.
- Foil-aware allocation (`collections.foil` still ignored).
- Deck legality enforcement → issue #61.

## Known seams

- The collection index issues one `Allocations::Availability` call per card (N+1) — acceptable this
  iteration, tracked in #59.
- ~~`has_proxies` and per-card `owned_copies`-derived proxy state remain two independent sources of
  truth; this feature reads from `owned_copies` and leaves the flag alone (#56).~~ **Closed:** the
  `decks.has_proxies` column was dropped and `Deck#has_proxies?` is now derived from
  `owned_copies`, so the badge and the deck-list filter read from the same source as this feature.
