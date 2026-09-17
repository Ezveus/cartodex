# Plan — bulk card add

Spec: `docs/superpowers/specs/2026-09-17-bulk-card-add-design.md`.
Branch: `bulk-card-add`, off `master`, worktree `.claude/worktrees/bulk-card-add`.

## Frozen contract

Everything below is fixed before any lane starts. A lane consumes it; no lane renegotiates it.

### Constants

```ruby
BulkAdd::MAX_ENTRIES = 500                   # the module both tools extend
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

New column `receipt`, `json`, `null: false`, `default: []`. New kind `"bulk_cards"`. **No new
scope**: the four that exist each have a caller, and one nothing reads is asserted about by nothing.

**Receipt keys are Strings, everywhere.** `receipt` is a `json` column, so a row re-read from the
database hands its keys back as Strings whatever was written. A view or a response reading
`entry[:name]` renders empty against a persisted row while every "the node is present" and
"length == N" assertion stays true. Writers build String keys; readers use String keys; the tests
assert against a **reloaded** row.

`Admin::ImportsController::UNRETRYABLE_REASONS` gains
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

Corrected against `ship-plan-adversary`, which found ten decisions the suite as first planned would
not have noticed. Each correction is marked **[adv]** and says what it separates.

Resolution (`test/services/cards/reference_resolver_test.rb`):

1. A batch of the spec's shape resolves: several sets, several numbers, sums correct. Fixtures hold
   13 cards, so this is the spec's measurement in miniature, not its 52 references.
2. Repeated pairs are summed and **`resolved` is asserted as an ordered array**: `MEE 6, 7, 8, 8, 2,
   6`-shaped input over fixture cards gives quantities `[2, 1, 2, 1]` in source order. **[adv]** Pass
   1 returns rows lexicographically by `(set_name, set_number)`, which is neither source nor numeric
   order, so an ordered assertion is what separates them.
3. Repetition and an explicit `quantity` combine: `{POR 56}, {POR 56, quantity: 3}` → 4.
4. **[adv] Summing is keyed on the *normalised* pair, not the raw one.** One call mixing three
   spellings of one printing — `{set_code: "POR", set_number: 56}`, `{set_code: " por ",
   set_number: "56"}`, `{set_code: "POR", set_number: " 56"}` — gives `resolved.size == 1`,
   `quantity == 3`.
5. **[adv] The second pass exists.** Create a `Card` with `set_name: "por"` lowercase (nothing
   upcases it — `Card` carries only `compute_fingerprint` and `normalize_name`), resolve
   `set_code: "POR"` against it, assert it lands in `resolved` and `unresolved` is empty. `set_name`
   is BINARY-collated, confirmed, so pass 1 genuinely cannot answer it. **Sabotage gate: deleting
   pass 2 must turn this red** — the "lowercase `pbl` resolves" test cannot, since normalisation
   upcases the input before pass 1 ever runs.
6. **[adv] The cross-product over-fetch is re-paired, not guessed.** Fixtures already hold `POR 56`
   and `TWM 56`: ask for `POR 56` and `TWM 57` in one call and assert `TWM 57` is unresolved while
   `POR 56` resolved — a naive `index_by(:set_number)` answers both.
7. `set_number` accepts the Integer `56` and the String `"56"` identically; `"GG1"`-style numbers
   resolve; `" 56 "` and a **literal U+00A0**-padded `"56"` resolve.
8. An unknown number in a known set is `"no printing in the catalogue"`, not an exception.
9. A blank `set_code` and a blank `set_number` each produce their exact reason.
10. **[adv] `quantity` refuses non-Integers, not only 0.** A case each for `0`, `-1`, `"3"`, `2.9`
    and `true`, each asserting the exact reason on that entry and that nothing resolved; plus
    `quantity` absent and `quantity: nil` both defaulting to 1 rather than being refused. This is
    what `McpTool#positive_quantity?` exists for — an in-process call bypasses the schema minimum.
11. **Nothing is fetched**: stub `Cards::Fetcher` to raise, resolve a miss, assert no call.
12. Flat query cost: 2 references and 52 references cost the same statements, inside
    `ActiveRecord::Base.uncached`.

Write services:

13. `Collections::BulkCardAdder` sums onto an existing row and creates a missing one in one call.
14. It writes `language`/`finish` `"unknown"` and never a second row for the same printing.
15. Receipt `before`/`after` match the database after the call, read off a **reloaded** row with
    String keys. **[adv]**
