# Importing a set from the official card database — Plan

Spec: `docs/superpowers/specs/2026-09-16-official-card-import-design.md`

## Where the boundary sits, and why it moved

The first shape had the scraper emit JSON, which put HTML→field extraction — every fragile rule in
the change — inside the one piece this repository cannot test (there is no JS test infrastructure).
Measured on the 17 captured pages, the `section.card-detail` fragment every selector lives inside
is **106 KiB across all 17** against 2732 KiB for the whole pages, ~6 KiB each. So the scraper
writes that fragment verbatim, and the rules move to Ruby where fixtures cost nothing.

```
bin/scrape_official_cards   navigate, slice section.card-detail, write, throttle   (no rules)
      │  tmp/official/30th_<n>.html
      ▼
Cards::OfficialParser       HTML → Hash                                            (all the rules)
      ▼
Cards::OfficialImporter     Hash → Card + Attacks + Abilities                      (all the writes)
      ▼
lib/tasks/official_cards.rake                                                      (thin wrapper)
```

The fixtures the tests eat are byte-identical in shape to what the scraper writes, so a test passing
is evidence about production input and not about a hand-made stand-in.

## Frozen contract

```ruby
Cards::OfficialParser.call(html) # => Hash
# { name:, card_type:, stage:, subtype:, hp:, type_symbol:, evolves_from:,
#   weakness:, resistance:, retreat_cost:, rarity:, set_full_name:, set_number:,
#   artist:, image_url:, effect:,
#   attacks: [ { name:, cost:, damage:, effect: } ],
#   abilities: [ { name:, effect: } ] }
# raises Cards::OfficialParser::ParseError

Cards::OfficialImporter.call(dir:, set_code:, set_full_name: nil) # => Result
Result = Struct.new(:imported, :skipped, :failed, keyword_init: true) # failed: [[file, message]]
```

`ENERGY_BY_SLUG` (icon class → `Card::ENERGY_TYPES` member) and `SYMBOL_BY_TYPE` (energy type →
the Limitless letter of `Cards::Fetcher::ENERGY_SYMBOLS`) are constants on `OfficialParser`.

## Steps, in order — each one red first

Sequential, not parallel. Two lanes would be `parser` and `importer`, and the importer's tests
consume the parser's output on every case; the split would cost a frozen intermediate fixture set
and return nothing. Below two useful lanes, dispatching is a loss — so this is written to be done
in one pass.

### 1. Fixtures

Commit 17 `section.card-detail` fragments to `test/fixtures/files/official_cards/`, named
`<slug>_<number>.html`. They cover: Basic Pokémon (`30th_1`, `30th_100`, `30th_130`), Stage 1
(`30th_129`), Stage 2 (`30th-c_1`), *ex* on a Basic (`30th_15`, `30th_53`), *ex* on an evolution
(`30th_21`), a card with a true Ability (`30th_66`), Trainer-Item (`30th_128`), damage shapes
`30×` (`30th_120`), `100+` (`30th_92`) and flat (`30th_21`), the secret-rare numbering `129/128`
(`30th_129`), `Futuristic Rare` (`30th_158`) and `Classic Collection` (`30th-c_1`).

`30th_1` is the one captured without a browser, so it carries none of the `data-gtm-vis-*`
attributes the others do. Keeping both forms is deliberate: it is what proves the selectors do not
depend on runtime-injected markup.

### 2. `Cards::OfficialParser` — tests first

One test per rule. The four that the spec calls load-bearing get a test that fails for the *right*
reason:

| Test | Asserts |
|---|---|
| name keeps the rule-box suffix | `30th_21` → `"Greninja ex"`, lowercase, not `"Greninja EX"` |
| stage on a plain Pokémon | `30th_129` → `"Stage 1"`, `30th-c_1` → `"Stage 2"` |
| **stage on a Basic *ex*** | `30th_15`, `30th_53` → `"Basic"` |
| **stage on an evolving *ex*** | `30th_21` → `nil`, and `evolves_from` → `"Frogadier"` |
| **retreat cost absent** | a fixture with no retreat list → `0`, never `nil` |
| attack cost re-encoding | `30th_21` Aqua Edge → `"WW"`; `30th_53` Thunderbolt → `"LLC"` |
| damage verbatim | `30th_120` → `"30×"`, `30th_92` → `"100+"`, `30th_21` → `"160"` |
| **the ex rule is not an ability** | `30th_53` → `abilities == []` despite three `.ability` divs |
| a real ability is one | `30th_66` → one ability named `"Memory Helix"`, and one attack |
| Trainer | `30th_128` → `card_type "Trainer"`, `subtype "Item"`, effect present, `hp` nil |
| rarity is the first token | `30th_21` → `"Double"`, `30th_158` → `"Futuristic"`, `30th-c_1` → `"Classic"` |
| set number | `30th_129` → `"129"` from `129/128` |
| type symbol from the class | `30th_100` → `"Darkness"`, `30th_110` → `"Dragon"` |
| a page with no card detail | raises `ParseError`, does not return a blank Hash |

The retreat-0 and resistance cases have no fixture yet — the capture was cut short by the block.
Either a captured page supplies one, or the fixture is a fragment edited by hand *and labelled as
such* in the test.

### 3. `Cards::OfficialImporter` — tests first

| Test | Asserts |
|---|---|
| creates the CardSet | code, name, `region` default |
| **fingerprint covers the attacks** | imported `30th_21`'s fingerprint equals the same card built by hand with its attacks — i.e. it is *not* the fingerprint of an attack-less card |
| idempotence | running twice imports once and reports `skipped` |
| a parse failure is isolated | one bad file does not abort the run; it lands in `failed` and the others import |
| forgets the filter cache | `Card.filter_values` re-queries afterwards, as `CardSets::Importer`'s test asserts |
| Trainer needs no Pokémon columns | `30th_128` saves with nil `hp`/`type_symbol`/`retreat_cost` |

The fingerprint test is the one that earns its place: it is the only thing standing between a
`create!`-then-`attacks.create!` regression and 184 cards that silently never match an archetype.

### 4. `lib/tasks/official_cards.rake` — thin

Two tasks, matching `archetypes.rake`'s shape (namespace, `desc`, `:environment`, `puts`,
non-zero exit on a bad outcome):

- `official_cards:import[dir,code,name]` → `Cards::OfficialImporter.call`, prints the counts, and
  `exit 1` if anything landed in `failed`.
- `official_cards:rename_set[from,to]` → moves `cards.set_name` and `card_sets.code` in one
  transaction; refuses if the target code already exists.

Tested with the repo's one existing rake-test mechanism
(`test/lib/tasks/card_labels_rake_test.rb`: `Rake::Task.clear`, `Cartodex::Application.load_tasks`,
`Rake::Task[name].tap(&:reenable).invoke`, `$stdout` redirected because `abort` escapes `capture_io`).

### 5. `bin/scrape_official_cards` — last, and dumb

Node, no dependencies. Enumerates from the gallery JSON, launches Chrome with
`--remote-debugging-port`, navigates, waits for `.card-description`, writes
`document.querySelector('.card-detail').outerHTML`, throttles ~500 ms, skips files already written,
aborts after three consecutive failures. No field extraction, no mapping, no rules.

It is not unit-tested and the plan says so rather than pretending otherwise. What stands in for a
test: the parser refuses a fragment it cannot read, so a scraper that writes the block page or a
truncated slice fails loudly at import instead of writing bad cards.

### 6. Verify

Container, per the project's own recipe — the host has no libvips and `bin/rails test` dies before
the first test:

```
docker run --rm -v cartodex-bundle-406:/bundle \
  -v /Users/matthieuciappara/Documents/perso/cartodex/.claude/worktrees/official-card-import:/app \
  -w /app cartodex-test:4.0.6 bin/rails test
```

Then the five CI gates. System tests are unaffected (no view, no route) but run anyway, on the host,
both viewports.

## Open, and blocking the run but not the build

The capture stopped at 17 of 184 pages: the address is currently refused by Imperva, including in a
browser and on the landing page. Everything above is buildable and testable from the 17. Running the
real import needs the block to lift, and the plan does not work around it.
