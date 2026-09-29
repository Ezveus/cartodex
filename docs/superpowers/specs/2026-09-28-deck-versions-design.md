# Deck versions — design

Date: 2026-09-28. Status: agreed with the owner through a one-question interview; this file
records the decisions and the measurements behind them.

## Problem

A physical deck is edited in place — that mirrors what happens to the cards on the table — while
its `DeckResult`s keep accumulating against "the deck", with no record of which list, which format
or which Standard pool a match was played with. Measured on a production copy, deck 1281
(`DPra_QHkj0XCtVILFfxDGw`, physical, pool 9 = TEF-PBL, 31 rows):

| Result | played_at | Participation | List actually played |
|---|---|---|---|
| #118 | 2026-09-17 06:39 | — | A |
| #122–125 | 2026-09-22 17:43–19:42 | entry 2 | A |
| #126–129 | 2026-09-23 17:59–19:36 | entry 4 | B |

The list was last edited 2026-09-23 16:40 (`MAX(deck_cards.updated_at)`), between the two
participations. List A exists nowhere in the database: `deck_cards` holds the current state only.
30C becomes legal on 2026-10-02, which will change the pool under the same deck a second time.

Scale of the backfill (same copy): 123 results over 24 decks, 6 tournament entries, no result with
a NULL `played_at`.

## Decisions

1. **A version is an immutable snapshot**: per-printing quantities, `format`, `standard_pool_id`,
   `other_format_name`, and an `effective_at` date. The deck's live list may diverge from its
   latest version; editing the deck never touches a version. Allocation (`owned_copies`) is not
   snapshotted — it is present-state inventory, not a property of the list played.
2. **Drift** is "the live deck differs from its latest version", compared by **fingerprint** and
   summed quantity plus the three format columns. A printing swap, a proxy→real change or a
   re-save therefore is not drift. A card with no fingerprint is compared by `card_id`.
3. **Two ways to create a version** (owner choice "mix of A and C"):
   - explicit: "New version" on the versions page, allowed only while there is drift (or no version
     at all);
   - on logging a result while there is drift: the modal offers three choices — *create version
     N+1 and attach*, *attach to version N (the list changed after this match)*, *cancel*.
   A deck with **no version at all** gets version 1 silently on its first result: there is no
   "version N" to offer.
4. **Tournament entries carry the version**, and their results inherit it. The three-choice
   prompt happens when the entry is created; a result attached to an entry (through the modal,
   the result edit form or `attach_results`) takes the entry's version without a question, and a
   validation refuses a result whose version differs from its entry's. Moving an entry to another
   version moves its results in the same transaction.
5. **Backfill**: every deck with at least one result or entry gets version 1 = its current list,
   `effective_at` = `MAX(deck.created_at, MAX(deck_cards.updated_at))` — for deck 1281 that is
   2026-09-23 16:40, the true start of list B. All its results and entries are attached to it.
   Both foreign keys are then `NOT NULL`.
6. **Reconstructing the past**: "Add an earlier version" takes a pasted decklist
   (`Decks::Fetcher::CARD_LINE_RE` lines), a date and the format fields, resolves printings through
   `Cards::ReferenceResolver` (never fetches; one unresolved line refuses the whole list), and
   creates a version. Results and entries are then moved onto it through a version select on the
   result edit form and the entry edit form.
7. **Numbering is derived, never stored**: a version's number is its rank by
   `(effective_at, id)` within its deck, so inserting A before B renumbers both correctly.
   `effective_at` is editable (content is not), to correct the backfill's estimate.
8. **A version is deletable only when nothing is attached** (no result, no entry):
   `dependent: :restrict_with_error` on both associations. Deleting a deck deletes its versions
   after its results (declaration order).
9. **Owner only.** The versions page and the diff sit behind the rule `#stats` uses; nothing new is
   public, the shared deck page is untouched.
10. **Stats**: `/decks/:id/stats` opens with one row per version — number, period, format/pool,
    W/L/D/T, win rate, link to the diff with the previous version — and the existing detail is
    scoped by `?version=N`, defaulting to all versions (a fresh version has zero results).
11. **Diff** reuses `Decks::Comparator` unchanged: a version answers `id`, `name` and
    `deck_cards` (rows with `card` and `quantity`), which is all it reads.
12. `Decks::Duplicator` copies no version (allowlist, unchanged). No MCP tool writes results, so
    the prompt concerns two write paths only: `Api::DeckResultsController#create` and
    `Tournaments::EntriesController#create`.

## Schema

- `deck_versions`: `deck_id` NOT NULL FK, `effective_at` datetime NOT NULL, `format` NOT NULL,
  `standard_pool_id` FK nullable, `other_format_name`, timestamps. Index `(deck_id, effective_at)`.
- `deck_version_cards`: `deck_version_id` NOT NULL FK, `card_id` NOT NULL FK, `quantity` NOT NULL
  (> 0). UNIQUE `(deck_version_id, card_id)`.
- `deck_results.deck_version_id` and `tournament_entries.deck_version_id`: NOT NULL FK after
  backfill, indexed.
- Model invariants: a result's / entry's version belongs to the same deck; a result with an entry
  has the entry's version.

## Write-path protocol

`POST /api/decks/:key/results` accepts `version_choice` = `new` | `current`. With drift, an
existing version, no entry and no choice, it answers **409** with
`{ drift: true, current_version: N, next_version: N+1 }` and writes nothing; the modal shows the
three choices and resubmits. The entry create form behaves the same way server-side: with drift and
no choice it re-renders (422) with the choice radios visible.

## Out of scope

- Public version history (decided: owner only).
- Automatic version assignment by `played_at` (rejected: a deleted card leaves no timestamp).
- Snapshotting allocation.
