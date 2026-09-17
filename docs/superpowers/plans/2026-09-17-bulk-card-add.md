# Plan — bulk card add

Spec: `docs/superpowers/specs/2026-09-17-bulk-card-add-design.md`.
Branch: `bulk-card-add`, off `master`, worktree `.claude/worktrees/bulk-card-add`.

## Frozen contract

Everything below is fixed before any lane starts. A lane consumes it; no lane renegotiates it.

### Constants

```ruby
AddCardsToCollectionTool::MAX_ENTRIES = 500   # and AddCardsToDeckTool::MAX_ENTRIES
Import::KINDS                                  # gains "bulk_cards"
```

### `Cards::ReferenceResolver` (new, `app/services/cards/reference_resolver.rb`)

```ruby
Cards::ReferenceResolver.call(entries:) # => Result

Entry  = Struct.new(:set_code, :set_number, :quantity, keyword_init: true)
Result = Struct.new(:resolved, :unresolved, keyword_init: true)
#   resolved   => [ { card:, quantity: } ], one per distinct card, source order of first appearance
#   unresolved => [ { set_code:, set_number:, reason: } ], reason is a String
```

- `entries` is an Array of Hashes with String or Symbol keys `set_code`, `set_number`,
  optional `quantity`.
- Normalisation: `set_code.to_s.squish.upcase`, `set_number.to_s.squish`. `quantity` defaults to 1.
- **Repeated `(set_code, set_number)` pairs are summed**, after normalisation.
- Refusal reasons, exact strings:
  - `"set code is missing"` — blank `set_code`
  - `"collector number is missing"` — blank `set_number`
  - `"quantity must be a positive integer"` — `quantity` present and not an Integer ≥ 1
  - `"no printing in the catalogue"` — resolved to no card
- Two passes, in this order: `Card.where(set_name: codes).where(set_number: numbers)` paired in
  Ruby, then `Card.in_set_code(code).find_by(set_number: number)` for whatever the first pass left.
- **Never fetches.** No `Cards::Fetcher`, no HTTP.

### `Collections::BulkCardAdder` (new, `app/services/collections/bulk_card_adder.rb`)

```ruby
Collections::BulkCardAdder.call(user:, resolved:) # => [ receipt_entry, … ]
# receipt_entry: { card_id:, set_name:, set_number:, name:, quantity:, before:, after: }
```

One `serialized_transaction`. Delegates each row to `Collections::CardAdder` — the backing rule and
the `"unknown"` language/finish defaults stay in one place. Order of the receipt matches `resolved`.

### `Decks::BulkCardAdder` (new, `app/services/decks/bulk_card_adder.rb`)

```ruby
Decks::BulkCardAdder.call(deck:, resolved:) # => [ receipt_entry, … ]
# receipt_entry: { card_id:, set_name:, set_number:, name:, quantity:, before:, after:,
#                  owned_before:, owned_after: }
```

One `serialized_transaction`. **One** `Allocations::Availability.for_cards(user: deck.user,
cards:, excluding_deck: deck)` for the whole batch, then `Allocations::Backing.greedy` per row.
`owned_*` are 0 on a non-physical deck and the row's `owned_copies` is left at 0, matching
`Decks::CardAdder`.

### The two tools

```ruby
AddCardsToCollectionTool  # wire name add_cards_to_collection, required_scope "mcp:write"
AddCardsToDeckTool        # wire name add_cards_to_deck,       required_scope "mcp:write"
```

`input_schema` for both: `entries` is a required array of objects with `set_code` (string),
`set_number` (`type: [ "string", "integer" ]`), `quantity` (integer, `minimum: 1`); `set_code` and
`set_number` required per item. `AddCardsToDeckTool` additionally requires `deck_key` (string).

Refusals, all through `error_text` (`isError: true`):

- empty `entries`, or not an Array → `"Error: entries must be a non-empty array."`
- more than `MAX_ENTRIES` → `"Error: at most 500 entries per call (got N)."`
- any unresolved entry → nothing written, and the text names every one:
  `"Error: N entries could not be resolved, nothing was written:\n  PBL 999 — no printing in the catalogue\n  …"`
- `AddCardsToDeckTool` only: unknown/foreign `deck_key` → the pre-existing `RecordNotFound` shape,
  through `error_text`.

Success, through `text`: a summary line plus one line per printing carrying name and before → after.

### `Import`

New column `receipt`, `json`, `null: false`, `default: []`. New kind `"bulk_cards"`, new scope
`bulk_card_imports`. `Admin::ImportsController::UNRETRYABLE_REASONS` gains
`"bulk_cards" => "A bulk card add cannot be retried: it adds copies rather than setting them, so replaying it would add them a second time."`

