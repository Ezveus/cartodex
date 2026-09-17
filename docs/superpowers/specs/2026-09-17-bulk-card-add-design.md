# Bulk card add — one MCP call for a whole booster-box opening

**Status**: design, 2026-09-17
**Issue**: none. The spec is a usage report written by a chat session driving the MCP connector,
reproduced in `docs/superpowers/plans/2026-09-17-bulk-card-add.md`.

## The measurement that motivates this

A player opens boosters and pastes what came out, grouped by set, duplicates expressed by repeating
the number:

```
MEG 131, 131
PFL 85, 86
JTG 55
DRI 34, 136
MEE 6, 7, 8, 8, 2, 6
ASC 39, 61
POR 70
PBL 56, 56, 19, 23, 36, 66, 81, 26, 77, 57, 85, 59, 44, 3, 11, 13, 64, 77, 6, 18, 88, 28
CRI 44, 28, 8, 16, 74, 69, 75, 67, 87, 13, 30, 52, 14, 46, 57, 32, 80, 42, 97, 42
```

58 copies, 52 distinct printings, 9 sets. Under today's tools that is **104 round trips**: 52
`search_cards(set_code:, set_number:)` to turn each reference into a `card_id`, then 52
`add_card_to_collection(card_id:, quantity:)`. The run saturated the per-response call budget twice
and had to be resumed by hand twice.

Three things were measured on the development catalogue (4916 cards) by replaying those exact 52
references:

- **52 of 52 resolved, each to exactly one card.** No ambiguity, no miss.
- `(set_name, set_number)` is unique at scale and **stays unique under case folding**: 4916 cards,
  4916 distinct pairs, 4916 distinct pairs after `UPPER()`. So the resolution step carries no
  information a caller could not have inferred — half of the 104 calls were pure loss.
- `PBL 3` and `PBL 85` are two different *Fomantis*. The number is the key; the name never is.

## What this adds

Two MCP tools, one shared resolution path:

```
add_cards_to_collection(entries: [{ set_code:, set_number:, quantity? }, …])
add_cards_to_deck(deck_key:, entries: [{ set_code:, set_number:, quantity? }, …])
```

104 round trips become 1.

### Entries are a copy of the list, not a reduction of it

`quantity` is optional and defaults to 1, and **repeating a `(set_code, set_number)` pair is legal**:
the tool sums the repeats. `MEE 6, 7, 8, 8, 2, 6` is transcribed as six entries in source order, and
the server arrives at `6 ×2, 7 ×1, 8 ×2, 2 ×1`.

This is the whole reason raw-text ingestion was refused rather than built. The danger in making the
caller aggregate is not transcription, it is **arithmetic**: a wrong reduce is silent, and nothing on
the server can see it, because the server only ever receives the already-summed number. Accepting
repetition moves the counting to the server — exactly what a text parser would have bought — at the
price of nothing at all.

A text parser would have cost a grammar. The repository already owns one decklist parser
(`Decks::Fetcher`, the PTCG `QUANTITY NAME SET NUMBER` format) and has already arbitrated, at length,
what "MEG 113" means when a set code collides with a card name — 12 of the 28 imported set codes are
substrings of card names, and 224 two-token queries were deliberately sent to empty so that the
printing reading wins (see **`CardSearchable` reads "POR 56" as a printing** in `CLAUDE.md`). The
paste format above is one person's shorthand, not a standard. A third reader of those same tokens
would reopen that arbitration for no gain this design does not already have.

### Nothing is ever scraped

A reference the catalogue does not hold is `not_found`. It is **not** a fetch — the same rule
`Cards::Printings` states. A booster from a set nobody has imported yet answers with 58 refusals
naming the set, and the fix is an admin set import, not a per-card network round trip inside a write
transaction. This is also what keeps the write transaction short; see the `Decks::Fetcher` note in
`CLAUDE.md` about holding SQLite's single write lock for 15–30 s.

### All or nothing

If any entry fails to resolve, **nothing is written** and the call answers through
`McpTool.error_text` (`isError: true`), naming every unresolved entry with its reason.

