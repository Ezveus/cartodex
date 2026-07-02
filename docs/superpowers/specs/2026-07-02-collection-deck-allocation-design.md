# Collection ↔ Deck Allocation (real copies vs proxies) — Design

**Date:** 2026-07-02
**Status:** Draft — awaiting user review
**Supersedes:** the transfer semantics of `2026-07-01-collection-deck-mcp-design.md` (the `move_card_to_deck` / `move_card_from_deck` "transfer" model is replaced by the allocation model below).

## Goal

Model a Pokémon TCG collection as **physically-owned cards**, and let decks draw on that
collection without ever inflating how many copies you actually own. A physical deck may contain
more copies of a card than you own — the surplus are **proxies**. The number of **real** (owned-backed)
copies committed across all physical decks can never exceed what you own.

## Vocabulary

- **Owned** `owned(X)` — copies of card `X` physically owned by the user (`collections.quantity`).
- **Real / owned copy** — a copy in a deck that is backed by a physically-owned card.
- **Proxy** — a copy in a deck not backed by an owned card.
- **Committed** `committed(X)` — sum of real copies of `X` across all of the user's **physical** decks.
- **Available** `available(X)` — `max(0, owned(X) − committed(X))`: owned copies not yet backing any deck.

## Confirmed decisions (from the brainstorming interview)

1. **Add to a physical deck is auto-split, overridable.** Adding copies backs as many reals as
   available, then fills the rest with proxies; the user may force a slot to stay a proxy even when
   a real is available (e.g. to keep the physical card safe).
2. **Collection is the source of truth for ownership.** You may add unlimited copies to the
   collection, and reduce it freely. It is **never** decremented by deck usage.
3. **A deck can hold unlimited copies** (proxies are unbounded). The constraint is only on the
   *real* copies.
4. **Global invariant (physical decks):** `committed(X) ≤ owned(X)`. A single physically-owned copy
   backs at most one physical deck at a time.
5. **Reconciliation on collection decrease = signal for review.** If reducing `owned(X)` makes
   `committed(X) > owned(X)`, the over-allocated state is **tolerated and surfaced**, never
   auto-corrected and never blocked. The user rebalances manually.
6. **Move between decks = pure conversion.** Moving a real copy from deck A to deck B does not
   change either deck's size: in A the freed slot becomes a proxy, in B a proxy slot becomes real.
   The model therefore stores, per `deck_card`, a **total quantity** and a **number of real copies**.
7. **`physical` alone drives allocation** (assumption — flagged; confirm on review). `physical=true`
   ⇒ real/proxy backing and collection accounting apply, regardless of `tcg_live`. `physical=false`
   ⇒ no backing ever (`owned_copies` forced to 0), and you cannot pull from the collection. `tcg_live`
   is an orthogonal label with no effect on allocation. `physical` and `tcg_live` remain independent
   booleans (a deck may be both, or neither).
8. **Scope:** domain model + MCP tools only. No web UI/API rework beyond not breaking existing
   behavior.

## Data model

- **`collections.quantity`** — unchanged meaning: copies owned. Source of truth. Add unlimited;
  reducible to 0.
- **`deck_cards.owned_copies`** — NEW `integer`, `default: 0`, `null: false`. `quantity` remains the
  **total** copies in the deck. `proxies = quantity − owned_copies`. Local invariant:
  `0 ≤ owned_copies ≤ quantity`. For a non-physical deck, `owned_copies` is always `0`.
- **`decks`** — columns unchanged. `physical`, `tcg_live`, and `has_proxies` stay exactly as today
  (they back existing filters, badges, the form, and the duplicator, all out of scope here). We do
  **not** introduce a `medium` enum and do **not** derive/drop `has_proxies` this iteration. (Note:
  `has_proxies` may drift from the true proxy state derivable from `owned_copies`; reconciling it —
  and the UI — is deferred to a later iteration.)

### Derived quantities (query layer, not stored)

- `committed(X)` = `Σ deck_cards.owned_copies` over the user's physical decks for card `X`.
- `committed_excluding(X, D)` = `committed(X)` minus deck `D`'s own `owned_copies` for `X`.
- `available_for(X, D)` = `max(0, owned(X) − committed_excluding(X, D))` — the largest
  `owned_copies` deck `D` may hold for `X`.
- **Over-allocated** card: `committed(X) > owned(X)`. A deck is **"to review"** if it contains an
  over-allocated card. Both are derived, never stored.

## Operations

All operations are per authenticated user and transactional where they touch more than one row.
Business logic lives in `app/services/` (`ApplicationService.call`); MCP tools stay thin.

### Collection

- **Add** `add_card_to_collection(card_id, quantity)` — increments `owned` (exists; keep the
  `quantity ≥ 1` guard).
- **Set** `set_collection_quantity(card_id, quantity)` — sets `owned(X)` to an exact `quantity ≥ 0`
  (0 allowed). Never blocked; may create a tolerated over-allocation. This is how a sale/loss is
  recorded.

### Deck cards

- **Add** `add_card_to_deck(deck_id, card_id, quantity)` — increases the deck's total for the card by
  `quantity`. If the deck is **physical**, bump `owned_copies` to
  `min(new_total, current_owned + available_for(X, D))` (auto-split: reals first, remainder proxies).
  If non-physical, `owned_copies` stays 0. *(Overriding the split at add time is done with a
  follow-up `set_deck_card_owned_copies` call; the add tool itself does the greedy auto-split.)*