16. **[adv] `Decks::BulkCardAdder` really passes `excluding_deck:` and the row's `current_owned`.**
    A physical deck already holding the printing at `quantity 1, owned_copies 1`, user owning 3: add
    2 and assert `owned_copies == 3`. Omitting `excluding_deck:` gives 2; hard-coding
    `current_owned: 0` also gives 2. Include a second row where owned < quantity so the greedy cap
    is exercised. The comparison against a `Decks::CardAdder` loop runs from the **same** starting
    state on the **same** deck, rolled back between arms — a loop arm on a second deck legitimately
    disagrees, because the first arm has already consumed the collection.
17. On a non-physical deck `owned_copies` stays 0.
18. **[adv] Flat availability cost, pinned to the literal.** Inside `uncached`, exactly 3 statements
    matching the grouped `SUM` on `collections`/`deck_cards` — that is what `for_cards` costs with
    `excluding_deck:` — at 10 printings and again at 40. Asserting the two counts merely agree is
    satisfied by a per-row `Availability.call` once the filter matches nothing.
19. A raise mid-batch rolls the whole batch back.

Tools:

20. Both tools refuse an empty `entries`, a non-array and 501 entries. **[adv] Each refusal asserts
    `response.to_h[:isError]`**, the way `read_tools_test.rb` does — `text("Error: …")` and
    `error_text("Error: …")` are byte-identical in the text block and only that flag separates them.
21. **[adv] All-or-nothing asserts quantities, not row counts.** A batch mixing one resolvable entry
    with one unresolved one, against fixtures that already hold the target rows: after the refusal
    `collections(:one).reload.quantity` is still 1, and on a physical deck holding the printing,
    `quantity` and `owned_copies` are both unchanged. Row counts alone are satisfied by a
    resolve-write-then-refuse implementation, because `CardAdder` sums onto an existing row.
22. Success writes exactly one `Import`, `kind: "bulk_cards"`, `status: "completed"`, receipt length
    equal to the distinct printing count.
23. **[adv] The label's two counts are two different numbers.** A batch of 3 printings and 5 copies
    (one repeat plus one explicit `quantity: 3`) asserts the literal
    `"Collection — 5 copies over 3 printings"`; a 1/1 batch asserts `"1 copy over 1 printing"`.
    Equal counts cannot separate a label built from `entries.size` twice, or with the two swapped.
24. A refusal writes **no** `Import`.
25. `add_cards_to_deck` refuses another user's deck key, writes nothing, and **[adv]** that refusal
    also asserts `isError` — every pre-existing deck tool answers this case with plain `text`.
26. `mcp_scope_test.rb`: a read-only token sees neither tool; a read-write token sees both.
27. **[adv] Over the wire, not only in process.** A `tools/call` case in
    `test/integration/mcp_server_test.rb` posting `add_cards_to_collection` with
    `entries: [{set_code: "POR", set_number: 56}, {set_code: "POR", set_number: "56"}]`, asserting
    the collection moved to 3 **and** `assert_no_match(/Invalid arguments|Missing required
    arguments/, result_text)`. In-process calls bypass schema validation entirely — `mcp` validates
    only inside `Server#call_tool` — and this is the app's first array-of-objects `input_schema`.
28. **[adv] Registration is structural, not a hand-maintained literal.** Assert
    `McpTool.descendants - Mcp::ServerController::TOOLS` is empty. `TOOLS` is named by no test today
    except `mcp_scope_test`'s own `WRITE_TOOLS` array, so a tool missing from both is asserted about
    by nothing.

Admin:

29. **[adv] The refusal sentence is the new one.** Retry a `bulk_cards` row — created with
    `status: "failed"`, since a real one is `completed` and the earlier guard would refuse it first —
    and assert `/adds copies rather than setting them/` **and**
    `assert_no_match(/what it was run from is not stored/)`. The generic fallback already matches
    `/cannot be retried/` and tells the admin the opposite of the truth, the receipt being stored.
30. **[adv] The index renders the receipt's content.** `assert_includes` the disclosure body with the
    card name, `"POR 56"` and the `1 → 3` of a **persisted** row — not merely that a `<details>` node
    exists, which is true of a view reading Symbol keys off a JSON column and rendering nothing.
31. A kind whose receipt is `[]` renders no disclosure.

Dropped as already covered, per the adversary: a separate "bulk_cards cannot be undone" test
(`imports_controller_test.rb:131` already exercises that branch for every other kind) and a
standalone case for the `bulk_card_imports` scope, the scope itself having been removed.

## Verification

Container, per the project memory: image `cartodex-test:4.0.6`, volume `cartodex-bundle-406`.
Gates, all five: `bin/brakeman --no-pager`, `bin/importmap audit`, `bin/rubocop`,
`bin/rails db:test:prepare test test:system`, `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`
(system tests on the host — no Chrome in the image). Baseline run count recorded before any change.
