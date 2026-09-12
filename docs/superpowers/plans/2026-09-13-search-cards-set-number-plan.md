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
one MCP tool and moves one guard in one parser. The six decisions a later reader could undo are in
"Decisions" below; the two that change an answer the app already gives — 4 and 6 — land in
`CLAUDE.md`.

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
   at least as often as the string. **`.to_s` is the half no data can see** — `cards.set_number` is
   a string column, so Active Record already renders `where(set_number: 56)` as `= '56'`; `.strip`
   is the observable half, and `" 56 "` is what a copy-paste actually delivers. Written together
   because the pair is one intent, tested through `.strip` because that is the half a test can hold.
3. **`query` becomes optional; the tool refuses an empty call — on `blank?`, not on `nil?`.**
   Set plus number identifies one printing and the caller does not know the name. But
   `Card.name_matching("")` compiles to `LIKE '%%'` and matches every row, so a guard reading
   `query.nil?` answers `{"query": ""}` — legal under the schema — with 20 arbitrary rows out of
   4732. That is the exact failure the guard exists to forbid, wearing the guard's own clothes.
4. **`set_code` moves from `joins(:card_set)` to `UPPER(cards.set_name) = ?`.** The INNER JOIN hides
   the 44 cards with no `card_set_id`; `cards.set_name` agrees with `card_sets.code` on every linked
   row (0 divergences), costs one join fewer, and is the column `CardSearchable` already reads — so
   the two surfaces stop answering differently.
5. **`CardSearchable`'s code-pop guard becomes `tokens.length > 1 || number`.** The `|| number` is
   the load-bearing half: it lets "PFL 86" reach code=PFL/number=86/name="", and it is what still
   stops the bare token "PFL" from being read as a set code and listing all 130 of them. Dropping it
   to `tokens.any?` passes every test in this plan except the one written to catch exactly that.
   The *number* guard stays `tokens.length > 1` for the mirror reason, and has its own test: relaxed
   to `tokens.any?`, the bare query "56" starts returning every card numbered 56 in every set.
6. **Where the two readings collide, the set wins, and one real query loses its answer.** 11 of the
   28 set codes are also substrings of card names, so a two-token query has two readings.
   Measured on the dump: "MEG 113" reads today as Mega Lucario ex (ASC 113) + Mega Sharpedo ex
   (PFL 113) and reads tomorrow as Acerola's Mischief (MEG 113); "PAL 49" moves from Palafin
   (TEF 49) to Quaxly (PAL 49); and **"Mew 216" goes from two cards to none**, because `MEW` is a
   set code and that set has no 216. The set reading wins because the name reading of a bare
   2–5 letter token is a coincidence filter — "name contains this fragment *and* carries this
   number" — which nobody types on purpose, while "MEG 113" is how every player writes a printing.
   Returning the union of both readings was weighed and refused: it keeps a query answering three
   cards where the reader asked for one. The loss is deliberate, so it gets a test rather than a
   comment — a query typed as a short name plus a number now answers with that *set*.

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

The first draft of this table was attacked before any code existed, and **11 of its 13 rows stayed
green without the mechanism they claimed to hold**. What follows is what survived that, with the
reason each row discriminates. Fixtures this leans on: `honedge` POR 56 (linked to
`card_sets(:por)`), `froakie_twm` TWM 56 (**no** `card_set` link, while `card_sets(:twm)` exists),
`trainer_card` PAL 172 (no link **and** no CardSet row at all), `basic_psychic_energy` SVE 5,
`budew_asc` ASC 16. Rows a fixture cannot express are built inline with `Card.create!` /
`CardSet.create!`, the idiom `test/controllers/api/cards_controller_test.rb:67` already uses —
never by adding to `cards.yml`, whose rows are shared with flat-cost and archetype tests.

### Lane A — `test/mcp/read_tools_test.rb`