- **Set the real/proxy split** `set_deck_card_owned_copies(deck_id, card_id, owned_copies)` — sets the
  real count `n` for a **physical** deck's card. Bounds: `0 ≤ n ≤ quantity` **and**
  `n ≤ available_for(X, D)` (so an edit can never push `committed` above `owned` — over-allocation is
  reachable only via a collection decrease). Rejected with a clean error on a non-physical deck.
- **Reallocate reals between decks** `reallocate_owned_copies(from_deck_id, to_deck_id, card_id, quantity)`
  — moves `quantity` real copies from deck A to deck B (both physical). Requires
  `A.owned_copies ≥ quantity` and `B.owned_copies + quantity ≤ B.quantity` (B must have proxy slots to
  convert). Pure conversion: `committed(X)` is unchanged, the invariant is preserved, the collection
  is untouched.
- **Set total / remove** `set_deck_card_quantity(deck_id, card_id, quantity)` — sets the deck's total
  for the card to `quantity ≥ 0` (0 removes the row). `owned_copies` is recapped to
  `min(owned_copies, quantity)`.

### Removed

- `move_card_to_deck` and `move_card_from_deck` (the old collection-decrementing "transfer" tools) are
  **removed**, along with the `Decks::CardTransfer` service. Their intent is now covered by
  `add_card_to_deck` (auto-backing) + `set_deck_card_owned_copies` / `reallocate_owned_copies`
  (adjusting the backing), with the collection never decremented.

## Reconciliation / over-allocation

- No operation auto-corrects allocation. A collection decrease that makes `committed(X) > owned(X)` is
  allowed and leaves the affected physical decks over-allocated.
- The over-allocated state is **derived and surfaced** (see `list_over_allocations`), never persisted
  and never blocking. The user resolves it with `set_deck_card_owned_copies` (demote reals to proxies)
  or `reallocate_owned_copies`.
- Editing up (`set_deck_card_owned_copies`, `reallocate_owned_copies`, the auto-split in
  `add_card_to_deck`) can never create over-allocation — it is capped by `available_for`.

## Medium changes

- When a deck's `physical` flag transitions to **false**, all its `deck_cards.owned_copies` are reset
  to 0 (the reals are released back to `available`). Enforced by a `Deck` model callback.
- A deck with `physical=false` rejects `set_deck_card_owned_copies` and `reallocate_owned_copies`, and
  `add_card_to_deck` never backs reals for it.

## MCP tools (final surface)

**Write:** `add_card_to_collection` (kept), `set_collection_quantity` (new),
`add_card_to_deck` (kept, extended with the physical auto-split), `set_deck_card_owned_copies` (new),
`reallocate_owned_copies` (new), `set_deck_card_quantity` (new). Removed: `move_card_to_deck`,
`move_card_from_deck`.

**Read:** `search_cards` (kept), `list_decks` (kept; add `physical`/`tcg_live` to output),
`list_collection` (extended → `{card_id, name, owned, committed, available}`),
`list_deck_cards` (extended → per card `{quantity, owned_copies, proxies}`),
`list_over_allocations` (new → cards where `committed > owned`, with the contributing decks).

## Out of scope

- Web UI and JSON API rework (must keep compiling/passing; the existing `Api::DeckCardsController`
  add/update leaves `owned_copies` at its default — acceptable this iteration).
- Deriving/auto-maintaining `has_proxies` from `owned_copies`, and any UI for real/proxy/over-allocation.
- Foil-aware allocation (`collections.foil` ignored; a card is identified by its printing / `card_id`).
- Deck legality (e.g. max 4-of) enforcement.
- API token expiry (tracked separately).

## Testing

Service/model level (Minitest, fixtures):

- **Availability:** `available_for` with zero/some/all copies committed, across multiple physical
  decks; non-physical decks excluded from `committed`.
- **Auto-split on add:** reals-first then proxies; capped by availability; a second physical deck gets
  proxies once the first exhausted the owned copies (the Kirlia A/B example).
- **Override:** `set_deck_card_owned_copies` within bounds; rejects `n > quantity`,
  `n > available_for`, and any call on a non-physical deck.
- **Reallocation:** A→B moves reals, sizes unchanged, `committed` unchanged; rejects when A lacks reals
  or B lacks proxy slots; rejects on a non-physical deck.
- **Collection decrease → over-allocation:** `set_collection_quantity` below `committed` leaves the
  state over-allocated (not blocked), and `list_over_allocations` reports it; a later
  `set_deck_card_owned_copies` clears it.
- **Medium change:** flipping `physical` to false zeroes `owned_copies`.
- **Cross-user isolation** for every tool.

## Worked example (the Kirlia SIT scenario)

Own 3 Kirlia SIT. Deck A (physical) add 4 → A: `quantity 4, owned_copies 3` (1 proxy);
`available = 0`. Deck B (physical) add 4 → B: `quantity 4, owned_copies 0` (4 proxies). Reallocate 1
from A→B → A: `owned_copies 2` (2 proxies), B: `owned_copies 1` (3 proxies); total real still 3.
Sell one (`set_collection_quantity 2`) → `committed = 3 > owned = 2` → over-allocated, surfaced;
user demotes one real (`set_deck_card_owned_copies`) to restore `committed = 2`.
