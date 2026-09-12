# Find a printing by set and collector number

## Why

A bulk collection add ("PFL 86, POR 48, ASC 86, …") is the natural way a player reads cards off a
stack, and it is the one lookup neither surface of this app can answer.

`SearchCardsTool` searches a name substring only, capped at 50 with no pagination, so reaching
PFL 86 among 130 PFL cards meant sweeping the alphabet for rare letters. `CardSearchable`, which
backs `/cards`, `Api::CardsController` and the spotlight, *does* parse "Charmeleon PFL 12" — but
not "PFL 86", because after popping the number its `tokens.length > 1` guard refuses to pop the
code, and "PFL" goes on as the name.

No spec file: this adds no table, no column, no external source. It adds one optional argument to
one MCP tool and moves one guard in one parser. The two decisions a later reader could undo are in
"Decisions" below and land in `CLAUDE.md`.

## Measurements

On `storage/development.sqlite3`, 4732 cards:

| Measurement | Value |
|---|---|
| `cards.set_name` differing from its `card_sets.code` | **0** rows |
| Cards with `card_set_id` NULL | **44** (GRI 4, ASR 4, PHF 3, … 26 old sets) |
| `set_number` not purely numeric | **100** (CRZ `GG1`…`GG15` and friends) |
| `set_number` with a leading zero | 0 |
| `(set_name, set_number)` | UNIQUE index — set + number is exactly one card |
| PFL / POR / ASC / MEG / JTG sizes | 130 / 124 / 295 / 188 / 190 |

`mcp` gem 1.5.0, `Configuration#validate_tool_call_arguments` defaults to **true**
(`configuration.rb:57`), and `Server#call_tool` runs `input_schema.validate_arguments` when it is
(`server.rb:1242`). So the declared JSON Schema is enforced on the wire, and a client sending
`{"set_number": 86}` against `type: "string"` gets rejected before the tool runs.

## Decisions

1. **`set_number` is matched as text, exactly.** 100 rows carry `GG1`-style numbers and none carries
   a leading zero, so there is no integer to cast to and no padding to normalise.
2. **`set_number` is declared `type: ["string", "integer"]`** and coerced with `.to_s.strip`. The
   schema is enforced (measured above), and an assistant reading "86" off a card writes the integer
   at least as often as the string. The coercion is what makes the two spellings one lookup.
3. **`query` becomes optional; the tool refuses an empty call.** Set plus number identifies one
   printing and the caller does not know the name — that is the whole point. But a call with no
   criterion at all must not answer with the first 20 rows of a 4732-card catalogue: a plausible,
   arbitrary answer is worse than an error.
4. **`set_code` moves from `joins(:card_set)` to `UPPER(cards.set_name) = ?`.** The INNER JOIN hides
   the 44 cards with no `card_set_id`; `cards.set_name` agrees with `card_sets.code` on every linked
   row (0 divergences), costs one join fewer, and is the column `CardSearchable` already reads — so
   the two surfaces stop answering differently.
5. **`CardSearchable`'s code-pop guard becomes `tokens.length > 1 || number`.** The `|| number` is
   the load-bearing half: it lets "PFL 86" reach code=PFL/number=86/name="", and it is what still
   stops the bare token "PFL" from being read as a set code and listing all 130 of them. Dropping it
   to `tokens.any?` passes every test in this plan except the one written to catch exactly that.

## Frozen contract

`app/mcp/search_cards_tool.rb`

```ruby
def self.call(server_context:, query: nil, set_code: nil, set_number: nil, limit: 20)
```

- `input_schema` `required: []`; properties `query` (string), `set_code` (string),
  `set_number` (`type: [ "string", "integer" ]`), `limit` (integer).
- Empty call → `text("Error: give at least one of query, set_code or set_number.")`
- Filters, in order, each applied only when present:
  `Card.all` → `.name_matching(query)` → `.where("UPPER(cards.set_name) = ?", set_code.to_s.upcase)`
  → `.where(set_number: set_number.to_s.strip)`
- `MAX_LIMIT = 50` and the clamp are unchanged. The per-row JSON payload
  (`id, name, set_name, set_number, card_type`) is unchanged.

`app/controllers/concerns/card_searchable.rb` — signature unchanged; only the `code` guard moves.

## Lanes

Disjoint file sets. **Neither lane runs a test**: `storage/test.sqlite3` is shared and
`database.yml` appends no `TEST_ENV_NUMBER`, so two concurrent runs cascade into
`SQLite3::BusyException`. Both lanes write tests and implementation; the suite is run once,
serialised, after integration.

**Lane A — the MCP tool**
- `app/mcp/search_cards_tool.rb`
- `test/mcp/read_tools_test.rb`
- `test/integration/mcp_server_test.rb`

**Lane B — the shared query parser**
- `app/controllers/concerns/card_searchable.rb`
- `test/services/search/global_test.rb`
- `test/controllers/cards_controller_test.rb`
- `test/controllers/api/cards_controller_test.rb`

## Tests, and what each one would have to lose to go red

Fixtures this leans on: `honedge` POR 56 (linked to `card_sets(:por)`), `froakie_twm` TWM 56
(**no** `card_set` link, while `card_sets(:twm)` exists), `trainer_card` PAL 172 (no link, no
CardSet row), `budew_asc` ASC 16.

Lane A, `test/mcp/read_tools_test.rb`:

| Test | Goes red without |
|---|---|
| `set_code` + `set_number`, no `query`, returns exactly Honedge | the optional `query`, or the `set_number` filter |
| `set_number` alone matches across sets and returns both POR 56 and TWM 56 | matching `set_number` as a column rather than folding it into the name |
| `set_number: 56` as an **Integer** returns the same rows as `"56"` | the `.to_s` coercion |
| `set_code: "twm"`, `set_number: "56"` returns Froakie | decision 4 — the INNER JOIN drops the unlinked row |
| No argument at all returns the error text and no card list | decision 3 |
| `query` + `set_code` + `set_number` still AND together | any filter overwriting instead of chaining |

Lane A, `test/integration/mcp_server_test.rb` (over JSON-RPC, so the gem's schema validation runs):

| Test | Goes red without |
|---|---|
| `tools/call` `search_cards` with `{"set_code":"POR","set_number":56}` (integer) returns Honedge | `type: [ "string", "integer" ]` — a bare `"string"` answers "Invalid arguments" |
| `tools/call` `search_cards` with `{}` answers the tool's own error, not "Missing required arguments" | `required: []` |

Lane B:

| Test | Goes red without |
|---|---|
| `Search::Global` on `"POR 56"` finds Honedge | the `\|\| number` half of the guard |
| `Search::Global` on `"asc"` finds no ASC card | the `tokens.length > 1 \|\|` half — a bare code must stay a name |
| `Search::Global` on `"Honedge POR 56"` still finds it | the whole parse order |
| `GET /cards?q=POR 56` lists Honedge and not Doublade | the guard, on the page that has to agree with MCP |
| `GET /api/cards?q=POR 56` returns Honedge | the guard, on the third caller |

## Verification

CI's five checks, container-side where Ruby cannot run on this host:
`bin/brakeman --no-pager`, `bin/importmap audit`, `bin/rubocop -f github`,
`bin/rails db:test:prepare test`, then `bin/rails test:system` and its `SYSTEM_TEST_VIEWPORT=mobile`
twin on the host (no Chrome in the image). Baseline to beat: **1755 runs, 8428 assertions,
0 failures**. Then sabotage every test in the two tables above.

No UI: this changes a tool argument and a scope builder, nothing rendered.
