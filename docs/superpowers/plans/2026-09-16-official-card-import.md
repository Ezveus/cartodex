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

## What attacking this plan found — every row gets a test

The plan above was attacked before any code existed. Fourteen decisions would have been made wrong
without a single test going red. Two were factual errors in the spec, now corrected there.

| # | Would have stayed green because | Test assigned |
|---|---|---|
| 1 | `belongs_to :card_set, optional: true`, and 44 catalogue printings legitimately carry a nil `card_set_id` — so a card with the right `set_name` and **no set link** passes every `set_name` assertion, while `CardSets::RescrapeJob` iterates `card_set.cards` and repairs nothing | `assert_equal result.imported, set.cards.count`, and a rescrape test stubbing `Cards::Fetcher` that asserts `…/cards/30C/21` was requested |
| 2 | **Spec was wrong**: nothing on `Card` derives `pokemon_subtype`; the only writer is private to `Cards::Fetcher`. All 24 *ex* cards would score `POKEMON_WEIGHT` (2) instead of `RULE_BOX_WEIGHT` (3) in `Decks::ArchetypeDetector` | assert `pokemon_subtype.name == "Pokémon ex"` on `30th_53`, plus an `ArchetypeDetector` case where an imported *ex* wins on score |
| 3 | `config/environments/test.rb:23` is `:null_store`, so `count_queries { Card.filter_values } > 0` passes whether or not the cache was forgotten | copy `with_real_cache` from `CardSets::ImporterTest`, and assert 0 queries before the import as the sanity half |
| 4 | Every attack effect sits in a `<pre>` inside `.ability` — the same selector `effect` uses. A parser dropping the card-type guard writes attack text into `cards.effect` on all 154 Pokémon | `assert_nil` effect on `30th_21`/`30th_66`; assert `30th_128`'s by **equality** with Ultra Ball's printed sentence |
| 5 | The plan claimed weakness/resistance had no fixture. Wrong — `30th_53` carries the empty-resistance block, `30th_66`/`30th_100` a populated one | `30th_66` → weakness/resistance both asserted; `30th_53` → `assert_nil resistance`; assert the `×2` suffix stays out |
| 6 | The three damage fixtures each have exactly **one** damage span, so a parser zipping spans against attacks positionally is invisible | `assert_equal [nil, "160"]` on `30th_21`, `[nil, "200"]` on `30th_53`, `["30+", "90"]` on `30th_5`; `assert_nil` the empty `<pre>` effect |
| 7 | "Imports once, reports skipped" is satisfied by an in-place `update!` of the same row | pre-create the printing with `regulation_mark: "J"` and `price_eur: 1.5`; assert both survive and it is counted `skipped` |
| 8 | A `ParseError` is raised **before any write**, so the test passes whether the run is transactional or not. The realistic failure is a parseable card `Card` refuses — `RecordInvalid` | a fragment with its rarity span stripped: assert it lands in `failed`, that later files imported, and that earlier files are still in the database |
| 9 | `rename_set`'s refusal keyed on `card_sets.code` is **the wrong key** — `cards.set_name` holds 54 codes against `card_sets`' 28 | a `Card` at the target `set_name` with no `card_sets` row must make the rename refuse; and a card with `card_set_id: nil` must still be renamed |
| 10 | Two energy letters of eleven are exercised; a Fairy↔Psychic swap stores a valid, wrong, fingerprint-bearing value | `assert_equal Cards::Fetcher::ENERGY_SYMBOLS.invert, SYMBOL_BY_TYPE`; every `icon-*` class in the 17 fragments is a key |
| 11 | None of the three rarity cases is the collision the decision is *about* | assert `30th_129` → `"Illustration"` **and** `assert_not_equal "Art"`, with the refusal named in a comment |
| 12 | The only fixture with no retreat block is `30th_128`, a **Trainer** — which plan §3 requires to save with `retreat_cost` nil. The two prescribed tests contradict each other | a hand-edited `30th_53` copy, labelled as such: `assert_equal 0` and `card.valid?`; keep `30th_128` at nil |
| 13 | **Measured**: a two-attack card with `position: nil, nil` and one with `0, 1` produce the identical fingerprint `da0c4d0b5a19577a`, because `sort_by` on an all-equal key is stable. `position` is absent from the frozen contract | `assert_equal [0, 1], card.attacks.map(&:position)` and assert the attack order by name |
| 14 | `name_normalized` is only asserted by tests that read fixtures or their own transaction. An `insert_all` anywhere on the create path leaves it nil and the card invisible to `/cards` and the spotlight | `assert_includes Card.name_matching("greninja").pluck(:set_number), "21"` after a run |

Plus: `set_full_name`/`artist`/`image_url` get assertions (none were prescribed, and `set_full_name`
has two unarbitrated sources — the parser and the importer's argument); and the rake task gets
`assert_raises(SystemExit)` on a failing run, since `exit` otherwise kills the whole minitest run
instead of failing one test.

## Open, and blocking the run but not the build

The capture stopped at 17 of 184 pages: the address is currently refused by Imperva, including in a
browser and on the landing page. Everything above is buildable and testable from the 17. Running the
real import needs the block to lift, and the plan does not work around it.