This is the decision that makes the feature safe rather than merely fast, and it is worth spelling
out why partial application was refused. The original hazard — the one that produced two manual
resumptions — is that `add_card_to_collection` is *relative*: an interrupted run cannot be replayed,
because replaying it adds the copies that already landed a second time. Under one atomic call that
hazard disappears, but only if the failure mode is "nothing happened":

- **Refusal → nothing written → the retry is safe by construction.** The caller fixes the typo and
  sends the whole list again.
- Partial application would resurrect it exactly: 49 written, 3 refused, and a caller that resends
  the message adds 49 more copies.

That is also why this design carries **no idempotency key**. A caller-supplied `import_key` under a
uniqueness constraint was proposed; one atomic call makes it answer a question that can no longer be
asked. The one residual — "my call timed out, did it land?" — is answered by the `Import` row below,
which is a read, not a constraint.

Two refusals are deliberately *not* errors of this kind, because they are legal states rather than
bad input: an entry whose set exists but whose number does not is `not_found` like any other, and a
deck key that is not the caller's is the pre-existing `RecordNotFound` refusal of `find_deck!`.

## Resolution: one query, indexed, and the case rule kept honest

`cards` carries `index_cards_on_set_name_and_set_number (set_name, set_number) UNIQUE`. Four ways to
resolve 52 references against it were measured on the development catalogue, with
`EXPLAIN QUERY PLAN` and a timer:

| Form | Plan | Time | Rows read |
|---|---|---|---|
| A — 52 × `(UPPER(set_name) = ? AND set_number = ?)` OR'd together | **SCAN** (covering) | 0.025 s | 52 |
| B — `(set_name, set_number) IN (VALUES …)`, input upcased in Ruby | SEARCH + bloom filter | 0.000068 s | 52 |
| C — `set_name IN (…) AND set_number IN (…)`, paired in Ruby | SEARCH | 0.00014 s | **357** |
| D — `(UPPER(set_name), set_number) IN (VALUES …)` | **SCAN** (covering) | — | 52 |

The rule the table hides: **any case-insensitive form scans**, because `UPPER(set_name)` is what the
composite index cannot be searched on. A and D are the case-insensitive forms and both scan; B and C
are indexed and both depend on the stored value already being uppercase.

`Card.in_set_code` keeps `UPPER` on both sides on purpose — `CLAUDE.md` records that nothing enforces
the casing, since `Cards::Fetcher` takes `set_name` from a URL path segment. Measured today, **0 of
4916 rows deviate from uppercase**. So the invariant holds but is not guaranteed, and a resolver that
simply assumed it would be wrong silently, on exactly the row that broke it.

The resolution is therefore **two passes**:

1. **Form C over upcased input**, in one indexed query: `Card.where(set_name: codes.map(&:upcase))
   .where(set_number: numbers)`, paired back to the entries in Ruby. This resolves everything under
   the invariant. It over-fetches by the cross-product of distinct codes × distinct numbers — 357
   rows for the 52 real references, and bounded above by the table itself: the deliberately absurd
   case of all 56 codes against 400 numbers returns the whole 4916-row catalogue in 6 ms.
2. **Only for entries the first pass did not resolve**, a second chance through the existing
   `Card.in_set_code` scope — the scanning, case-insensitive form. This costs a scan per unresolved
   entry, and unresolved entries are the path that is already about to refuse the whole call; 0 of
   52 took it on the real data.

Form C is chosen over the faster form B because it is ordinary Active Record rather than hand-built
row-value SQL, and because it makes the fallback natural: B would have had to be written as raw SQL
*and* would have depended on the same unenforced invariant with nothing to catch it.

Both `set_code` and `set_number` are `squish`ed, never `strip`ped, and `set_number` is declared
`type: [ "string", "integer" ]` — both for the reasons `SearchCardsTool` already records: 100
printings carry `GG1`-style numbers so there is no integer to cast to, an assistant reading "86" off
a card sends the integer as often as the string, and a copy-paste out of a web page carries U+00A0
that `String#strip` leaves in place.

## Writing: flat query cost, and why the deck side may be batched

`Collections::BulkCardAdder` and `Decks::BulkCardAdder` each wrap one `serialized_transaction`.