| Test | Goes red without | Why it discriminates |
|---|---|---|
| `set_code: "por"`, `set_number: "56"`, no `query` → exactly Honedge | optional `query`, or the `set_number` filter | the only call shape the feature exists for |
| `set_number: " 56 "` → Honedge and Froakie | `.strip` | `.to_s` alone is invisible: Active Record casts `56` to `'56'` on a string column, so an implementation with **no** coercion passes the Integer test |
| `set_number: "5"` → **only** `basic_psychic_energy` (SVE 5) | exact matching | a `LIKE '%5%'` implementation also returns POR 56 and TWM 56 |
| `set_number: "056"` → nothing | exact matching | pins "no padding to normalise" |
| A `CardSet.create!(code: "CRZ")` + `Card.create!(set_name: "CRZ", set_number: "GG12")`, found by `set_code: "CRZ", set_number: "GG12"` | text matching | **no fixture carries a non-numeric number**, so `.to_i` / `CAST(set_number AS INTEGER)` — the spelling both card indexes already use in their ORDER BY — is bit-identical on every other row |
| `set_code: "PAL"`, `set_number: "172"` → `trainer_card` | decision 4 | PAL has **no `card_sets` row**, so this also refuses the half-fix that resolves the code through the table before filtering. The Froakie row alone does not: `card_sets(:twm)` exists |
| `set_code: "twm"`, `set_number: "56"` → Froakie | decision 4 | the INNER JOIN drops the row whose `card_set_id` is NULL |
| `query: "", set_code: "", set_number: "  "` → the error text, and no JSON array | decision 3 | a `nil?` guard lets `""` through and `LIKE '%%'` answers with 20 arbitrary cards |
| `assert_empty SearchCardsTool.input_schema.to_h[:required]` | `required: []` | the wire test cannot see it — both refusals are a 200 |
| `assert_equal [ "string", "integer" ], …dig(:properties, :set_number, :type)` | decision 2's declaration | ditto |
| `assert_match(/set_number/, SearchCardsTool.description_value)` | the updated description | **nothing in the suite reads a description.** Ship the old one and the argument exists while no assistant can discover it — with a green suite |
| The whole first row equals `{ "id" => …, "name" => "Honedge", "set_name" => "POR", "set_number" => "56", "card_type" => "Pokémon" }` | the payload contract | every existing test reads `["name"]` only, so `id` — the key a client chains into `add_card_to_collection` — could be dropped silently |
| `query` + `set_code` + `set_number` still AND together | chaining | a filter that reassigns instead of chaining |

### Lane A — `test/integration/mcp_server_test.rb` (over JSON-RPC, where the gem validates)

| Test | Goes red without | Why it discriminates |
|---|---|---|
| `tools/call` `search_cards` `{"set_code":"POR","set_number":56}` → parse `result.content[0].text` as JSON and find `cards(:honedge).id` | `type: [ "string", "integer" ]` | with a bare `"string"` the gem answers **200** with `Invalid arguments: value at '/set_number' is not a string`, so `assert_response :success` — the shape every other test in this file uses — passes either way |
| `tools/call` `search_cards` `{}` → `assert_match(/give at least one of query/, text)` **and** `assert_no_match(/Missing required arguments/, text)` | `required: []` | `server.rb:1235-1250`: the missing-argument branch and the tool's own refusal are both `error_tool_response` — a 200 with `isError` and one text block. `/Error/i` cannot tell them apart |

### Lane B — the shared parser

Built inline: `CardSet.create!(code: "MEW", name: "151", …)`, `Card.create!(name: "Mew ex", set_name: "PAF", set_number: "25")` and `Card.create!(name: "Pikachu", set_name: "MEW", set_number: "25")`. **No fixture set code equals any fixture card name**, so the collision decision 6 creates is otherwise unrepresentable and every test passes without it.

| Test | Goes red without |
|---|---|
| `Search::Global` on `"POR 56"` finds Honedge | the `\|\| number` half of the guard |
| `Search::Global` on `"asc"` finds no ASC card | the `tokens.length > 1 \|\|` half — a bare code stays a name |
| `Search::Global` on `"56"` finds no card | the *number* guard staying `tokens.length > 1` |
| `Search::Global` on `"Honedge POR 56"` still finds it | the three-token parse order |
| `Search::Global` on `"Mew 25"` finds Pikachu (MEW 25) and **not** Mew ex (PAF 25) | decision 6 — and it fails in both directions, so nobody reverts the trade by accident |
| `GET /cards?q=POR 56` lists Honedge and not Doublade | the guard, on the page that has to agree with MCP |
| `GET /cards?q=CRZ GG12` — the parser's `\A\d+\z` never pops `GG12`, so this answers by name | pins the one place the parser and the tool deliberately still differ |
| `GET /api/cards?q=POR 56` returns Honedge | the guard, on the third caller |

### Cross-surface

| Test | Goes red without |
|---|---|
| `SearchCardsTool.call(set_code: "TWM", set_number: "56")` and `GET /cards?q=TWM 56` name the same card id | decision 4's whole justification — the two surfaces agreeing |

## Verification

CI's five checks, container-side where Ruby cannot run on this host:
`bin/brakeman --no-pager`, `bin/importmap audit`, `bin/rubocop -f github`,
`bin/rails db:test:prepare test`, then `bin/rails test:system` and its `SYSTEM_TEST_VIEWPORT=mobile`
twin on the host (no Chrome in the image). Baseline to beat: **1755 runs, 8428 assertions,
0 failures**. Then sabotage every test in the two tables above.

No UI: this changes a tool argument and a scope builder, nothing rendered.
