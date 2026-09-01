# Standard Pool Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A deck and a tournament record *which* Standard they belong to, chosen from a seeded, admin-maintained calendar of Standard pools named the way players name them (`TEF-PBL`).

**Architecture:** A new `standard_pools` table holds one row per period of the Standard calendar — two `CardSet` bounds, the legal regulation marks, and two dates (`released_on` for "the cards exist", `legal_on` for Play! Pokémon tournament legality). `Deck` and `Tournament` each gain a `standard_pool_id` that is required when the format is Standard and cleared otherwise, mirroring the existing `other_format_name` pattern. Nothing reads the regulation marks: this change carries them for #27/#61/#125.

**Tech Stack:** Ruby 3.4.1, Rails 8.1, SQLite (all environments), Minitest with parallel execution, Phlex views, Hotwire (Turbo + Stimulus), Nokogiri for scraping.

**Spec:** `docs/superpowers/specs/2026-08-31-standard-format-pool-design.md`

## Global Constraints

- **All views are Phlex components.** Never write ERB view logic. See the `phlex-architecture` skill.
- **Code and code comments in English.**
- `bin/rubocop` (rubocop-rails-omakase) must pass before every commit.
- `bin/rails test` must be green before every commit.
- System tests must pass at **both** viewports: `bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`. Never click a nav link directly — use `click_nav_link`.
- **Sabotage-verify every new test**: before implementing, run the test and see it fail for the stated reason. After implementing, break the implementation once and confirm the test goes red. A test that has never been red proves nothing.
- Services inherit from `ApplicationService` and expose `.call`.
- `app/mcp/` is an autoloaded root, so its classes are **top-level constants** (`ListDecksTool`, not `Mcp::ListDecksTool`).
- Fixtures are inserted **without validations or callbacks**. A new conditional presence validation will not make an existing fixture fail to load, but it will make `.valid?`/`.save` on that fixture fail in a test.
- `regulation_marks` is a `json` column. In fixtures, write it as a **JSON string** (`'["H","I","J"]'`) — unambiguous in both directions.

## Deploy order (read before Task 6)

The anchor validation goes live the moment the code deploys, so on an existing database three steps must run in order:

1. `bin/rails db:migrate` — creates `standard_pools`, adds the anchor columns.
2. `bin/rails db:seed` — creates the pool rows. **Without this, step 3 has nothing to anchor to.**
3. `bin/rails standard_pools:backfill_anchors` — anchors existing Standard decks and tournaments.