On the collection side there is nothing subtle: one row per `(user, card, language, finish)`. **The
tool does not expose `language` or `finish`** and leaves `Collections::CardAdder`'s `"unknown"`
defaults in place. The `collections` unique index is `(user_id, card_id, language, finish)`, not
`(user_id, card_id)`: a tool that exposed those two would let a caller write a *second* row for the
same printing and quietly split the owned count in two. No existing caller sets them.

The deck side looks like it has to be sequential and does not. `Decks::CardAdder` recomputes
`Allocations::Availability` per card because the greedy backing rule needs the pool the collection
leaves free to this deck. But **availability is keyed on `card_id`, and after aggregation each
`card_id` appears exactly once**: `collections` and `deck_cards` are both per-card-id, so adding
printing A never moves printing B's pool, even when the two are printings of the same card — that
equivalence lives in `fingerprint`, which allocation does not read. The bulk adder therefore calls
`Allocations::Availability.for_cards(user:, cards:, excluding_deck: deck)` **once** — the batched
form that exists precisely for this ("callers that render a whole collection or decklist must use
this") — and applies `Allocations::Backing.greedy` per row from its result.

That is 3 queries for the availability of a 60-card list instead of 180, and it is the same rule, not
a second implementation of it: `Backing.greedy` is still the only place the backing rule is written,
which is what keeps this from disagreeing with `Decks::CardAdder` and `Cards::Printings`' projection.

A field list (ownerless deck) is unreachable here for free: `find_deck!` is `user.decks.find_by!`.

## Traceability: one `Import` row, a new kind, a receipt

Both tools write one `Import` on success, `kind: "bulk_cards"`, `status: "completed"`, with a label
naming the target and the two counts — `Collection — 58 copies over 52 printings`, or
`Deck "Raging Bolt ex" — 60 copies over 24 printings`. On a refusal **no `Import` is written**, for
the same reason nothing else is: the run did not happen.

`imports` gains a JSON column `receipt`, `null: false, default: []`, one object per resolved
printing:

```json
{ "card_id": 4647, "set_name": "PBL", "set_number": "56", "name": "Ultra Ball",
  "quantity": 2, "before": 1, "after": 3 }
```

The deck shape adds `owned_before` / `owned_after`. JSON rather than a join table for the reason
`created_standing_ids` gives: it is read whole by a human and never joined, aggregated or indexed.
Default `[]` rather than nil so a reader never nil-checks first.

The receipt is what makes the row genuinely traceable rather than merely present, and it is what the
response is built from — which closes the last of the reported problems: the summary handed back to
the user today is assembled from 52 individual acknowledgements, never from a re-read of the
resulting state.

`"bulk_cards"` is **not retryable**. It goes in `Admin::ImportsController::UNRETRYABLE_REASONS`, not
in `RETRYABLE_KINDS`, and the reason is stronger than the usual "what it was run from is not stored":
here it *is* stored, and replaying it is precisely the thing this design exists to make impossible —
a relative add applied twice. The allowlist shape of `RETRYABLE_KINDS` means a kind that is simply
forgotten already falls through to a refusal; the explicit sentence is so the admin reads why.

It is not undoable either. An undo is buildable from the receipt and is deliberately out of scope:
nobody has asked for one, and `Tournaments::StandingsImportUndo` is the precedent for how much
surface one costs.

## Bounds

`MAX_ENTRIES = 500` per call, refused through `error_text` above it. The largest real payload
measured is 58; a Commander-sized deck is 100. The bound exists so that the one-query resolution and
the in-memory aggregation stay bounded by something other than the caller's imagination, and 500
entries is 556 bind variables against SQLite 3.51's 32766 limit.

The MCP per-user quota (300 calls/min) needs no change: this feature removes calls.

## What is deliberately not here

- **Raw-text ingestion** (`import_collection(text:)`). Argued above.
- **An idempotency key.** Argued above.
- **Partial application**, and any `skip_unknown` opt-in for it. Argued above; it can be added later
  without moving anything, since the refusal already carries the per-entry reasons that a partial
  mode would need.
- **`language` / `finish`.** Argued above.
- **An undo.** Argued above.
- **Any change to `search_cards`.** Its contract is unchanged; this feature removes the need to call
  it 52 times, not the tool.