Label: `"Collection — 58 copies over 52 printings"` / `"Deck \"NAME\" — 60 copies over 24 printings"`,
pluralised.

## Lanes

The dependency chain is linear at its middle — resolver → adders → tools → response — so only the
two ends are genuinely disjoint, and that is the split. The middle I write myself after integrating,
because a lane boundary there would be a contract negotiated across a fan-out on every call.

**Lane R — resolution.** Files: `app/services/cards/reference_resolver.rb`,
`test/services/cards/reference_resolver_test.rb`. Nothing else. Depends on nothing in this branch.

**Lane T — traceability.** Files: the migration, `app/models/import.rb`,
`app/controllers/admin/imports_controller.rb`, `app/views/components/admin/imports/index_view.rb`,
`test/models/import_test.rb`, `test/controllers/admin/imports_controller_test.rb`,
`test/components/admin/imports/index_view_test.rb` (if the directory convention has one; otherwise
the controller test carries the rendering assertions). Depends on nothing in this branch.

Each lane runs in its own isolated worktree with its own `storage/test.sqlite3`. Neither touches the
other's files. I integrate both, then write `Collections::BulkCardAdder`, `Decks::BulkCardAdder`, the
two tools, `Mcp::ServerController::TOOLS`, `test/integration/mcp_scope_test.rb`'s `WRITE_TOOLS`, and
`docs/architecture/mcp-and-oauth.md`.

## Tests

Resolution (`test/services/cards/reference_resolver_test.rb`):

1. 52 real references from the spec resolve to 52 cards, 58 copies — the measurement, as a test.
2. Repeated pairs are summed: `MEE 6, 7, 8, 8, 2, 6` → four rows, quantities 2/1/2/1.
3. Repetition and an explicit `quantity` combine: `{PBL 56}, {PBL 56, quantity: 3}` → 4.
4. `set_code` is matched case-insensitively — lowercase `pbl` resolves.
5. A card whose stored `set_name` is lowercase still resolves (second pass). Requires a fixture
   written that way, since 0 of 4916 production rows are.
6. `set_number` accepts the Integer 56 and the String `"56"` identically.
7. `"GG1"`-style alphanumeric numbers resolve; `" 56 "` and a U+00A0-padded `"56"` resolve.
8. An unknown number in a known set is `"no printing in the catalogue"`, not an exception.
9. A blank `set_code`, a blank `set_number`, and `quantity: 0` each produce their exact reason.
10. **Nothing is fetched**: stub `Cards::Fetcher` to raise, resolve a miss, assert no call.
11. Flat query cost: resolving 2 references and 52 references costs the same number of statements,
    measured inside `ActiveRecord::Base.uncached` (the query cache hides repeats, and has fooled a
    measurement in this repository three times).

Write services:

12. `Collections::BulkCardAdder` sums onto an existing row and creates a missing one in one call.
13. It writes `language`/`finish` `"unknown"` and never a second row for the same card.
14. Receipt `before`/`after` match the database after the call.
15. `Decks::BulkCardAdder` on a physical deck backs greedily and agrees, row for row, with what
    looping `Decks::CardAdder` would have produced — asserted against the loop, not against a
    transcribed constant.
16. On a non-physical deck `owned_copies` stays 0.
17. Flat query cost on the deck side: 10 printings and 40 printings cost the same availability
    statements, inside `uncached`.
18. A raise mid-batch rolls the whole batch back (sabotage-shaped: force the last row invalid).

Tools:

19. Both tools refuse an empty `entries`, a non-array, and 501 entries, each with `isError: true`.
20. One unresolved entry → **nothing written** (collection and deck row counts unchanged), `isError:
    true`, and the text names that entry and no other.
21. Success writes exactly one `Import`, `kind: "bulk_cards"`, `status: "completed"`, receipt length
    equal to the distinct printing count, label carrying both counts.
22. A refusal writes **no** `Import`.
23. `add_cards_to_deck` refuses another user's deck key and writes nothing.
24. `mcp_scope_test.rb`: a read-only token sees neither tool; a read-write token sees both.

Admin:

25. `"bulk_cards"` is not in `RETRYABLE_KINDS`; Retry on one redirects with the exact sentence.
26. Undo on one is refused.
27. The index renders the receipt disclosure for a `bulk_cards` row and renders nothing extra for a
    kind whose receipt is `[]`.

## Verification

Container, per the project memory: image `cartodex-test:4.0.6`, volume `cartodex-bundle-406`.
Gates, all five: `bin/brakeman --no-pager`, `bin/importmap audit`, `bin/rubocop`,
`bin/rails db:test:prepare test test:system`, `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`
(system tests on the host — no Chrome in the image). Baseline run count recorded before any change.