This is why the backfill is a **rake task and not part of the migration** (a deviation from the spec's wording, which said the migration backfills): a migration cannot depend on seed data that runs after it, and a rake task is idempotent, re-runnable, and — unlike a migration — testable.

---

## Task 1: `CardSets::Importer` records the set's release date

Prerequisite for everything date-driven. Today the importer writes only `code`, `name` and `logo_url`, so every set imported from the admin panel has a NULL `release_date`.

**Files:**
- Modify: `app/services/card_sets/importer.rb`
- Test: `test/services/card_sets/importer_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: `CardSet#release_date` is populated by `CardSets::Importer.call(url)`. No signature change — `.call` still returns `{ card_set:, imported: }`.

**Context you need:** the real Limitless set page (verified against `https://limitlesstcg.com/cards/CRI`) puts the date in the first segment of a line under the set heading:

```html
<div class="infobox">
  <div class="infobox-heading sm">
    <img class="set" alt="CRI" src="…"> Chaos Rising (CRI)
  </div>
  <div class="infobox-line">
     22nd May 2026                  •                  122 Cards                  • $641.12 • 578.42€
  </div>
</div>
```

An unreleased set omits the date and the line then starts with the card count. `Date.parse("122 Cards")` does **not** raise — it would read `122` as a day-of-month against the current month — so the parser must match an explicit ordinal date rather than hand the line to `Date.parse`.

- [ ] **Step 1: Replace the HTTP stub with one that can serve several pages**

The existing `stub_http` is hardcoded to one URL. Replace the private section of `test/services/card_sets/importer_test.rb` with this, keeping `SET_URL` and `SET_HTML` exactly as they are:

```ruby
  private

  # Serves a url => html map and records every URL asked for, so a test can
  # assert that the per-card pages were never requested.
  def stub_http(pages = { SET_URL => SET_HTML })
    calls = @http_calls
    HttpFetcher.define_singleton_method(:call) { |u|
      calls << u
      pages.fetch(u) { raise "Unexpected URL: #{u}" }
    }
  end
```

Run `bin/rails test test/services/card_sets/importer_test.rb` and confirm the two existing tests still pass. This is a refactor with no behaviour change; if it is red, stop and fix it before going on.

- [ ] **Step 2: Write the three failing tests**

Add to `test/services/card_sets/importer_test.rb`, above the `private` keyword:

```ruby
  # A set imported from the admin panel used to arrive with a NULL release_date,
  # which every date-driven rule then read as "never released".
  CRI_URL = "https://limitlesstcg.com/cards/CRI".freeze

  # No card links, so Cards::Fetcher is never reached and no card page is needed.
  CRI_HTML = <<~HTML.freeze
    <html><body>
      <div class="infobox">
        <div class="infobox-heading sm">Chaos Rising (CRI)</div>
        <div class="infobox-line"> 22nd May 2026  •  122 Cards • $641.12 • 578.42€ </div>
      </div>
    </body></html>
  HTML

  UNRELEASED_HTML = <<~HTML.freeze
    <html><body>
      <div class="infobox">
        <div class="infobox-heading sm">Chaos Rising (CRI)</div>
        <div class="infobox-line"> 122 Cards </div>
      </div>
    </body></html>
  HTML

  test "records the release date printed on the set page" do
    stub_http(CRI_URL => CRI_HTML)

    result = CardSets::Importer.call(CRI_URL)

    assert_equal Date.new(2026, 5, 22), result[:card_set].release_date
  end

  test "leaves a release date already on the record alone" do
    # POR is fixtured at 2026-01-16. The page deliberately claims a different,
    # obviously wrong date: a hand-seeded date must win over a scrape.
    page = SET_HTML.sub("<h1>", <<~INFOBOX + "<h1>")
      <div class="infobox"><div class="infobox-line">9th September 2099 • 4 Cards</div></div>
    INFOBOX
    Card.where(set_name: "POR", set_number: %w[56 57]).update_all(updated_at: 30.days.ago)
    stub_http(SET_URL => page)

    CardSets::Importer.call(SET_URL)

    assert_equal Date.new(2026, 1, 16), card_sets(:por).reload.release_date
  end

  test "leaves the release date nil when the page prints none" do
    stub_http(CRI_URL => UNRELEASED_HTML)

    result = CardSets::Importer.call(CRI_URL)

    assert_nil result[:card_set].release_date
  end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bin/rails test test/services/card_sets/importer_test.rb`

Expected: `records the release date printed on the set page` fails with `Expected: 2026-05-22, Actual: nil`. The other two pass already (nothing writes the column yet) — that is fine; they are regression guards, and Step 5 re-runs them.

- [ ] **Step 4: Implement the parser**

In `app/services/card_sets/importer.rb`, add the constant just below `BASE_URL`:

```ruby
  # Limitless prints the release date as the first segment of the infobox line
  # under the set heading: "22nd May 2026 • 122 Cards • $641.12 • 578.42€".
  # An unreleased set omits it and the line starts with the card count, which is
  # why this matches an explicit ordinal date instead of handing the whole line
  # to Date.parse — that would read "122 Cards" as a day of the current month.
  RELEASE_DATE = /\b\d{1,2}(?:st|nd|rd|th)\s+[A-Za-z]+\s+\d{4}\b/
```

Add the `||=` line to `find_or_create_set` — the same guard as `name` and `logo_url`, so a date seeded by hand is never overwritten by a scrape:

```ruby
  def find_or_create_set(doc)
    card_set = CardSet.find_or_initialize_by(code: @set_code)
    card_set.name ||= parse_set_name(doc)
    card_set.logo_url ||= parse_logo_url(doc)
    card_set.release_date ||= parse_release_date(doc)
    card_set.save!
    card_set
  end
```

And the parser, next to the other `parse_*` methods:

```ruby
  def parse_release_date(doc)
    match = doc.at_css(".infobox .infobox-line")&.text&.match(RELEASE_DATE)
    return if match.nil?

    Date.parse(match[0])
  rescue Date::Error
    nil
  end
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bin/rails test test/services/card_sets/importer_test.rb`
Expected: 5 runs, 0 failures.

- [ ] **Step 6: Sabotage-verify**

Change `RELEASE_DATE` to `/\b\d{4}\b/` (matches the year alone). Re-run: `records the release date printed on the set page` must fail. Revert the sabotage and re-run to green.

- [ ] **Step 7: Rubocop and commit**

```bash
bin/rubocop app/services/card_sets/importer.rb test/services/card_sets/importer_test.rb
git add app/services/card_sets/importer.rb test/services/card_sets/importer_test.rb
git commit -m "Record a set's release date when importing it

Every set imported from the admin panel arrived with a NULL release_date,
which a date-driven rule reads as \"never released\". The date is the first
segment of the infobox line under the set heading; it is matched as an
explicit ordinal date because an unreleased set omits it and the line then
starts with the card count, which Date.parse would happily read as a day of
the current month.

Refs #122"
```

---

## Task 2: The `standard_pools` table and model

**Files:**
- Create: `db/migrate/<timestamp>_create_standard_pools.rb`
- Create: `app/models/standard_pool.rb`
- Create: `test/fixtures/standard_pools.yml`
- Create: `test/models/standard_pool_test.rb`
- Modify: `db/schema.rb` (regenerated by the migration — commit it)

**Interfaces:**
- Consumes: `CardSet` (existing model, `#code`, `#release_date`).
- Produces:
  - `StandardPool#name → String` — `"TEF-PBL"`
  - `StandardPool.current → StandardPool | nil`
  - `StandardPool.at(date) → StandardPool | nil`
  - `StandardPool.by_release → ActiveRecord::Relation` (newest `released_on` first)
  - `StandardPool#first_card_set`, `#last_card_set`, `#regulation_marks` (Array of String), `#released_on`, `#legal_on`
  - `StandardPool#decks`, `#tournaments` — declared here, usable once Tasks 4 and 5 add the columns.

- [ ] **Step 1: Generate and write the migration**

```bash
bin/rails generate migration CreateStandardPools
```

Replace the generated file's body with:

```ruby
class CreateStandardPools < ActiveRecord::Migration[8.1]
  def change
    create_table :standard_pools do |t|
      t.references :first_card_set, null: false, foreign_key: { to_table: :card_sets }
      t.references :last_card_set,  null: false, foreign_key: { to_table: :card_sets }
      t.json :regulation_marks, null: false
      t.date :released_on, null: false
      t.date :legal_on, null: false

      t.timestamps
    end

    # The bound pair is the pool's name ("TEF-PBL"); two rows must not claim it.
    add_index :standard_pools, [ :first_card_set_id, :last_card_set_id ],
      unique: true, name: "index_standard_pools_on_bounds"
  end
end
```

Run: `bin/rails db:migrate` then `bin/rails db:test:prepare`

- [ ] **Step 2: Write the fixtures**

Create `test/fixtures/standard_pools.yml`. The `card_sets` fixtures available are `twm` (2024-05-24), `asc` (2025-11-07) and `por` (2026-01-16), and each pool below uses a distinct bound pair so the unique index is satisfied:

```yaml
# regulation_marks is a json column; written as a JSON string so it round-trips
# unambiguously through the fixture loader.
#
# Both pools are deliberately in the past: StandardPool.current must resolve to
# twm_por in every test. A pool with a future released_on is built inside the one
# test that needs it, rather than fixtured, so it cannot rot.

twm_asc:
  first_card_set: twm
  last_card_set: asc
  regulation_marks: '["G","H","I"]'
  released_on: 2025-11-07
  legal_on: 2025-11-21

twm_por:
  first_card_set: twm
  last_card_set: por
  regulation_marks: '["G","H","I","J"]'
  released_on: 2026-01-16
  legal_on: 2026-01-30
```

- [ ] **Step 3: Write the failing tests**

Create `test/models/standard_pool_test.rb`:

```ruby
require "test_helper"

class StandardPoolTest < ActiveSupport::TestCase
  test "is named by its two bounds, oldest legal set first" do
    assert_equal "TWM-POR", standard_pools(:twm_por).name
  end

  test "current is the most recently released pool" do
    assert_equal standard_pools(:twm_por), StandardPool.current
  end

  # The moment an announced-but-unreleased set's pool is seeded, it must not
  # become the default anchor for new decks before its date.
  test "current ignores a pool whose released_on is in the future" do
    StandardPool.create!(
      first_card_set: card_sets(:asc), last_card_set: card_sets(:por),
      regulation_marks: %w[H I J],
      released_on: Date.current + 1, legal_on: Date.current + 15
    )

    assert_equal standard_pools(:twm_por), StandardPool.current
  end

  # A tournament asks what was legal on its date, which is legal_on and not
  # released_on: a set is tournament-legal about two weeks after it releases.
  test "at reads legal_on, not released_on" do
    between = Date.new(2026, 1, 20) # after twm_por released, before it was legal

    assert_equal standard_pools(:twm_asc), StandardPool.at(between)
    assert_equal standard_pools(:twm_por), StandardPool.at(Date.new(2026, 1, 30))
  end

  test "at is nil before the oldest pool was legal" do
    assert_nil StandardPool.at(Date.new(2020, 1, 1))
  end

  test "the bound pair is unique" do
    duplicate = StandardPool.new(
      first_card_set: card_sets(:twm), last_card_set: card_sets(:por),
      regulation_marks: %w[G H I J],
      released_on: Date.new(2026, 2, 1), legal_on: Date.new(2026, 2, 15)
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:first_card_set_id], "has already been taken"
  end

  test "the database refuses a duplicate bound pair even without validations" do
    duplicate = StandardPool.new(
      first_card_set: card_sets(:twm), last_card_set: card_sets(:por),
      regulation_marks: %w[G H I J],
      released_on: Date.new(2026, 2, 1), legal_on: Date.new(2026, 2, 15)
    )

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "regulation_marks round-trips as an array of strings" do
    assert_equal %w[G H I J], standard_pools(:twm_por).regulation_marks
  end
end
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bin/rails test test/models/standard_pool_test.rb`
Expected: every test errors with `NameError: uninitialized constant StandardPool`.

- [ ] **Step 5: Write the model**

Create `app/models/standard_pool.rb`:

```ruby
# One period of the rotating Standard calendar. A period is created by exactly one
# of two events — a set release, which moves the upper bound, or a rotation, which
# moves the lower bound — and players name it by both bounds: "TEF-PBL".
class StandardPool < ApplicationRecord
  belongs_to :first_card_set, class_name: "CardSet"
  belongs_to :last_card_set, class_name: "CardSet"

  # restrict, not the :nullify that Archetype uses for its decks. An archetype is
  # a tag, so dropping it is harmless; a NULL anchor on a Standard deck makes that
  # deck unsavable on its next edit. A referenced pool is corrected, never deleted.
  has_many :decks, dependent: :restrict_with_error
  has_many :tournaments, dependent: :restrict_with_error

  validates :regulation_marks, presence: true
  validates :released_on, presence: true
  validates :legal_on, presence: true
  validates :first_card_set_id, uniqueness: { scope: :last_card_set_id }

  scope :by_release, -> { order(released_on: :desc) }

  # The oldest legal set, then the newest — the name players already use.
  def name = "#{first_card_set.code}-#{last_card_set.code}"

  # The pool a new deck is pre-anchored to. Filtered on released_on rather than
  # simply taking the newest row: a pool seeded for an announced set must not
  # become the default before that set exists.
  def self.current = where(released_on: ..Date.current).by_release.first

  # The pool a tournament held on `date` was played under. Reads legal_on, since
  # a set is tournament-legal about two weeks after it releases.
  def self.at(date) = where(legal_on: ..date).order(legal_on: :desc).first
end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `bin/rails test test/models/standard_pool_test.rb`
Expected: 8 runs, 0 failures.

- [ ] **Step 7: Sabotage-verify the two rules that are easy to get wrong**

1. Change `self.current` to `by_release.first` (drop the date filter). Re-run: `current ignores a pool whose released_on is in the future` must fail. Revert.
2. Change `self.at` to read `released_on` instead of `legal_on`. Re-run: `at reads legal_on, not released_on` must fail. Revert.

Re-run to green after both.

- [ ] **Step 8: Rubocop and commit**

```bash
bin/rubocop app/models/standard_pool.rb
bin/rails test
git add db/migrate db/schema.rb app/models/standard_pool.rb test/fixtures/standard_pools.yml test/models/standard_pool_test.rb
git commit -m "Add StandardPool, one row per period of the Standard calendar

A period is created by exactly one of two events: a set release moves the
upper bound, a rotation moves the lower bound. Both are stored, because the
bound pair is what players name the pool by (TEF-PBL) and the unique index
is what stops two rows claiming that name.

Two dates rather than one: released_on says the cards exist and drives
current, legal_on says Play! Pokemon considers the pool legal and drives
at(date). Neither derives from the other — a rotation with no new set shares
the previous pool's upper bound, and tournament legality lags a release by
about two weeks.

Refs #122"
```

---

## Task 3: Seed the missing sets and the pool history

**This task contains a review gate.** The seed data is the one place in this change where an error is silent: a wrong date or a wrong mark produces a plausible-looking pool that mislabels every deck anchored to it. **Do not commit the data without the maintainer's sign-off** (Step 2).

**Files:**
- Modify: `db/seeds/card_sets.rb`
- Create: `db/seeds/standard_pools.rb`
- Modify: `db/seeds.rb`
- Test: `test/models/standard_pool_test.rb` (one seed-shape test)

**Interfaces:**
- Consumes: `StandardPool` (Task 2), `CardSet`.
- Produces: a seeded pool history. `StandardPool.current` resolves on a seeded database.

- [ ] **Step 1: Add the missing card sets**

`db/seeds/card_sets.rb` jumps from PAL (2023-06-09) to TEF (2024-03-22) and stops at CRI. Insert the four missing Scarlet & Violet sets in release order, and PBL at the end of the Mega Evolution block:

```ruby
  { code: "OBF", name: "Obsidian Flames",           block_name: "Scarlet & Violet", release_date: "2023-08-11" },
  { code: "MEW", name: "151",                        block_name: "Scarlet & Violet", release_date: "2023-09-22" },
  { code: "PAR", name: "Paradox Rift",               block_name: "Scarlet & Violet", release_date: "2023-11-03" },
  { code: "PAF", name: "Paldean Fates",              block_name: "Scarlet & Violet", release_date: "2024-01-26" },
```

```ruby
  { code: "PBL", name: "Pitch Black",                 block_name: "Mega Evolution", release_date: "2026-07-17" }
```

- [ ] **Step 2: The pool table — SIGNED OFF, use these values verbatim**

This table was submitted to the maintainer and corrected by them. It is authoritative; do not re-derive any value in it.

| Pool | Created by | `released_on` | `legal_on` | `regulation_marks` |
|---|---|---|---|---|
| `SVI-JTG` | 2025 rotation | 2025-04-11 | 2025-04-11 | G, H, I |
| `SVI-DRI` | DRI release | 2025-05-30 | 2025-06-13 | G, H, I |
| `SVI-BLK` | BLK + WHT release | 2025-07-18 | 2025-08-01 | G, H, I |
| `SVI-MEG` | MEG + MEE release | 2025-09-26 | 2025-10-10 | G, H, I |
| `SVI-PFL` | PFL release | 2025-11-14 | 2025-11-28 | G, H, I |
| `SVI-ASC` | ASC release | 2026-01-30 | **2026-03-06** | G, H, I, **J** |
| `TEF-POR` | 2026 rotation + POR release | 2026-03-27 | 2026-04-10 | H, I, J |
| `TEF-CRI` | CRI release | 2026-05-22 | 2026-06-05 | H, I, J |
| `TEF-PBL` | PBL release | 2026-07-17 | 2026-07-31 | H, I, J |

Three facts behind the two values in bold, all of them non-derivable — a future maintainer who "corrects" either by re-applying the release + 14 rule will reintroduce a bug:

1. **`J` starts at ASC, not at MEG.** The Mega Evolution block opens on the `I` mark — *Mega Lucario ex* is MEG 77 with an `I` — so MEG and PFL add no new mark, and `SVI-ASC` is the first pool to carry four.
2. **ASC's legality is 2026-03-06, five weeks after release, not two.** *Ascended Heroes* shipped staggered: the ETB only arrived 2026-02-20, and Play! Pokémon pushed legality past the 2026-02-13 EUIC. This is exactly the case that makes `legal_on` a stored column rather than a computed one — derived, it would have claimed ASC was legal at a tournament where it was not.
3. **A rotation-created pool has `released_on == legal_on == the rotation date.`** True of both `SVI-JTG` (2025-04-11) and `TEF-POR` (2026-04-10), because Play! Pokémon aligns each rotation with a set's legality date rather than with its release.

Two more decisions this table encodes:

- **`SVI-BLK`, not `SVI-BLK/WHT`** — BLK and WHT released the same day; the upper bound is single and follows the Limitless name.
- **The history starts at the 2025 rotation** because every earlier rotation has a Sword & Shield lower bound and no Sword & Shield set exists in `card_sets`.

Promo sets (`SVP`, `MEP`) are deliberately absent: their legality is per-card, not per-set, and a promo reaches a pool through its regulation mark like any other card. They are never a pool bound.

- [ ] **Step 3: Write the seed**

Create `db/seeds/standard_pools.rb`:

```ruby
# The Standard calendar. One row per pool-creating event since the 2025 rotation:
# a set release moves the upper bound, a rotation moves the lower bound. Two sets
# released the same day are one event and one pool, named the way Limitless names
# it (SVI-BLK, not SVI-BLK/WHT), which also covers the energy subsets SVE and MEE.
#
# Earlier rotations are absent on purpose: their lower bound is a Sword & Shield
# set, and no Sword & Shield set exists in card_sets — seeding them would mean
# inventing set rows to hang them off.
#
# This file is a bootstrap, not the source of truth: pools are maintained from the
# admin panel. It is keyed on the bound pair, which the unique index guarantees,
# so re-running it after admin edits neither duplicates nor overwrites.
#
# legal_on is Play! Pokémon tournament legality, which is usually the second
# Friday after the US release (release + 14) but is NOT a formula — see ASC below.
# It is stored rather than computed precisely because of that.
#
# The J mark starts at ASC, not at MEG: the Mega Evolution block opens on I
# (Mega Lucario ex is MEG 77, mark I), so MEG and PFL add no new mark.
POOLS = [
  { first: "SVI", last: "JTG", marks: %w[G H I],   released_on: "2025-04-11", legal_on: "2025-04-11" },
  { first: "SVI", last: "DRI", marks: %w[G H I],   released_on: "2025-05-30", legal_on: "2025-06-13" },
  { first: "SVI", last: "BLK", marks: %w[G H I],   released_on: "2025-07-18", legal_on: "2025-08-01" },
  { first: "SVI", last: "MEG", marks: %w[G H I],   released_on: "2025-09-26", legal_on: "2025-10-10" },
  { first: "SVI", last: "PFL", marks: %w[G H I],   released_on: "2025-11-14", legal_on: "2025-11-28" },
  # ASC shipped staggered — the ETB only arrived 2026-02-20 — so Play! Pokémon
  # pushed its legality to 2026-03-06, past the 2026-02-13 EUIC. Five weeks after
  # release, not two: do not "fix" this back to the +14 rule.
  { first: "SVI", last: "ASC", marks: %w[G H I J], released_on: "2026-01-30", legal_on: "2026-03-06" },
  { first: "TEF", last: "POR", marks: %w[H I J],   released_on: "2026-03-27", legal_on: "2026-04-10" },
  { first: "TEF", last: "CRI", marks: %w[H I J],   released_on: "2026-05-22", legal_on: "2026-06-05" },
  { first: "TEF", last: "PBL", marks: %w[H I J],   released_on: "2026-07-17", legal_on: "2026-07-31" }
].freeze

missing = []

POOLS.each do |attrs|
  first_set = CardSet.find_by(code: attrs[:first])
  last_set  = CardSet.find_by(code: attrs[:last])

  # A pool whose bounds are not in the database cannot be written: both columns
  # are NOT NULL. Report it rather than aborting the run part-way.
  if first_set.nil? || last_set.nil?
    missing << "#{attrs[:first]}-#{attrs[:last]}"
    next
  end

  pool = StandardPool.find_or_initialize_by(first_card_set: first_set, last_card_set: last_set)
  pool.regulation_marks = attrs[:marks]
  pool.released_on = attrs[:released_on]
  pool.legal_on = attrs[:legal_on]
  pool.save!
end

puts "Seeded #{StandardPool.count} Standard pools; current is #{StandardPool.current&.name || 'none'}"
puts "Skipped (bound set missing): #{missing.join(', ')}" if missing.any?
```

Append to `db/seeds.rb`, after the existing `load` line:

```ruby
load Rails.root.join("db/seeds/standard_pools.rb")
```

- [ ] **Step 4: Run the seed and check the result**

```bash
bin/rails db:seed
```

Expected: `Seeded 9 Standard pools; current is TEF-PBL` and no "Skipped" line. Run it a second time and confirm the count stays 9 — the seed is idempotent.

- [ ] **Step 5: Add the seed-shape test**

The seed is not loaded by the test suite, so this test asserts the *rule* the seed follows rather than its rows. Append to `test/models/standard_pool_test.rb`:

```ruby
  # Within one rotation era the lower bound is constant and the upper bound only
  # advances, and each rotation changes the lower bound — which is what makes the
  # bound pair a safe unique key across the whole history.
  test "a pool with a lower bound the seed has no card set for cannot be written" do
    orphan = StandardPool.new(
      first_card_set: nil, last_card_set: card_sets(:por),
      regulation_marks: %w[H I J],
      released_on: Date.new(2026, 3, 27), legal_on: Date.new(2026, 4, 10)
    )

    assert_not orphan.valid?
    assert_includes orphan.errors[:first_card_set], "must exist"
  end
```

Run: `bin/rails test test/models/standard_pool_test.rb`
Expected: 9 runs, 0 failures.

- [ ] **Step 6: Commit**

```bash
bin/rubocop db/seeds/standard_pools.rb db/seeds/card_sets.rb
bin/rails test
git add db/seeds.rb db/seeds/card_sets.rb db/seeds/standard_pools.rb test/models/standard_pool_test.rb
git commit -m "Seed the Standard calendar and the four missing sets

One row per pool-creating event since the 2025 rotation. Earlier rotations
have a Sword & Shield lower bound and no Sword & Shield set exists, so they
are not expressible without inventing set rows.

The seed is a bootstrap, not the source of truth — pools are maintained from
the admin panel — so it is keyed on the bound pair and re-running it after an
admin edit neither duplicates nor overwrites. A pool whose bounds are absent
is reported rather than aborting the run part-way, since both columns are NOT
NULL.

Also adds OBF, MEW, PAR and PAF, which the seed skipped between PAL and TEF,
and PBL, which it stopped short of.

Refs #122"
```

---

## Task 4: The anchor on `Deck`

**Files:**
- Create: `db/migrate/<timestamp>_add_standard_pool_to_decks.rb`
- Modify: `app/models/deck.rb`
- Modify: `app/services/decks/duplicator.rb`
- Modify: `app/services/decks/fetcher.rb:27`
- Modify: `test/fixtures/decks.yml`
- Test: `test/models/deck_test.rb`, `test/services/decks/duplicator_test.rb`, `test/services/decks/fetcher_test.rb`, `test/models/standard_pool_test.rb`
- Modify: `db/schema.rb`

**Interfaces:**
- Consumes: `StandardPool.current` (Task 2).
- Produces: `Deck#standard_pool` / `#standard_pool_id`. A `Deck` with `format == "standard"` is invalid without one. `Deck#clear_inapplicable_classification` nils it for every other format.

- [ ] **Step 1: Write the migration**

```bash
bin/rails generate migration AddStandardPoolToDecks
```

```ruby
class AddStandardPoolToDecks < ActiveRecord::Migration[8.1]
  def change
    # Nullable in the database: the column is required by validation only when the
    # format is Standard, exactly like other_format_name is for "other".
    add_reference :decks, :standard_pool, foreign_key: true
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 2: Point the deck fixtures at a pool**

Fixtures load without validation, so they would not fail — but any test that saves `decks(:one)` would. Both fixtures take the column default `format: "standard"`, so both need an anchor. In `test/fixtures/decks.yml`, add to each of `one` and `two`:

```yaml
  standard_pool: twm_por
```

- [ ] **Step 3: Write the failing tests**

Append to `test/models/deck_test.rb`:

```ruby
  test "requires a standard pool when the format is standard" do
    deck = Deck.new(user: users(:one), name: "Anchorless", format: "standard")

    assert_not deck.valid?
    assert_includes deck.errors[:standard_pool], "can't be blank"
  end

  # Only Standard rotates. An anchor left behind by a format change would claim a
  # card pool that the new format does not have.
  test "clears the standard pool when the format is not standard" do
    deck = Deck.create!(
      user: users(:one), name: "Was standard", format: "standard",
      standard_pool: standard_pools(:twm_por)
    )

    deck.update!(format: "glc")

    assert_nil deck.reload.standard_pool_id
  end

  test "accepts a standard pool being absent on an eternal format" do
    deck = Deck.new(user: users(:one), name: "Singleton", format: "glc")

    assert deck.valid?
  end
```

Append to `test/models/standard_pool_test.rb`:

```ruby
  # :nullify would leave the deck with a NULL anchor, which its own validation
  # then refuses on the next edit.
  test "a pool holding decks refuses to be destroyed" do
    pool = standard_pools(:twm_por)

    assert_not pool.destroy
    assert_includes pool.errors[:base].join, "decks"
    assert StandardPool.exists?(pool.id)
  end
```

Append to `test/services/decks/duplicator_test.rb`:

```ruby
  # A duplicate of a TEF-CRI deck is still a TEF-CRI deck; it must not slide onto
  # whatever pool happens to be current.
  test "the copy keeps the source deck's standard pool" do
    source = decks(:one)
    source.update!(format: "standard", standard_pool: standard_pools(:twm_asc))

    copy = Decks::Duplicator.call(source)

    assert_equal standard_pools(:twm_asc), copy.standard_pool
  end
```

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bin/rails test test/models/deck_test.rb test/models/standard_pool_test.rb test/services/decks/duplicator_test.rb`

Expected failures: `requires a standard pool…` (deck is valid), `clears the standard pool…` (`NoMethodError: undefined method 'standard_pool'` — the association does not exist yet), `a pool holding decks refuses to be destroyed` (destroy succeeds), `the copy keeps…` (nil).

- [ ] **Step 5: Add the association, validation and clearing to `Deck`**

In `app/models/deck.rb`, after `belongs_to :archetype, optional: true`:

```ruby
  # Which Standard the deck was built for. Standard rotates, so its name alone
  # does not identify a card pool; every other format is eternal and has no anchor.
  belongs_to :standard_pool, optional: true
```

Next to `validates :other_format_name, presence: true, if: :other?`:

```ruby
  validates :standard_pool, presence: true, if: :standard?
```

In `clear_inapplicable_classification` (around `app/models/deck.rb:115`), add the second line:

```ruby
  def clear_inapplicable_classification
    self.other_format_name = nil unless other?
    self.standard_pool_id = nil unless standard?
  end
```

- [ ] **Step 6: Carry the anchor through the duplicator**

In `app/services/decks/duplicator.rb`, add to the `create!` argument list, after `other_format_name:`:

```ruby
        standard_pool_id: @deck.standard_pool_id
```

- [ ] **Step 7: Anchor an imported deck**

`Decks::Fetcher` creates the deck without a format, so it takes the `"standard"` column default and the user is never asked — the silent assumption #125 flags. Anchoring it to the current pool makes that assumption explicit and visible in the edit form. Change `app/services/decks/fetcher.rb:27`:

```ruby
      # The import never asks for a format, so the deck takes the "standard"
      # column default. Anchor it to the current pool rather than leave it
      # unsavable; the deck form is where the user corrects it.
      deck = Deck.create!(user: @user, name: @name, standard_pool: StandardPool.current)
```

- [ ] **Step 8: Add the importer test**

Find the existing "creates a deck" test in `test/services/decks/fetcher_test.rb` and add alongside it:

```ruby
  test "anchors an imported deck to the current standard pool" do
    deck = Decks::Fetcher.call(user: users(:one), name: "Imported", decklist: DECKLIST)

    assert_equal StandardPool.current, deck.standard_pool
  end
```

If the existing tests in that file use a different constant name for the decklist body or a different `.call` signature, match theirs — read the top of the file first and reuse its setup verbatim.

- [ ] **Step 9: Run the full suite**

Run: `bin/rails test`
Expected: 0 failures. Any unrelated failure is a fixture that now needs an anchor — add `standard_pool: twm_por` to it rather than relaxing the validation.

- [ ] **Step 10: Sabotage-verify**

1. Remove `if: :standard?` from the validation (making it unconditional). `accepts a standard pool being absent on an eternal format` must fail. Revert.
2. Remove the `self.standard_pool_id = nil unless standard?` line. `clears the standard pool when the format is not standard` must fail. Revert.
3. Change `restrict_with_error` to `nullify`. `a pool holding decks refuses to be destroyed` must fail. Revert.

- [ ] **Step 11: Rubocop and commit**

```bash
bin/rubocop app/models/deck.rb app/services/decks/duplicator.rb app/services/decks/fetcher.rb
bin/rails test
git add db/migrate db/schema.rb app/models/deck.rb app/services/decks app/services/decks/fetcher.rb test/
git commit -m "A deck records which Standard it was built for

Required by validation when the format is Standard and cleared otherwise —
the other_format_name pattern — so the eternal formats stay eternal and an
anchor left behind by a format change does not claim a pool the new format
has not got.

Two existing paths would have broken on the validation. Decks::Fetcher creates
a deck without a format, so it takes the \"standard\" column default and the
user is never asked; it now anchors to the current pool, which turns that
silent assumption into something the edit form shows. Decks::Duplicator copied
other_format_name but would have dropped the anchor, sliding the copy of a
TEF-CRI deck onto whatever is current.

Refs #122"
```

---

## Task 5: The anchor on `Tournament`

**Files:**
- Create: `db/migrate/<timestamp>_add_standard_pool_to_tournaments.rb`
- Modify: `app/models/tournament.rb`
- Modify: `test/fixtures/tournaments.yml`
- Test: `test/models/tournament_test.rb`
- Modify: `db/schema.rb`

**Interfaces:**
- Consumes: `StandardPool.at(date)`, `StandardPool.current` (Task 2).
- Produces: `Tournament#standard_pool` / `#standard_pool_id`, with the same conditional validation and clearing as `Deck`.

- [ ] **Step 1: Write the migration**

```bash
bin/rails generate migration AddStandardPoolToTournaments
```

```ruby
class AddStandardPoolToTournaments < ActiveRecord::Migration[8.1]
  def change
    add_reference :tournaments, :standard_pool, foreign_key: true
  end
end
```

Run: `bin/rails db:migrate && bin/rails db:test:prepare`

- [ ] **Step 2: Point the tournament fixtures at a pool**

Both fixtures are `format: standard`. `one` is dated 2026-03-14 and `two` 2026-02-01, and `twm_por` was legal from 2026-01-30, so it is the right pool for both. Add to each of `one` and `two` in `test/fixtures/tournaments.yml`:

```yaml
  standard_pool: twm_por
```

- [ ] **Step 3: Write the failing tests**

Append to `test/models/tournament_test.rb`, using that file's existing `build_tournament` helper:

```ruby
  test "requires a standard pool when the format is standard" do
    tournament = build_tournament(format: "standard", standard_pool: nil)

    assert_not tournament.valid?
    assert_includes tournament.errors[:standard_pool], "can't be blank"
  end

  test "clears the standard pool when the format is not standard" do
    tournament = build_tournament(format: "expanded", standard_pool: standard_pools(:twm_por))

    tournament.validate

    assert_nil tournament.standard_pool_id
  end
```

Read the top of `test/models/tournament_test.rb` first: if `build_tournament` does not accept arbitrary attributes, or already sets `standard_pool`, adapt these two tests to its actual signature rather than changing the helper for every other test in the file.

- [ ] **Step 4: Run the tests to verify they fail**

Run: `bin/rails test test/models/tournament_test.rb`
Expected: both new tests error on the missing `standard_pool` association.

- [ ] **Step 5: Implement**

In `app/models/tournament.rb`, after `belongs_to :tournament_profile, optional: true`:

```ruby
  # A tournament is played under the format legal on its date, which is not the
  # same as "the newest set exists" — a set is tournament-legal about two weeks
  # after release. The form pre-fills this from the date; it stays editable.
  belongs_to :standard_pool, optional: true
```

Next to `validates :other_format_name, presence: true, if: :other?`:

```ruby
  validates :standard_pool, presence: true, if: :standard?
```

In `clear_inapplicable_classification` (`app/models/tournament.rb:107`):

```ruby
  def clear_inapplicable_classification
    self.other_format_name = nil unless other?
    self.standard_pool_id = nil unless standard?
  end
```

- [ ] **Step 6: Run, sabotage-verify, commit**

Run: `bin/rails test`
Expected: 0 failures.

Sabotage: drop `if: :standard?` — `clears the standard pool…` still passes, but add a temporary check that an `expanded` tournament with no pool is valid; simpler, remove the clearing line and confirm `clears the standard pool when the format is not standard` fails. Revert.

```bash
bin/rubocop app/models/tournament.rb
git add db/migrate db/schema.rb app/models/tournament.rb test/fixtures/tournaments.yml test/models/tournament_test.rb
git commit -m "A tournament records which Standard it was played under

Same conditional validation and clearing as Deck. The anchor is explicit
rather than derived from the date, because tournament legality is not the
release date: a set becomes legal about two weeks after it ships, and an
event announced under a frozen format is a real case.

Refs #122"
```

---

## Task 6: Backfill existing rows

**Files:**
- Create: `lib/tasks/standard_pools.rake`
- Create: `app/services/standard_pools/anchor_backfill.rb`
- Test: `test/services/standard_pools/anchor_backfill_test.rb`

Written as a service behind a rake task, following the `archetypes:resync_fingerprints` precedent (`lib/tasks/archetypes.rake` → `Archetypes::FingerprintSync`). A migration cannot do this: it would run before `db:seed` has created the pools it needs. See **Deploy order** at the top of this plan.

**Interfaces:**
- Consumes: `StandardPool.at(date)`, `StandardPool.current`, `Deck`, `Tournament`.
- Produces: `StandardPools::AnchorBackfill.call → Result` with `Struct.new(:decks, :tournaments, :skipped, keyword_init: true)` — counts of rows anchored, plus `skipped` (an Array of `String` describing rows left alone).

- [ ] **Step 1: Write the failing tests**

Create `test/services/standard_pools/anchor_backfill_test.rb`:

```ruby
require "test_helper"

class StandardPools::AnchorBackfillTest < ActiveSupport::TestCase
  setup do
    # The fixtures are already anchored, which is the post-migration state. Undo
    # that to reproduce the pre-migration one.
    Deck.update_all(standard_pool_id: nil)
    Tournament.update_all(standard_pool_id: nil)
  end

  # created_at is not the date a deck was built — importing an old decklist today
  # stamps today — so anchoring on it would fabricate a precision the column has
  # not got. The current pool is visibly wrong for an old deck rather than
  # plausibly wrong, and the stale-anchor nudge invites the user to fix it.
  test "anchors standard decks to the current pool" do
    result = StandardPools::AnchorBackfill.call

    assert_equal StandardPool.current, decks(:one).reload.standard_pool
    assert_equal 2, result.decks
  end

  test "anchors tournaments to the pool legal on their date" do
    tournaments(:one).update_columns(date: Date.new(2026, 1, 20))

    StandardPools::AnchorBackfill.call

    # 2026-01-20 is after twm_por released but before it was legal.
    assert_equal standard_pools(:twm_asc), tournaments(:one).reload.standard_pool
  end

  # NULL is unsavable on the next edit, so an event older than the whole seeded
  # history falls back to the oldest pool rather than staying empty.
  test "a tournament older than the oldest pool falls back to the oldest" do
    tournaments(:one).update_columns(date: Date.new(2019, 1, 1))

    StandardPools::AnchorBackfill.call

    assert_equal standard_pools(:twm_asc), tournaments(:one).reload.standard_pool
  end

  test "leaves rows whose format is not standard alone" do
    decks(:one).update_columns(format: "glc")

    StandardPools::AnchorBackfill.call

    assert_nil decks(:one).reload.standard_pool_id
  end

  test "is idempotent and does not move an anchor already set" do
    decks(:one).update_columns(standard_pool_id: standard_pools(:twm_asc).id)

    result = StandardPools::AnchorBackfill.call

    assert_equal standard_pools(:twm_asc), decks(:one).reload.standard_pool
    assert_equal 1, result.decks
  end

  test "reports rather than writes when there is no pool at all" do
    Deck.update_all(standard_pool_id: nil)
    Tournament.update_all(standard_pool_id: nil)
    StandardPool.delete_all

    result = StandardPools::AnchorBackfill.call

    assert_equal 0, result.decks
    assert_includes result.skipped.join, "no Standard pool"
  end
end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/services/standard_pools/anchor_backfill_test.rb`
Expected: every test errors with `NameError: uninitialized constant StandardPools`.

- [ ] **Step 3: Implement the service**

Create `app/services/standard_pools/anchor_backfill.rb`:

```ruby
# Anchors Standard decks and tournaments that predate the anchor column.
#
# A rake task rather than a migration: the pools it needs come from db/seed, which
# runs after db:migrate, so a migration would find an empty table. Idempotent, so
# it can be re-run after the seed is corrected.
class StandardPools::AnchorBackfill < ApplicationService
  Result = Struct.new(:decks, :tournaments, :skipped, keyword_init: true)

  def call
    skipped = []
    oldest = StandardPool.order(:legal_on).first

    if oldest.nil?
      skipped << "no Standard pool exists yet — run bin/rails db:seed first"
      return Result.new(decks: 0, tournaments: 0, skipped: skipped)
    end

    Result.new(decks: backfill_decks, tournaments: backfill_tournaments(oldest), skipped: skipped)
  end

  private

  # created_at is not a build date — importing an old decklist today stamps today —
  # so every unanchored Standard deck takes the current pool. Visibly wrong for an
  # old deck beats plausibly wrong, and the deck form invites the user to correct it.
  def backfill_decks
    Deck.where(format: "standard", standard_pool_id: nil)
        .update_all(standard_pool_id: StandardPool.current&.id)
  end

  # A tournament has a real date, so its answer is exact. An event older than the
  # whole seeded history falls back to the oldest pool: NULL would be unsavable on
  # its next edit.
  def backfill_tournaments(oldest)
    Tournament.where(format: "standard", standard_pool_id: nil).find_each.count do |tournament|
      pool = StandardPool.at(tournament.date) || oldest
      tournament.update_column(:standard_pool_id, pool.id)
    end
  end
end
```

Note on the return values: `update_all` returns the number of rows it touched, which is what `result.decks` reports. `find_each.count { … }` counts the block's truthy returns, and `update_column` returns `true`, so it counts every row updated.

- [ ] **Step 4: Write the rake task**

Create `lib/tasks/standard_pools.rake`:

```ruby
namespace :standard_pools do
  desc "Anchor Standard decks and tournaments that predate the standard_pool column"
  task backfill_anchors: :environment do
    result = StandardPools::AnchorBackfill.call

    puts "Anchored #{result.decks} deck(s) and #{result.tournaments} tournament(s)."

    if result.skipped.any?
      puts "\nNothing was written:"
      result.skipped.each { |reason| puts "  #{reason}" }
      exit 1
    end
  end
end
```

- [ ] **Step 5: Run to verify they pass**

Run: `bin/rails test test/services/standard_pools/anchor_backfill_test.rb`
Expected: 6 runs, 0 failures.

- [ ] **Step 6: Sabotage-verify**

Change `StandardPool.at(tournament.date) || oldest` to `StandardPool.current`. `anchors tournaments to the pool legal on their date` must fail. Revert.

- [ ] **Step 7: Run it against the development database and report**

```bash
bin/rails standard_pools:backfill_anchors
```

Record the printed counts in the commit message — this is the verification the spec says is done by hand rather than by a test.

- [ ] **Step 8: Rubocop and commit**

```bash
bin/rubocop app/services/standard_pools lib/tasks/standard_pools.rake
bin/rails test
git add app/services/standard_pools lib/tasks/standard_pools.rake test/services/standard_pools
git commit -m "Backfill the anchor on decks and tournaments that predate it

A rake task, not a migration: the pools it needs come from db/seed, which runs
after db:migrate, so a migration would find an empty table. Idempotent, and —
unlike a migration — testable.

Tournaments take the pool legal on their own date, which is exact. Decks take
the current pool: created_at is not a build date, since importing an old
decklist today stamps today, so anchoring on it would fabricate a precision
the column has not got. A tournament older than the whole seeded history falls
back to the oldest pool, because NULL is unsavable on its next edit.

Refs #122"
```

---

## Task 7: `#format_label` names the pool

**Files:**
- Modify: `app/models/deck.rb:42-46`
- Modify: `app/models/tournament.rb:79-83`
- Test: `test/models/deck_test.rb`, `test/models/tournament_test.rb`

**Interfaces:**
- Consumes: `Deck#standard_pool` (Task 4), `Tournament#standard_pool` (Task 5), `StandardPool#name` (Task 2).
- Produces: `#format_label → String` returns `"Standard (TEF-PBL)"` with an anchor, `"Standard"` without. Every consumer — `Decks::ClassificationBadges`, `Decks::IndexView`, `Search::ResultsList`, `Tournaments::ShowView` — picks this up with no change.

- [ ] **Step 1: Write the failing tests**

Append to `test/models/deck_test.rb`:

```ruby
  test "format_label names the standard pool the deck is anchored to" do
    deck = Deck.new(user: users(:one), name: "Anchored", format: "standard",
      standard_pool: standard_pools(:twm_por))

    assert_equal "Standard (TWM-POR)", deck.format_label
  end

  # Pre-backfill rows and any row the anchor does not apply to.
  test "format_label falls back to the bare format name without a pool" do
    deck = Deck.new(user: users(:one), name: "Anchorless", format: "standard")

    assert_equal "Standard", deck.format_label
  end
```

Append to `test/models/tournament_test.rb`:

```ruby
  test "format_label names the standard pool the tournament was played under" do
    tournament = build_tournament(format: "standard", standard_pool: standard_pools(:twm_por))

    assert_equal "Standard (TWM-POR)", tournament.format_label
  end
```

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/models/deck_test.rb test/models/tournament_test.rb`
Expected: the two "names the standard pool" tests fail with `Expected: "Standard (TWM-POR)", Actual: "Standard"`.

- [ ] **Step 3: Implement in both models**

The two methods are independent copies today; keep them that way rather than extracting a concern for four lines. In `app/models/deck.rb`:

```ruby
  # Human-readable format label. For the "other" format the user-supplied name
  # takes precedence when present; for Standard the pool is named, since
  # "Standard" alone does not identify a card pool.
  def format_label
    return other_format_name if other? && other_format_name.present?

    base = FORMAT_LABELS.fetch(format, format.to_s.humanize)
    return base unless standard? && standard_pool

    "#{base} (#{standard_pool.name})"
  end
```

Apply the identical change to `Tournament#format_label`.

- [ ] **Step 4: Run to verify they pass**

Run: `bin/rails test`
Expected: 0 failures. If a controller or system test asserted the exact string `"Standard"` in a page body, it now sees `"Standard (TWM-POR)"` — update the assertion to the new string rather than weakening the label.

- [ ] **Step 5: Sabotage-verify**

Drop the `&& standard_pool` guard so it calls `standard_pool.name` unconditionally. `format_label falls back to the bare format name without a pool` must fail with `NoMethodError on nil`. Revert.

- [ ] **Step 6: Commit**

```bash
bin/rubocop app/models/deck.rb app/models/tournament.rb
git add app/models/deck.rb app/models/tournament.rb test/models
git commit -m "Name the Standard pool in format_label

One method per model changes and the deck badge, the deck list, the search
results and the tournament view all follow, because they already render
format_label. Falls back to the bare name when there is no anchor, which is
every row until the backfill runs.

Refs #122"
```

---

## Task 8: The pool picker on the deck form

**Files:**
- Modify: `app/views/components/decks/classification_fields.rb`
- Modify: `app/javascript/controllers/deck_classification_controller.js`
- Modify: `app/controllers/decks_controller.rb:210`
- Test: `test/controllers/decks_controller_test.rb`

**Interfaces:**
- Consumes: `StandardPool.by_release` (Task 2), `Deck#standard_pool_id` (Task 4).
- Produces: the deck form posts `deck[standard_pool_id]`. The Stimulus controller `deck-classification` exposes a single `toggle` action driving two conditional fields, with targets `format`, `otherField` and `standardField`.

**Already done in Task 4, do not redo:** `:standard_pool_id` is permitted in `DecksController#deck_params`, and a test that posting an explicit `standard_pool_id` creates the deck with that pool already exists in `test/controllers/decks_controller_test.rb`. Both were pulled forward because Task 4's validation left every HTML deck edit answering 422, and no task should end with the branch in that state. This task therefore owns the **form field and the Stimulus controller only**.

- [ ] **Step 1: Write the failing controller test**

Append to `test/controllers/decks_controller_test.rb` (reuse that file's existing sign-in setup):

```ruby
  test "the new deck form offers the standard pools, current one selected" do
    get new_deck_path

    assert_response :success
    assert_match "TWM-POR", response.body
    assert_match "TWM-ASC", response.body
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/controllers/decks_controller_test.rb`
Expected: fails because the form has no pool select, so neither pool name appears in the body.

- [ ] **Step 3: Add the field to the Phlex component**

In `app/views/components/decks/classification_fields.rb`, render the new field between `format_group` and `other_format_field`:

```ruby
    def view_template
      div(class: "deck-classification-fields", data: { controller: "deck-classification" }) do
        support_fieldset
        format_group
        standard_pool_field
        other_format_field
        render Decks::ArchetypeField.new(form: @form, deck: @deck)
      end
    end
```

Change `format_group`'s Stimulus action to the generalised name:

```ruby
          data: { deck_classification_target: "format", action: "deck-classification#toggle" }
```

Add the field itself, plus the pool list. `StandardPool.current` is the pre-selection for a new deck; on an existing one the form object already carries the value:

```ruby
    # Standard rotates, so a deck has to say which Standard. Conditional on the
    # format for the same reason other_format_name is: the other three formats are
    # eternal and have no pool.
    def standard_pool_field
      div(class: "form-group deck-standard-pool-field",
          data: { deck_classification_target: "standardField" },
          style: hidden_unless(@deck.standard?)) do
        label(class: "form-label", for: "deck_standard_pool_id") { "Standard" }
        @form.collection_select :standard_pool_id, pools, :id, :name,
          { selected: @deck.standard_pool_id || StandardPool.current&.id },
          class: "form-input", id: "deck_standard_pool_id"
      end
    end

    def pools
      @pools ||= StandardPool.includes(:first_card_set, :last_card_set).by_release
    end
```

The `includes` is not decoration: `#name` reads both bounds' codes, so without it the select costs two queries per pool.

- [ ] **Step 4: Generalise the Stimulus controller**

Replace `app/javascript/controllers/deck_classification_controller.js` entirely:

```javascript
import { Controller } from "@hotwired/stimulus"

// Toggles the conditional classification fields on the deck form. Two fields
// depend on the format: the custom name applies only to "other", the Standard
// pool only to "standard" — Standard is the one rotating format.
export default class extends Controller {
  static targets = ["format", "otherField", "standardField"]

  connect() {
    this.toggle()
  }

  toggle() {
    if (!this.hasFormatTarget) return

    const format = this.formatTarget.value
    this.show(this.hasOtherFieldTarget && this.otherFieldTarget, format === "other")
    this.show(this.hasStandardFieldTarget && this.standardFieldTarget, format === "standard")
  }

  show(element, visible) {
    if (!element) return
    element.style.display = visible ? "" : "none"
  }
}
```

The old action name `toggleOther` is gone, so grep for it and fix every caller:

```bash
grep -rn "toggleOther" app test
```

- [ ] **Step 5: Run to verify they pass**

Run: `bin/rails test`
Expected: 0 failures.

- [ ] **Step 6: Sabotage-verify**

Remove the `standard_pool_field` call from `view_template`. `the new deck form offers the standard pools` must fail. Revert. Then break the Stimulus `toggle` so it never shows `standardField`, and confirm Task 13's system test catches it later — note it, do not run the system suite here.

- [ ] **Step 7: Rubocop and commit**

```bash
bin/rubocop app/views/components/decks/classification_fields.rb app/controllers/decks_controller.rb
git add app/views/components/decks/classification_fields.rb app/javascript/controllers/deck_classification_controller.js app/controllers/decks_controller.rb test/controllers/decks_controller_test.rb
git commit -m "Let the deck form pick which Standard

Conditional on the format, the way other_format_name is, and pre-selected to
the current pool so the mandatory field costs the common case nothing.

The Stimulus controller knew how to toggle exactly one field; it now drives
both from one action rather than growing a near-copy of itself.

Refs #122"
```

---

## Task 9: The pool picker on the tournament form

**Files:**
- Modify: `app/views/components/tournaments/form.rb:33-41`
- Modify: `app/controllers/tournaments_controller.rb:61`
- Test: `test/controllers/tournaments_controller_test.rb`

This form has **no** Stimulus toggling: it renders `other_format_name` unconditionally with the hint "Only used when format is “Other”". Follow that pattern rather than importing the deck form's controller — matching the file you are in beats consistency with a different file.

**Interfaces:**
- Consumes: `StandardPool.at(date)`, `StandardPool.current`, `Tournament#standard_pool_id` (Task 5).
- Produces: the tournament form posts `tournament[standard_pool_id]`.

- [ ] **Step 1: Write the failing test**

Append to `test/controllers/tournaments_controller_test.rb` (reuse its sign-in setup):

```ruby
  test "creating a tournament stores the chosen standard pool" do
    assert_difference "Tournament.count", 1 do
      post tournaments_path, params: { tournament: {
        name: "Anchored Cup", date: "2026-02-10", deck_id: decks(:one).id,
        tier: "league_cup", format: "standard",
        standard_pool_id: standard_pools(:twm_por).id
      } }
    end

    assert_equal standard_pools(:twm_por), Tournament.order(:created_at).last.standard_pool
  end
```

- [ ] **Step 2: Run to verify it fails**

Run: `bin/rails test test/controllers/tournaments_controller_test.rb`
Expected: fails — `standard_pool_id` is not permitted, so the tournament is invalid and no row is created.

- [ ] **Step 3: Permit the parameter**

`app/controllers/tournaments_controller.rb:61`, add `:standard_pool_id` to the list:

```ruby
      :name, :date, :format, :other_format_name, :standard_pool_id, :tier, :deck_id, :tournament_profile_id,
```

- [ ] **Step 4: Add the field**

In `app/views/components/tournaments/form.rb`, immediately after the `format` group and before the `other_format_name` group:

```ruby
        render Ui::FormGroup.new(hint: "Only used when format is “Standard”") do
          f.label :standard_pool_id, "Standard", class: "form-label"
          f.collection_select :standard_pool_id, standard_pools, :id, :name,
            { selected: selected_standard_pool_id }, class: "form-input"
        end
```

And in the private section:

```ruby
      def standard_pools
        @standard_pools ||= StandardPool.includes(:first_card_set, :last_card_set).by_release
      end

      # A tournament is played under the format legal on its date, so the date is
      # the better default than "the newest pool". Falls back to current on a new
      # tournament, which has no date yet.
      def selected_standard_pool_id
        @tournament.standard_pool_id ||
          StandardPool.at(@tournament.date)&.id ||
          StandardPool.current&.id
      end
```

`StandardPool.at(nil)` would raise, so guard it if `@tournament.date` can be nil — `at` compares against the column, and `where(legal_on: ..nil)` yields an unbounded range that matches everything. Verify with `bin/rails runner 'p StandardPool.at(nil)&.name'`; if it does not return the newest pool, change `selected_standard_pool_id` to test `@tournament.date.present?` before calling `at`.

- [ ] **Step 5: Run to verify it passes**

Run: `bin/rails test`
Expected: 0 failures.

- [ ] **Step 6: Sabotage-verify**

Remove `:standard_pool_id` from the `permit` list. The new test must fail. Revert.

- [ ] **Step 7: Rubocop and commit**

```bash
bin/rubocop app/views/components/tournaments/form.rb app/controllers/tournaments_controller.rb
git add app/views/components/tournaments/form.rb app/controllers/tournaments_controller.rb test/controllers/tournaments_controller_test.rb
git commit -m "Let the tournament form pick which Standard

Defaults to the pool legal on the tournament's own date rather than to the
newest one, and follows this form's existing hint pattern instead of importing
the deck form's Stimulus toggling.

Refs #122"
```

---

## Task 10: The stale-anchor nudge

**Files:**
- Create: `app/views/components/decks/standard_pool_notice.rb`
- Modify: `app/views/components/decks/classification_fields.rb`
- Modify: `app/views/components/tournaments/form.rb`
- Test: `test/controllers/decks_controller_test.rb`, `test/controllers/tournaments_controller_test.rb`

**Interfaces:**
- Consumes: `StandardPool.current`, `StandardPool.at(date)`, `StandardPool#name`.
- Produces: `Decks::StandardPoolNotice.new(record:, expected:)` — renders nothing when `record` is a new record, when `expected` is nil, or when the anchor already is `expected`.

- [ ] **Step 1: Write the failing tests**

Append to `test/controllers/decks_controller_test.rb`:

```ruby
  # Pinned means pinned: nothing moves the anchor on its own, so the only way a
  # user learns a newer Standard exists is being told while editing.
  test "editing a deck anchored to an older pool invites an update" do
    decks(:one).update!(format: "standard", standard_pool: standard_pools(:twm_asc))

    get deck_path(decks(:one))

    assert_response :success
    assert_match "TWM-ASC", response.body
    assert_match "TWM-POR", response.body
    assert_match "released since", response.body
  end

  test "a deck on the current pool is not nagged" do
    decks(:one).update!(format: "standard", standard_pool: StandardPool.current)

    get deck_path(decks(:one))

    assert_response :success
    assert_no_match "released since", response.body
  end
```

Append to `test/controllers/tournaments_controller_test.rb`:

```ruby
  # For a tournament the comparison is the pool legal on its date, not the newest
  # one: a March 2026 event anchored to the latest pool is a data-entry error, not
  # a deck to refresh.
  test "editing a tournament whose anchor disagrees with its date says so" do
    tournaments(:one).update!(date: Date.new(2026, 1, 20), standard_pool: standard_pools(:twm_por))

    get edit_tournament_path(tournaments(:one))

    assert_response :success
    assert_match "TWM-ASC", response.body
  end
```

If the deck edit form lives behind a Turbo frame rather than the deck show page, adjust the request in the deck tests to whatever path renders `Decks::ClassificationFields` — read `app/views/components/decks/header_frame.rb` and the deck routes first.

- [ ] **Step 2: Run to verify they fail**

Run: `bin/rails test test/controllers/decks_controller_test.rb test/controllers/tournaments_controller_test.rb`
Expected: the two "invites an update" / "says so" tests fail on the missing text.

- [ ] **Step 3: Write the component**

Create `app/views/components/decks/standard_pool_notice.rb`:

```ruby
module Decks
  # Tells the user their record is anchored to a Standard that is no longer the
  # one expected, and invites them to move it. Informative only: the anchor is
  # pinned by design, and nothing here writes it.
  #
  # `expected` is the pool the record would take if it were created now — the
  # current pool for a deck, the pool legal on its date for a tournament. Those
  # are different questions: a tournament in the past is not stale, it is wrong.
  class StandardPoolNotice < ApplicationComponent
    def initialize(record:, expected:)
      @record = record
      @expected = expected
    end

    def view_template
      return unless applicable?

      div(class: "form-hint deck-standard-pool-notice") do
        plain "Anchored to "
        strong { @record.standard_pool.name }
        plain ". "
        strong { @expected.name }
        plain " has released since — update it if you still play this deck."
      end
    end

    private

    # Never on a creation form, where there is nothing to be stale about.
    def applicable?
      @record.persisted? && @expected.present? &&
        @record.standard_pool.present? && @record.standard_pool_id != @expected.id
    end
  end
end
```

- [ ] **Step 4: Render it on both forms**

In `app/views/components/decks/classification_fields.rb`, inside `standard_pool_field`, after the `collection_select`:

```ruby
        render Decks::StandardPoolNotice.new(record: @deck, expected: StandardPool.current)
```

In `app/views/components/tournaments/form.rb`, inside the Standard `FormGroup` block, after the `collection_select`:

```ruby
          render Decks::StandardPoolNotice.new(
            record: @tournament, expected: StandardPool.at(@tournament.date)
          )
```

- [ ] **Step 5: Run to verify they pass**

Run: `bin/rails test`
Expected: 0 failures.

- [ ] **Step 6: Sabotage-verify**

Change `applicable?` to drop the `@record.persisted?` clause. Add a temporary assertion that `get new_deck_path` contains no `"released since"`, confirm it fails, then revert both.

- [ ] **Step 7: Rubocop and commit**

```bash
bin/rubocop app/views/components/decks/standard_pool_notice.rb app/views/components/decks/classification_fields.rb app/views/components/tournaments/form.rb
git add app/views/components/decks/standard_pool_notice.rb app/views/components/decks/classification_fields.rb app/views/components/tournaments/form.rb test/controllers
git commit -m "Invite an update when a record's Standard is no longer current

The anchor is pinned and nothing moves it automatically, so editing is the
only moment a user can learn a newer Standard exists. Informative only.

A tournament compares against the pool legal on its own date rather than the
newest one: a March 2026 event anchored to the latest pool is a data-entry
error, not a deck to refresh.

Refs #122"
```

---

## Task 11: `ListDecksTool` names the pool

**Files:**
- Modify: `app/mcp/list_decks_tool.rb:2,8`
- Test: `test/mcp/list_decks_tool_test.rb` (create if absent — check `ls test/mcp` first and follow whatever pattern is there; if there is no MCP test directory, add the assertion to the existing MCP controller test instead)

**Interfaces:**
- Consumes: `Deck#standard_pool`, `StandardPool#name`.
- Produces: each deck in the tool's JSON payload gains a `standard_pool` key: the pool's name, or `null`.

- [ ] **Step 1: Write the failing test**

```ruby
  test "each deck names the Standard pool it is anchored to" do
    decks(:one).update!(format: "standard", standard_pool: standard_pools(:twm_por))

    payload = JSON.parse(ListDecksTool.call(server_context: { user: users(:one) }).content.first[:text])

    assert_equal "TWM-POR", payload.first["standard_pool"]
  end
```

Read an existing MCP tool test first and copy its invocation shape exactly — the `server_context` key and the way the text content is reached must match the suite, not this sketch.

- [ ] **Step 2: Run to verify it fails**

Expected: `KeyError` or `nil` for `standard_pool`.

- [ ] **Step 3: Implement**

`app/mcp/list_decks_tool.rb`:

```ruby
  description "List the authenticated user's decks with their ids, names, formats and Standard pool."
```

```ruby
      { id: deck.id, name: deck.name, format: deck.format,
        standard_pool: deck.standard_pool&.name,
        physical: deck.physical, tcg_live: deck.tcg_live }
```

Add `includes(:standard_pool)` to whatever relation the tool iterates, so the list does not fire a query per deck. Read the surrounding method to place it.

- [ ] **Step 4: Run, sabotage-verify, commit**

Run: `bin/rails test`

Sabotage: remove the `standard_pool:` key. The test must fail. Revert.

```bash
bin/rubocop app/mcp/list_decks_tool.rb
git add app/mcp/list_decks_tool.rb test/
git commit -m "Name the Standard pool in list_decks

The tool answered format: \"standard\", which is the ambiguity this issue
exists to remove — an MCP client could not tell a 2024 deck from a current one.

Refs #122"
```

---

## Task 12: Admin CRUD for pools

Without this, every set release needs a commit, a deploy and a `db:seed` before anyone can anchor a deck to the current Standard — roughly every seven weeks — while the admin panel already imports the set itself.

**Files:**
- Create: `app/controllers/admin/standard_pools_controller.rb`
- Create: `app/views/components/admin/standard_pools/index_view.rb`
- Create: `app/views/components/admin/standard_pools/form.rb`
- Modify: `config/routes.rb` (the `namespace :admin` block)
- Modify: `app/views/components/ui/admin_navbar.rb:46`
- Test: `test/controllers/admin/standard_pools_controller_test.rb`

**Interfaces:**
- Consumes: `StandardPool` and everything from Task 2; `Ui::PageHeader`, `Ui::DataTable`, `Ui::AdminActions`, `Ui::FormErrors`, `Ui::FormGroup` (all existing).
- Produces: `admin_standard_pools_path`, `new_admin_standard_pool_path`, `edit_admin_standard_pool_path(pool)`, `admin_standard_pool_path(pool)`.

- [ ] **Step 1: Add the route**

In `config/routes.rb`, inside `namespace :admin do`, after `resources :archetypes`:

```ruby
      resources :standard_pools, except: [ :show ]
```

`except: :show` because a pool is five fields: the index already shows all of them, so a show page would only restate the row.

- [ ] **Step 2: Write the failing tests**

Create `test/controllers/admin/standard_pools_controller_test.rb`:

```ruby
require "test_helper"

class Admin::StandardPoolsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
  end

  test "the index lists pools newest first with their bounds and marks" do
    get admin_standard_pools_path

    assert_response :success
    assert_match "TWM-POR", response.body
    assert_match "TWM-ASC", response.body
    assert_match "G, H, I, J", response.body
  end

  # A set release moves only the upper bound, so the parts a human does not know
  # are pre-filled from the current pool. Typing them again is how a wrong pool
  # gets seeded.
  test "the new form pre-fills the lower bound and the marks from the current pool" do
    get new_admin_standard_pool_path

    assert_response :success
    assert_match "G, H, I, J", response.body
  end

  test "creates a pool" do
    assert_difference "StandardPool.count", 1 do
      post admin_standard_pools_path, params: { standard_pool: {
        first_card_set_id: card_sets(:asc).id,
        last_card_set_id: card_sets(:por).id,
        regulation_marks: "H, I, J",
        released_on: "2026-06-01",
        legal_on: "2026-06-15"
      } }
    end

    pool = StandardPool.order(:created_at).last
    assert_equal %w[H I J], pool.regulation_marks
    assert_equal "ASC-POR", pool.name
  end

  test "rejects a duplicate bound pair" do
    assert_no_difference "StandardPool.count" do
      post admin_standard_pools_path, params: { standard_pool: {
        first_card_set_id: card_sets(:twm).id,
        last_card_set_id: card_sets(:por).id,
        regulation_marks: "H, I, J",
        released_on: "2026-06-01",
        legal_on: "2026-06-15"
      } }
    end

    assert_response :unprocessable_entity
  end

  # restrict_with_error, not nullify: a NULL anchor on a Standard deck is
  # unsavable on its next edit.
  test "refuses to delete a pool decks are anchored to" do
    assert_no_difference "StandardPool.count" do
      delete admin_standard_pool_path(standard_pools(:twm_por))
    end

    assert_redirected_to admin_standard_pools_path
    assert_match "deck", flash[:alert]
  end

  test "requires an admin" do
    @admin.update!(admin: false)

    get admin_standard_pools_path

    assert_response :redirect
  end
end
```

- [ ] **Step 3: Run to verify they fail**

Run: `bin/rails test test/controllers/admin/standard_pools_controller_test.rb`
Expected: every test errors on the missing controller.

- [ ] **Step 4: Write the controller**

Create `app/controllers/admin/standard_pools_controller.rb`:

```ruby
module Admin
  class StandardPoolsController < BaseController
    before_action :set_standard_pool, only: [ :edit, :update, :destroy ]

    def index
      @standard_pools = StandardPool.includes(:first_card_set, :last_card_set).by_release
    end

    def new
      # A set release moves only the upper bound, so everything else is carried
      # over from the pool in force. The annual rotation is the one case where the
      # lower bound and the marks are typed in full.
      current = StandardPool.current
      @standard_pool = StandardPool.new(
        first_card_set_id: current&.first_card_set_id,
        regulation_marks: current&.regulation_marks
      )
    end

    def create
      @standard_pool = StandardPool.new(standard_pool_params)

      if @standard_pool.save
        redirect_to admin_standard_pools_path, notice: "Standard pool created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      if @standard_pool.update(standard_pool_params)
        redirect_to admin_standard_pools_path, notice: "Standard pool updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @standard_pool.destroy
        redirect_to admin_standard_pools_path, notice: "Standard pool deleted."
      else
        redirect_to admin_standard_pools_path, alert: @standard_pool.errors.full_messages.to_sentence
      end
    end

    private

    def set_standard_pool
      @standard_pool = StandardPool.find(params[:id])
    end

    def standard_pool_params
      permitted = params.require(:standard_pool)
        .permit(:first_card_set_id, :last_card_set_id, :regulation_marks, :released_on, :legal_on)

      # The form takes marks as free text ("H, I, J") because a fixed checkbox list
      # would need a deploy the first time a new mark is printed — the very thing
      # this screen exists to avoid.
      permitted.merge(regulation_marks: parse_marks(permitted[:regulation_marks]))
    end

    def parse_marks(value)
      return value if value.is_a?(Array)

      value.to_s.split(",").map { |mark| mark.strip.upcase }.reject(&:empty?)
    end
  end
end
```

- [ ] **Step 5: Write the index view**

Create `app/views/components/admin/standard_pools/index_view.rb`:

```ruby
module Admin
  module StandardPools
    class IndexView < ApplicationComponent
      def initialize(standard_pools:)
        @standard_pools = standard_pools
        @current = StandardPool.current
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Standard Pools") do
            link_to "New Pool", new_admin_standard_pool_path, class: "btn btn-primary"
          end

          render Ui::DataTable.new(
            columns: [ "Pool", "Marks", "Released", "Legal", "Decks", "Tournaments", "Actions" ]
          ) do |t|
            @standard_pools.each { |pool| row(t, pool) }
          end
        end
      end

      private

      def row(t, pool)
        t.row do
          t.cell { pool == @current ? "#{pool.name} (current)" : pool.name }
          t.cell { pool.regulation_marks.join(", ") }
          t.cell { pool.released_on.strftime("%Y-%m-%d") }
          t.cell { pool.legal_on.strftime("%Y-%m-%d") }
          t.cell { pool.decks.size.to_s }
          t.cell { pool.tournaments.size.to_s }
          t.cell do
            render Ui::AdminActions.new(
              edit_path: edit_admin_standard_pool_path(pool),
              delete_path: admin_standard_pool_path(pool),
              confirm_message: "Delete #{pool.name}?"
            )
          end
        end
      end
    end
  end
end
```

The deck and tournament counts are what make a refused deletion legible before it is attempted. `Ui::DataTable`'s block API is `t.row` / `t.cell` — confirmed against `app/views/components/admin/card_sets/index_view.rb`.

- [ ] **Step 6: Write the form view**

Create `app/views/components/admin/standard_pools/form.rb`:

```ruby
module Admin
  module StandardPools
    class Form < ApplicationComponent
      def initialize(standard_pool:)
        @standard_pool = standard_pool
      end

      def view_template
        form_with(model: [ :admin, @standard_pool ], class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @standard_pool)

          render Ui::FormGroup.new(hint: "The oldest legal set — moved by the annual rotation") do
            f.label :first_card_set_id, "Lower bound", class: "form-label"
            f.collection_select :first_card_set_id, card_sets, :id, :code, {}, class: "form-input"
          end

          render Ui::FormGroup.new(hint: "The newest legal set — moved by every release") do
            f.label :last_card_set_id, "Upper bound", class: "form-label"
            f.collection_select :last_card_set_id, card_sets, :id, :code, {}, class: "form-input"
          end

          render Ui::FormGroup.new(hint: "Comma-separated, e.g. H, I, J") do
            f.label :regulation_marks, "Legal regulation marks", class: "form-label"
            f.text_field :regulation_marks, value: marks_value, class: "form-input"
          end

          render Ui::FormGroup.new(hint: "When the cards exist — decides the default for a new deck") do
            f.label :released_on, "Released on", class: "form-label"
            f.date_field :released_on, class: "form-input"
          end

          render Ui::FormGroup.new(hint: "Play! Pokémon legality, about two weeks after release") do
            f.label :legal_on, "Legal on", class: "form-label"
            f.date_field :legal_on, class: "form-input"
          end

          div(class: "form-actions deck-form-actions") do
            f.submit class: "btn btn-primary"
            link_to "Cancel", admin_standard_pools_path, class: "btn btn-secondary"
          end
        end
      end

      private

      def card_sets
        @card_sets ||= CardSet.by_release
      end

      # The column is json; the input is text. Rendered joined so a round-trip
      # through a failed validation shows what the user typed.
      def marks_value
        Array(@standard_pool.regulation_marks).join(", ")
      end
    end
  end
end
```

- [ ] **Step 7: Render the views from the controller**

Follow whatever `Admin::ArchetypesController` does to render a Phlex component — read `app/controllers/admin/archetypes_controller.rb` together with `app/views/admin/archetypes/` (or the `ApplicationController` render override, if the project renders components directly). Wire `index`, `new` and `edit` the same way. Do not invent a second mechanism.

- [ ] **Step 8: Add the navbar link**

`app/views/components/ui/admin_navbar.rb`, after the Archetypes line:

```ruby
        nav_link "Standard Pools", admin_standard_pools_path, "standard_pools"
```

- [ ] **Step 9: Run to verify they pass**

Run: `bin/rails test test/controllers/admin/standard_pools_controller_test.rb`
Expected: 7 runs, 0 failures.

- [ ] **Step 10: Sabotage-verify**

1. Remove the `first_card_set_id` / `regulation_marks` pre-fill from `new`. `the new form pre-fills…` must fail. Revert.
2. Change `dependent: :restrict_with_error` on `StandardPool#decks` to `:nullify`. `refuses to delete a pool decks are anchored to` must fail. Revert.

- [ ] **Step 11: Rubocop, full suite, commit**

```bash
bin/rubocop app/controllers/admin/standard_pools_controller.rb app/views/components/admin/standard_pools
bin/rails test
git add app/controllers/admin/standard_pools_controller.rb app/views/components/admin/standard_pools app/views/components/ui/admin_navbar.rb config/routes.rb test/controllers/admin/standard_pools_controller_test.rb
git commit -m "Maintain Standard pools from the admin panel

A pool is created roughly every seven weeks, and the seed alone would mean a
commit, a deploy and a db:seed before anyone could anchor a deck to the
current Standard — while the admin panel already imports the set itself.

The new form pre-fills the lower bound and the marks from the pool in force,
because a set release moves only the upper bound; the annual rotation is the
one case worth typing in full. Marks are free text rather than a checkbox
list, which would need a deploy the first time a new mark is printed.

The index carries deck and tournament counts, which is what makes a refused
deletion legible before it is attempted.

Refs #122"
```

---

## Task 13: System tests

**Files:**
- Create: `test/system/standard_pools_test.rb`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Write the tests**

Create `test/system/standard_pools_test.rb`. Read `test/system/` for the file that creates a deck through the UI and copy its navigation and setup verbatim — in particular `login_as user, scope: :user` and `click_nav_link`, never a bare click on a nav link.

```ruby
require "application_system_test_case"

class StandardPoolsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
  end

  test "picking a Standard when creating a deck shows it on the badge" do
    visit new_deck_path

    fill_in "Name", with: "Anchored deck"
    select "TWM-ASC", from: "deck_standard_pool_id"
    click_on "Create Deck"

    assert_text "Standard (TWM-ASC)"
  end

  # The picker is conditional: the eternal formats have no pool.
  test "the Standard picker disappears when the format is not Standard" do
    visit new_deck_path

    assert_selector "#deck_standard_pool_id", visible: true
    select "GLC", from: "deck_format"
    assert_selector "#deck_standard_pool_id", visible: false
  end

  test "a deck anchored to an older Standard is invited to update" do
    decks(:one).update!(format: "standard", standard_pool: standard_pools(:twm_asc))

    visit deck_path(decks(:one))

    assert_text "released since"
  end
end
```

The submit button's label comes from Rails' default for the model — check the actual label in `app/views/components/decks/new_view.rb` and use that string.

- [ ] **Step 2: Run at both viewports**

```bash
bin/rails test:system test/system/standard_pools_test.rb
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system test/system/standard_pools_test.rb
```

Both must pass. If a click fails below the breakpoint, the cause is almost always the navbar (`click_nav_link`) or the card-preview `<dialog>` backdrop eating a later click — see the Test Setup section of `CLAUDE.md`.

- [ ] **Step 3: Sabotage-verify**

Remove the `standardField` target from the Stimulus controller's `toggle`. `the Standard picker disappears when the format is not Standard` must fail. Revert.

- [ ] **Step 4: Full suite and commit**

```bash
bin/rails test
bin/rails test:system
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system
bin/rubocop
bin/brakeman --no-pager
git add test/system/standard_pools_test.rb
git commit -m "System-test the Standard picker at both viewports

Covers the three things only a browser can: the picker is conditional on the
format, the chosen pool reaches the badge, and a stale anchor is surfaced.

Refs #122"
```

---

## Task 14: Update the project documentation

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:** none.

- [ ] **Step 1: Add `StandardPool` to the Models paragraph**

In the **Models** section of `CLAUDE.md`, after the `CardSet has_many Cards…` sentence, add:

```markdown
`StandardPool` is one period of the rotating Standard calendar: two `CardSet` bounds — the oldest legal set, moved by the annual rotation, and the newest, moved by every release — plus the legal `regulation_marks` and **two** dates. `(first_card_set_id, last_card_set_id)` is UNIQUE because that pair *is* the pool's name, `TEF-PBL`, which is what players call it. `released_on` says the cards exist and drives `StandardPool.current`, the anchor a new deck is pre-selected to; `legal_on` says Play! Pokémon considers the pool legal and drives `StandardPool.at(date)`, which is what a tournament asks — a set is tournament-legal about two weeks after it ships, so neither date derives from the other. `Deck` and `Tournament` each carry a `standard_pool_id`, required by validation when the format is `standard` and cleared otherwise (the `other_format_name` pattern): **only Standard rotates**, the other three formats are eternal and have no anchor. The anchor is **pinned** — nothing moves it automatically, and `Decks::StandardPoolNotice` merely invites the user to. `has_many :decks, dependent: :restrict_with_error`, unlike `Archetype`'s `:nullify`, because a NULL anchor on a Standard deck is unsavable on its next edit. Deck-construction rules are deliberately **not** here: see #61.
```

- [ ] **Step 2: Note the seed and the backfill task**

In the **Bin Scripts** section, add:

```markdown
- `bin/rails standard_pools:backfill_anchors` — anchor Standard decks and tournaments that predate the `standard_pool_id` column. Run **after** `db:seed`, which creates the pools it needs; idempotent.
```

- [ ] **Step 3: Note the importer change**

In the **Key services** list, amend the `CardSets::Importer` entry to record that it now writes `release_date` (guarded by `||=`, so a hand-seeded date wins), since the entry currently says it sets only `code`, `name` and `logo_url`.

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Document StandardPool and the anchor

Refs #122"
```

---

## Self-review

**Spec coverage.** Every section of the spec maps to a task:

| Spec section | Task |
|---|---|
| `standard_pools` table, `#name`, `current`, `at` | 2 |
| `restrict_with_error` and why | 2, 12 |
| The anchor on `Deck`, `Fetcher`, `Duplicator` | 4 |
| The anchor on `Tournament` | 5 |
| `CardSets::Importer` writes `release_date` | 1 |
| Missing sets, pool history, derivation rule, review gate | 3 |
| Backfill | 6 |
| `#format_label` | 7 |
| Deck form field + Stimulus generalisation + strong params | 8 |
| Tournament form field + strong params | 9 |
| Stale-anchor nudge | 10 |
| `ListDecksTool` | 11 |
| Admin CRUD, pre-filled form, index counts, seed-as-bootstrap | 12 |
| Both-viewport system tests | 13 |

**Two deliberate deviations from the spec**, both to be reported to the maintainer:

1. **The backfill is a rake task, not part of the migration.** A migration cannot depend on seed data that runs after it. This also removes the spec's "not covered by a test" caveat — a service behind a rake task is testable, and Task 6 tests it.
2. **The tournament form uses the hint pattern, not Stimulus toggling.** `app/views/components/tournaments/form.rb` already renders `other_format_name` unconditionally with "Only used when format is “Other”"; matching the file beats importing the deck form's controller.

**One seam the spec does not record**, found while building the seed table: between a set's release and its legality date, `StandardPool.current` returns the *new* pool while tournaments are still played under the old one — two weeks a year. `current` is a pre-selection the user can change, and `at(date)` is exact for tournaments, so this is a known imprecision rather than a bug. Add it to the spec's **Known seams** before starting Task 1.

**Type consistency.** `StandardPool#name`, `.current`, `.at(date)`, `.by_release`, `#regulation_marks` (Array of String), `#released_on`, `#legal_on` are used identically in Tasks 3–13. `StandardPools::AnchorBackfill::Result` fields (`decks`, `tournaments`, `skipped`) are used only in Task 6's test and rake task, and match. `Decks::StandardPoolNotice.new(record:, expected:)` is called with those exact keywords from both forms in Task 10.
