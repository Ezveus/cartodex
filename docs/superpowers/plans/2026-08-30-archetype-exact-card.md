# Archetypes designate an exact card — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let an `Archetype` designate an exact card of any type (Pokémon, Trainer or Energy), keyed on the card's fingerprint rather than its name, so Trainer-led decks like Lost Zone Box can finally be named.

**Architecture:** The `archetypes` table renames its two card foreign keys and gains two denormalised fingerprint columns that back a real unique index (the current one is a no-op for single-member archetypes, because SQLite treats NULLs as distinct). `Decks::ArchetypeDetector` splits its two conflated jobs: *matching* becomes type-agnostic and fingerprint-keyed over the whole deck with a weighted score, while *suggesting* stays Pokémon-only and unchanged. The autocomplete component becomes type-agnostic and stops collapsing printings.

**Tech Stack:** Rails 8.1, Ruby 3.4.1, SQLite3, Minitest, Phlex components, Hotwire/Stimulus, Propshaft + importmap.

**Spec:** `docs/superpowers/specs/2026-08-30-archetype-exact-card-design.md`

**Issue:** #120

## Global Constraints

- **Branch from `docs/120-archetype-exact-card-design`** — the spec ships with the implementation. Suggested branch name: `feat/120-archetype-exact-card`.
- **Identity is the fingerprint pair, never the card-id pair.** A different printing of the same card is the *same* archetype.
- **A missing secondary fingerprint is the empty string `""`, never `NULL`.** SQLite treats NULLs as distinct; a nullable column reproduces exactly the hole this work exists to close.
- **The denormalised columns back the unique index and nothing else.** Detection reads `cards.fingerprint` through a join — the live truth — and never the copy. Nothing decides anything from the denormalised value.
- **Never delete an archetype row to resolve a duplicate.** `decks.archetype_id` and `deck_results.archetype_id` point at these rows; dropping one silently reassigns somebody's data. Fail and name the offenders instead.
- **`cards(:trainer_card)` must keep its `NULL` fingerprint.** `test/services/cards/printings_test.rb:48` and `test/services/decks/printing_swapper_test.rb:125` both assert it. Give other fixtures fingerprints, never that one.
- Comments and code in English. Run `bin/rubocop` before each commit; CI runs `bin/brakeman --no-pager`, `bin/importmap audit`, `bin/rubocop -f github`, `bin/rails test test:system`, and the system suite again with `SYSTEM_TEST_VIEWPORT=mobile`.

---

## File Structure

**Migrations (new):**
- `db/migrate/<ts>_rename_archetype_pokemon_columns.rb` — column rename + deterministic index name
- `db/migrate/<ts>_add_fingerprints_to_archetypes.rb` — denormalised columns, backfill, duplicate detection, real unique index

**Modified:**
- `app/models/archetype.rb` — associations, validations, `search` scope alias, fingerprint sync callback
- `app/services/decks/archetype_detector.rb` — the two-job split
- `app/controllers/api/archetypes_controller.rb` — fingerprint-keyed lookup, any card type, richer JSON
- `app/controllers/api/decks_controller.rb` — `suggested_archetype` payload keys
- `app/controllers/decks_controller.rb` — deck-list filter columns
- `app/controllers/admin/archetypes_controller.rb` — permitted params, includes
- `app/views/components/admin/archetypes/{form,index_view,show_view}.rb`
- `app/views/components/decks/{archetype_field,result_modal}.rb`
- `app/javascript/controllers/{card_select,archetype_picker,result_modal}_controller.js`
- `test/fixtures/{cards,archetypes}.yml`
- `CLAUDE.md`

**Created:**
- `app/views/components/ui/card_select.rb` (replaces `ui/pokemon_select.rb`)
- `app/javascript/controllers/card_select_controller.js` (replaces `pokemon_select_controller.js`)
- `app/services/archetypes/fingerprint_sync.rb`
- `lib/tasks/archetypes.rake`
- `test/services/archetypes/fingerprint_sync_test.rb`
- `test/controllers/api/archetypes_controller_test.rb`
- `test/system/archetype_any_card_test.rb`

---

### Task 1: Rename the card columns and associations

Pure rename, no behaviour change. Isolated so that the fingerprint work in Task 2 lands on stable names, and so a reviewer can check the rename without also reading new logic.

The one trap: `Archetype.search` writes its join alias by hand (`secondary_pokemons_archetypes`). Rails derives that alias from the association name, so the rename breaks the scope **at query time, not at load time** — nothing raises until the SQL runs.

**Files:**
- Create: `db/migrate/<ts>_rename_archetype_pokemon_columns.rb`
- Modify: `app/models/archetype.rb`, `app/services/decks/archetype_detector.rb`, `app/controllers/api/archetypes_controller.rb`, `app/controllers/api/decks_controller.rb`, `app/controllers/decks_controller.rb`, `app/controllers/admin/archetypes_controller.rb`, `app/controllers/deck_results_controller.rb`, `app/views/components/admin/archetypes/{form,index_view,show_view}.rb`
- Test: `test/models/archetype_test.rb`, `test/fixtures/archetypes.yml`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `Archetype#primary_card`, `Archetype#secondary_card`, columns `archetypes.primary_card_id` / `archetypes.secondary_card_id`, unique index named `index_archetypes_on_card_pair`.

- [ ] **Step 1: Write the failing test**

`test/models/archetype_test.rb` already covers all three columns of the `search` scope. Add one test that pins the association names themselves, so a half-done rename fails loudly rather than at query time in some other file. Append to `test/models/archetype_test.rb`:

```ruby
  # The `search` scope spells its second join alias by hand, and Rails derives
  # that alias from the association name — so renaming the association breaks
  # the scope at query time, not at load time. These two run the SQL.
  test "search runs against the renamed associations" do
    assert_respond_to archetypes(:ogerpon), :primary_card
    assert_respond_to archetypes(:ogerpon), :secondary_card
    assert_nothing_raised { Archetype.search("Ogerpon").to_a }
  end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/models/archetype_test.rb -n "/renamed associations/"`
Expected: FAIL with `Expected #<Archetype…> to respond to :primary_card`.

- [ ] **Step 3: Write the migration**

Generate a timestamp with `bin/rails generate migration RenameArchetypePokemonColumns` and replace the body:

```ruby
class RenameArchetypePokemonColumns < ActiveRecord::Migration[8.1]
  # An archetype's members were always Cards; only the column names claimed they
  # were Pokémon. The index is dropped and re-added by hand rather than left to
  # `rename_column`, which regenerates the auto-derived name — the next migration
  # has to remove this index, and it can only do that if it knows what it is called.
  def up
    remove_index :archetypes, name: "idx_on_primary_pokemon_id_secondary_pokemon_id_2a04cf9ccd"
    rename_column :archetypes, :primary_pokemon_id, :primary_card_id
    rename_column :archetypes, :secondary_pokemon_id, :secondary_card_id
    add_index :archetypes, [ :primary_card_id, :secondary_card_id ],
      unique: true, name: "index_archetypes_on_card_pair"
  end

  def down
    remove_index :archetypes, name: "index_archetypes_on_card_pair"
    rename_column :archetypes, :primary_card_id, :primary_pokemon_id
    rename_column :archetypes, :secondary_card_id, :secondary_pokemon_id
    add_index :archetypes, [ :primary_pokemon_id, :secondary_pokemon_id ],
      unique: true, name: "idx_on_primary_pokemon_id_secondary_pokemon_id_2a04cf9ccd"
  end
end
```

Run: `bin/rails db:migrate` and check `db/schema.rb` now shows `primary_card_id`, `secondary_card_id` and `index_archetypes_on_card_pair`.

- [ ] **Step 4: Rename in the model**

`app/models/archetype.rb` — replace lines 4-5, 12, and the `search` scope body, plus the two reader methods:

```ruby
  belongs_to :primary_card, class_name: "Card"
  belongs_to :secondary_card, class_name: "Card", optional: true
```

```ruby
  validates :primary_card_id, uniqueness: { scope: :secondary_card_id }
```

```ruby
  # Matches the archetype's own name or either member card's, all three through their
  # normalized mirrors (see NameNormalizable). Every LIKE needs its own ESCAPE clause. Spans
  # three columns, so it can't delegate to the concern's single-column scope.
  scope :search, ->(q) {
    like = "LIKE :q ESCAPE '\\'"
    left_joins(:primary_card, :secondary_card)
      .where(
        "archetypes.name_normalized #{like} OR cards.name_normalized #{like} " \
        "OR secondary_cards_archetypes.name_normalized #{like}",
        q: "%#{normalize_for_match(q)}%"
      )
      .distinct
  }
```

```ruby
  # Energy type of the lead card, used to colour the archetype's badge. Nil for a
  # Trainer- or Energy-led archetype, which the badge already falls back on.
  def primary_energy_type
    primary_card&.type_symbol
  end

  # Distinct energy types of the archetype's member cards, primary first.
  def energy_types
    [ primary_card, secondary_card ].compact.map(&:type_symbol).compact.uniq
  end
```

```ruby
  def auto_generate_name
    parts = [ primary_card&.name, secondary_card&.name ].compact
    self.name = parts.join(" / ") if parts.any?
  end
```

- [ ] **Step 5: Rename at every other call site**

Mechanical. Run this to find them all, then edit each:

```bash
grep -rn "primary_pokemon\|secondary_pokemon" app/ test/ lib/ --include='*.rb' --include='*.yml'
```

The Ruby-side list, exhaustively:

- `app/services/decks/archetype_detector.rb:54,55,57,67` — `joins(:primary_card)`, `left_joins(:secondary_card)`, `includes(:primary_card, :secondary_card)`, `archetype.secondary_card&.name`
- `app/controllers/api/archetypes_controller.rb:8,10,17,18,21,22,43,44` — includes, param names `primary_card_id`/`secondary_card_id`, `find_or_initialize_by(primary_card:, secondary_card:)`, `archetype_json` keys `primary_card`/`secondary_card`
- `app/controllers/api/decks_controller.rb:72,73` — `archetype.primary_card.name`, `archetype.secondary_card&.name`
- `app/controllers/decks_controller.rb:167,172,202,203` — `pokemon_filter_options(:primary_card_id)` / `(:secondary_card_id)`, and `where(archetypes: { primary_card_id: … })` / `{ secondary_card_id: … }`
- `app/controllers/deck_results_controller.rb:6` — `includes(archetype: :primary_card)`
- `app/controllers/decks_controller.rb:7,47,56` — the `includes(archetype: [ :primary_card, :secondary_card ])` chains
- `app/controllers/admin/archetypes_controller.rb:6,50` — includes and `permit(:name, :primary_card_id, :secondary_card_id, :parent_id)`
- `app/views/components/admin/archetypes/form.rb:17,18` — `pokemon_autocomplete(f, :primary_card_id, …, @archetype.primary_card)` and the secondary
- `app/views/components/admin/archetypes/index_view.rb:18,19` — `arch.primary_card.name`, `arch.secondary_card&.name`
- `app/views/components/admin/archetypes/show_view.rb:22,23,32,35,36` — same shape

The JSON keys `primary_pokemon` / `secondary_pokemon` in both API controllers change to `primary_card` / `secondary_card`, so update the two JS readers in the same commit:

- `app/javascript/controllers/archetype_picker_controller.js:105,106` — request body keys → `primary_card_id`, `secondary_card_id`
- `app/javascript/controllers/archetype_picker_controller.js:145` — `a.primary_card` / `a.secondary_card`
- `app/javascript/controllers/result_modal_controller.js:118,119,144` — same two changes

Leave `data.primary_pokemon` at `archetype_picker_controller.js:72-73` alone for now — Task 3 renames that payload.

- [ ] **Step 6: Rename in the fixtures**

`test/fixtures/archetypes.yml` — keys `primary_pokemon:` / `secondary_pokemon:` become `primary_card:` / `secondary_card:`:

```yaml
ogerpon:
  primary_card: teal_mask_ogerpon_ex
  name: "Teal Mask Ogerpon ex"
  name_normalized: "teal mask ogerpon ex"

budew_ogerpon:
  primary_card: budew_pre
  secondary_card: teal_mask_ogerpon_ex
  name: "Budew / Teal Mask Ogerpon ex"
  name_normalized: "budew / teal mask ogerpon ex"
```

Also update the comment on line 3 to say "member cards" rather than "primary/secondary Pokémon", and `test/models/archetype_test.rb:29-38,43` which name the old alias and the old association in a comment and two `update!` calls:

```ruby
  # Drift protection for the third column of the scope: name_normalized is read off
  # secondary_cards_archetypes (the join alias), not primary_cards_archetypes or
```

```ruby
    archetype.update!(secondary_card: secondary, name: "Mystery Box", custom_name: "1")
```

```ruby
    archetype.update!(secondary_card: nil, custom_name: "1")
```

- [ ] **Step 7: Run the full suite**

Run: `bin/rails test && bin/rubocop`
Expected: PASS. If `Archetype.search` raises `no such column: secondary_pokemons_archetypes.name_normalized`, Step 4's scope edit was missed.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "Rename an archetype's members from Pokémon to cards

An archetype's members were always Card records; only the column names
claimed otherwise. Pure rename, no behaviour change — but the search
scope spells its join alias by hand, so it breaks at query time rather
than at load time and needs a test that runs the SQL."
```

---

### Task 2: Denormalised fingerprints and a unique index that works

The existing unique index on the card-id pair does not do what it looks like it does: SQLite treats NULLs as distinct, so two archetypes with the same primary and no secondary are accepted by the database. Only the model validation stops them today — the race-prone shape this task replaces.

**Files:**
- Create: `db/migrate/<ts>_add_fingerprints_to_archetypes.rb`, `app/services/archetypes/fingerprint_sync.rb`, `lib/tasks/archetypes.rake`, `test/services/archetypes/fingerprint_sync_test.rb`
- Modify: `app/models/archetype.rb`, `test/fixtures/cards.yml`, `test/fixtures/archetypes.yml`, `test/models/archetype_test.rb`
- Test: `test/models/archetype_test.rb`, `test/services/archetypes/fingerprint_sync_test.rb`

**Interfaces:**
- Consumes: `Archetype#primary_card` / `#secondary_card` (Task 1), `Card#fingerprint`.
- Produces: columns `archetypes.primary_fingerprint` (NOT NULL) and `archetypes.secondary_fingerprint` (NOT NULL, default `""`); unique index `index_archetypes_on_fingerprint_pair`; `Archetypes::FingerprintSync.call → Result(updated:, collisions:)` where `collisions` is an Array of `Archetype`.

- [ ] **Step 1: Give the card fixtures fingerprints**

Fixtures skip callbacks, so `compute_fingerprint` never runs on them and most cards carry `NULL`. Fingerprint-keyed matching finds nothing against `NULL`, so the fixtures need values. The repo's established pattern is a sentinel string, not a real hash (`budew_shared`, `froakie_cri_fp` already do this).

**`cards(:trainer_card)` must stay `NULL`** — two existing tests assert it (`printings_test.rb:48`, `printing_swapper_test.rb:125`).

In `test/fixtures/cards.yml`, add a `fingerprint:` line to these five fixtures only:

```yaml
honedge:
  …
  fingerprint: honedge_fp

doublade:
  …
  fingerprint: doublade_fp

bosss_orders_meg:
  …
  fingerprint: bosss_orders_meg_fp

basic_psychic_energy:
  …
  fingerprint: basic_psychic_energy_fp

teal_mask_ogerpon_ex:
  …
  fingerprint: ogerpon_shared
```

`bosss_orders_meg` deliberately does **not** share with `trainer_card`: it is the Trainer used to build a Trainer-led archetype in Tasks 3-5, and `trainer_card` has to keep its `NULL`.

- [ ] **Step 2: Give the archetype fixtures their denormalised pair**

`test/fixtures/archetypes.yml` — the columns are NOT NULL and fixtures skip callbacks, so spell them out. Note the empty-string sentinel on `ogerpon`:

```yaml
# Read about fixtures at https://api.rubyonrails.org/classes/ActiveRecord/FixtureSet.html
#
# NOTE: archetypes hold a foreign key to cards (their member cards), so only
# reference cards that are not destroyed by other tests (e.g. avoid honedge).
#
# Fixtures skip callbacks, so name_normalized and the denormalised fingerprint pair are
# spelled out by hand; ArchetypeTest asserts both stay in step. A missing secondary is the
# empty string, never NULL — see the migration for why.

ogerpon:
  primary_card: teal_mask_ogerpon_ex
  primary_fingerprint: ogerpon_shared
  secondary_fingerprint: ""
  name: "Teal Mask Ogerpon ex"
  name_normalized: "teal mask ogerpon ex"

budew_ogerpon:
  primary_card: budew_pre
  secondary_card: teal_mask_ogerpon_ex
  primary_fingerprint: budew_shared
  secondary_fingerprint: ogerpon_shared
  name: "Budew / Teal Mask Ogerpon ex"
  name_normalized: "budew / teal mask ogerpon ex"
```

- [ ] **Step 3: Write the failing tests**

Append to `test/models/archetype_test.rb`:

```ruby
  # --- Fingerprint identity ---

  test "the fingerprint pair is filled from the member cards on save" do
    archetype = Archetype.create!(primary_card: cards(:doublade), secondary_card: cards(:bosss_orders_meg))

    assert_equal "doublade_fp", archetype.primary_fingerprint
    assert_equal "bosss_orders_meg_fp", archetype.secondary_fingerprint
  end

  # The empty string, never NULL: SQLite treats NULLs as distinct, so a nullable
  # column would let two single-member archetypes through the unique index —
  # exactly the hole the card-id index left open.
  test "a missing secondary is stored as the empty string" do
    archetype = Archetype.create!(primary_card: cards(:doublade))

    assert_equal "", archetype.secondary_fingerprint
  end

  # The pair is spelled out rather than left to sync_fingerprints: `validate: false`
  # skips before_validation too, so the callback would not run and the row would
  # die on NOT NULL instead of reaching the index this test is about.
  test "the database refuses two single-member archetypes on the same fingerprint" do
    duplicate = Archetype.new(primary_card: cards(:teal_mask_ogerpon_ex), name: "Ogerpon again",
      primary_fingerprint: "ogerpon_shared", secondary_fingerprint: "")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  # Identity is the fingerprint pair, so a different printing of the same card is
  # the same archetype — this is what makes the printing a display reference.
  test "the database refuses a second archetype built from another printing of the same card" do
    reprint = cards(:froakie_cri)
    reprint.update_column(:fingerprint, "ogerpon_shared")
    duplicate = Archetype.new(primary_card: reprint, name: "Ogerpon reprint",
      primary_fingerprint: "ogerpon_shared", secondary_fingerprint: "")

    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "a card with no fingerprint cannot be designated" do
    archetype = Archetype.new(primary_card: cards(:trainer_card), name: "Boss")

    assert_not archetype.valid?
    assert_includes archetype.errors[:primary_fingerprint], "can't be blank"
  end
```

- [ ] **Step 4: Run them to verify they fail**

Run: `bin/rails test test/models/archetype_test.rb`
Expected: FAIL — `no such column: archetypes.primary_fingerprint` (and the fixtures themselves will fail to load, for the same reason).

- [ ] **Step 5: Write the migration**

`bin/rails generate migration AddFingerprintsToArchetypes`, then:

```ruby
class AddFingerprintsToArchetypes < ActiveRecord::Migration[8.1]
  # `(primary_card_id, secondary_card_id)` is UNIQUE but does not do what it looks
  # like it does: SQLite treats NULLs as distinct, so two archetypes sharing a
  # primary and holding no secondary are accepted by the database. Only the model
  # validation has been stopping them.
  #
  # Identity is really the pair of *fingerprints* — two archetypes built from two
  # printings of the same cards are duplicates, not siblings — so the index moves
  # onto denormalised copies of them, and a missing secondary is the empty string
  # rather than NULL so the pair is always fully comparable.
  #
  # Raw SQL rather than the Archetype model on purpose: a migration must keep
  # meaning what it meant when it ran, and the model will move on.
  def up
    add_column :archetypes, :primary_fingerprint, :string
    add_column :archetypes, :secondary_fingerprint, :string, null: false, default: ""

    execute <<~SQL
      UPDATE archetypes
      SET primary_fingerprint = (
            SELECT fingerprint FROM cards WHERE cards.id = archetypes.primary_card_id
          ),
          secondary_fingerprint = COALESCE(
            (SELECT fingerprint FROM cards WHERE cards.id = archetypes.secondary_card_id), ''
          )
    SQL

    reject_unfingerprinted!
    reject_duplicates!

    change_column_null :archetypes, :primary_fingerprint, false
    remove_index :archetypes, name: "index_archetypes_on_card_pair"
    add_index :archetypes, [ :primary_fingerprint, :secondary_fingerprint ],
      unique: true, name: "index_archetypes_on_fingerprint_pair"
  end

  def down
    remove_index :archetypes, name: "index_archetypes_on_fingerprint_pair"
    add_index :archetypes, [ :primary_card_id, :secondary_card_id ],
      unique: true, name: "index_archetypes_on_card_pair"
    remove_column :archetypes, :secondary_fingerprint
    remove_column :archetypes, :primary_fingerprint
  end

  # Public so a test can exercise it: once the unique index below exists, a
  # duplicate pair is impossible to create, and there is no other way to run the
  # query that is supposed to find one.
  def duplicate_pairs
    select_all(<<~SQL).to_a
      SELECT GROUP_CONCAT(id) AS ids, GROUP_CONCAT(name, ' / ') AS names
      FROM archetypes
      GROUP BY primary_fingerprint, secondary_fingerprint
      HAVING COUNT(*) > 1
    SQL
  end

  private

  def reject_unfingerprinted!
    orphans = select_all(<<~SQL).to_a
      SELECT id, name FROM archetypes
      WHERE primary_fingerprint IS NULL OR primary_fingerprint = ''
    SQL
    return if orphans.empty?

    raise "#{orphans.size} archetype(s) point at a card with no fingerprint and cannot be " \
          "keyed on one — #{orphans.map { |row| "##{row['id']} #{row['name']}" }.join(', ')}. " \
          "Re-scrape those cards from the admin panel first (Cards → Rescrape), which is what " \
          "computes a fingerprint."
  end

  def reject_duplicates!
    duplicates = duplicate_pairs
    return if duplicates.empty?

    listed = duplicates.map { |row| "  #{row['ids']} — #{row['names']}" }.join("\n")
    raise "#{duplicates.size} archetype fingerprint pair(s) are duplicated, so the unique index " \
          "cannot be added:\n#{listed}\n" \
          "Merge them by hand first. This migration will not pick one to delete: decks and " \
          "deck_results point at these rows, so dropping one would silently move somebody's data."
  end
end
```

- [ ] **Step 6: Add the model's sync callback and validation**

`app/models/archetype.rb` — replace the id-pair validation and add the callback. Put both just after `validates :name, presence: true`:

```ruby
  validates :name, presence: true
  # These two are denormalised copies of the member cards' fingerprints, and they
  # back the unique index — identity is the fingerprint pair, not the card-id
  # pair, so designating another printing of the same card is the same archetype.
  # The presence check turns "this card has never been scraped" into a readable
  # error instead of a NOT NULL violation.
  validates :primary_fingerprint, presence: true
  validates :primary_fingerprint, uniqueness: { scope: :secondary_fingerprint }

  before_validation :sync_fingerprints
  before_validation :auto_generate_name, unless: :custom_name?
```

and, in the private section:

```ruby
  # A missing secondary is the empty string, never nil: SQLite treats NULLs as
  # distinct, so a nil would let the pair index accept duplicate single-member
  # archetypes. Nothing *decides* anything from these columns — detection joins
  # `cards` and reads the live fingerprint — so drift after a re-scrape is
  # harmless, and Archetypes::FingerprintSync is what brings them back in step.
  def sync_fingerprints
    self.primary_fingerprint = primary_card&.fingerprint
    self.secondary_fingerprint = secondary_card&.fingerprint.to_s
  end
```

Note the ordering: `sync_fingerprints` must run **before** the uniqueness validation, which `before_validation` guarantees.

- [ ] **Step 7: Run the model tests**

Run: `bin/rails db:migrate && bin/rails test test/models/archetype_test.rb`
Expected: PASS.

- [ ] **Step 8: Write the failing test for the resync service**

Create `test/services/archetypes/fingerprint_sync_test.rb`:

```ruby
require "test_helper"

class Archetypes::FingerprintSyncTest < ActiveSupport::TestCase
  test "rewrites a pair the member cards have drifted away from" do
    archetype = archetypes(:ogerpon)
    # update_column, not update!: this is precisely the drift a `force: true`
    # rescrape produces — the card moves, the archetype's copy does not.
    cards(:teal_mask_ogerpon_ex).update_column(:fingerprint, "ogerpon_v2")

    result = Archetypes::FingerprintSync.call

    assert_equal "ogerpon_v2", archetype.reload.primary_fingerprint
    assert_equal 1, result.updated
    assert_empty result.collisions
  end

  test "leaves a pair already in step alone" do
    result = Archetypes::FingerprintSync.call

    assert_equal 0, result.updated
  end

  test "reports the archetypes that drift has made duplicates instead of writing them" do
    # budew_ogerpon's primary moves onto ogerpon's fingerprint, so once resynced
    # both archetypes would claim (ogerpon_shared, ""). Neither may be written.
    archetypes(:budew_ogerpon).update_columns(secondary_card_id: nil, secondary_fingerprint: "")
    cards(:budew_pre).update_column(:fingerprint, "ogerpon_shared")

    result = Archetypes::FingerprintSync.call

    assert_equal 0, result.updated
    assert_equal [ archetypes(:budew_ogerpon), archetypes(:ogerpon) ].sort_by(&:id),
      result.collisions.sort_by(&:id)
    assert_equal "budew_shared", archetypes(:budew_ogerpon).reload.primary_fingerprint,
      "a colliding row must be reported, not written"
  end
end
```

- [ ] **Step 9: Run it to verify it fails**

Run: `bin/rails test test/services/archetypes/fingerprint_sync_test.rb`
Expected: FAIL with `uninitialized constant Archetypes::FingerprintSync`.

- [ ] **Step 10: Write the service**

Create `app/services/archetypes/fingerprint_sync.rb`:

```ruby
# Recomputes the denormalised fingerprint columns on `archetypes` from the cards
# they point at, and reports the pairs that collide once refreshed.
#
# Those columns exist only to back the unique index — detection reads
# `cards.fingerprint` through a join, never this copy — so drift is tolerable and
# this is a repair tool, not a callback on Card. A `force: true` rescrape that
# corrects an attack moves that card's fingerprint; a Card callback would then
# have to fail a whole set rescrape halfway through to keep the index honest.
# Running this afterwards brings the columns back in step instead, and names any
# duplicate the drift has let through rather than picking one to overwrite.
class Archetypes::FingerprintSync < ApplicationService
  Result = Struct.new(:updated, :collisions, keyword_init: true)

  def call
    desired = Archetype.includes(:primary_card, :secondary_card).map { |archetype|
      [ archetype, archetype.primary_card&.fingerprint, archetype.secondary_card&.fingerprint.to_s ]
    }

    collisions = colliding(desired)
    updated = desired.reject { |(archetype, _, _)| collisions.include?(archetype) }
      .count { |(archetype, primary, secondary)| write(archetype, primary, secondary) }

    Result.new(updated: updated, collisions: collisions)
  end

  private

  # Archetypes whose *refreshed* pair would not be unique. Grouped on the target
  # values rather than the stored ones: the whole point is to catch a collision
  # before writing it, since the index would only raise on the second write and
  # leave the first one applied.
  def colliding(desired)
    duplicated = desired.group_by { |(_, primary, secondary)| [ primary, secondary ] }
      .select { |_, rows| rows.size > 1 }
      .keys

    desired.select { |(_, primary, secondary)| duplicated.include?([ primary, secondary ]) }
      .map(&:first)
  end

  # update_columns skips validations and callbacks on purpose: the values are
  # already derived from the live cards, and re-running auto_generate_name here
  # would rename archetypes as a side effect of a repair.
  #
  # Known limitation: two archetypes swapping pairs can still raise
  # ActiveRecord::RecordNotUnique here, because the first write transiently
  # collides with the other's not-yet-updated row. Re-running resolves it, and a
  # raise is the right failure mode — loud, and nothing was lost.
  def write(archetype, primary, secondary)
    return false if [ archetype.primary_fingerprint, archetype.secondary_fingerprint ] == [ primary, secondary ]

    archetype.update_columns(primary_fingerprint: primary, secondary_fingerprint: secondary)
    true
  end
end
```

- [ ] **Step 11: Add the rake task**

Create `lib/tasks/archetypes.rake`:

```ruby
namespace :archetypes do
  desc "Recompute the denormalised fingerprint pair on every archetype and report collisions"
  task resync_fingerprints: :environment do
    result = Archetypes::FingerprintSync.call

    puts "Resynced #{result.updated} archetype(s)."

    if result.collisions.any?
      puts "\n#{result.collisions.size} archetype(s) would collide once resynced and were left alone:"
      result.collisions.each { |a| puts "  ##{a.id} #{a.name} (#{a.primary_card&.name})" }
      puts "\nMerge them by hand — decks and deck results point at these rows."
      exit 1
    end
  end
end
```

- [ ] **Step 12: Write the failing test for the migration's duplicate detection**

This one belongs in `test/models/archetype_test.rb`, not with the service: it is about the schema, not about the resync. Append:

```ruby
  # The migration refuses to add the index when a duplicate pair exists, and names
  # the offenders rather than deleting one — decks and deck_results point at these
  # rows. Once the index is in place a duplicate cannot be created, so the only way
  # to exercise the query is to drop the index for the length of this test. The
  # suite's transactional fixtures roll the DDL back.
  test "the migration's duplicate detection names the offenders" do
    require Rails.root.join("db/migrate/#{migration_filename('add_fingerprints_to_archetypes')}")

    connection = ActiveRecord::Base.connection
    connection.remove_index :archetypes, name: "index_archetypes_on_fingerprint_pair"
    Archetype.insert_all([
      { name: "Clone A", name_normalized: "clone a", primary_card_id: cards(:doublade).id,
        primary_fingerprint: "clone_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current },
      { name: "Clone B", name_normalized: "clone b", primary_card_id: cards(:doublade).id,
        primary_fingerprint: "clone_fp", secondary_fingerprint: "",
        created_at: Time.current, updated_at: Time.current }
    ])

    duplicates = AddFingerprintsToArchetypes.new.duplicate_pairs

    assert_equal 1, duplicates.size
    assert_match "Clone A / Clone B", duplicates.first["names"]
  end

  private

  def migration_filename(suffix)
    Dir.children(Rails.root.join("db/migrate")).find { |f| f.end_with?("_#{suffix}.rb") } ||
      raise("no migration ending in _#{suffix}.rb")
  end
```

- [ ] **Step 13: Run the tests**

Run: `bin/rails test test/models/archetype_test.rb test/services/archetypes/fingerprint_sync_test.rb`
Expected: PASS.

- [ ] **Step 14: Run the full suite**

Run: `bin/rails test && bin/rubocop && bin/brakeman --no-pager`
Expected: PASS. The fixture fingerprints added in Step 1 are the likeliest source of a surprise — `test/services/cards/printings_test.rb`, `test/services/decks/comparator_test.rb` and `test/services/collections/owned_equivalents_test.rb` all reason about fingerprint equality, so read any failure there as "this fixture's new sentinel collides with another's", not as a bug in this task.

- [ ] **Step 15: Commit**

```bash
git add -A
git commit -m "Key archetype identity on the fingerprint pair, in the database

(primary_card_id, secondary_card_id) is UNIQUE but SQLite treats NULLs as
distinct, so two single-member archetypes on the same card have always
been accepted — only the model validation stopped them. Identity is really
the fingerprint pair, so the index moves onto denormalised copies, with
the empty string standing in for a missing secondary so the pair is always
comparable.

The columns back the index and nothing else: detection joins cards and
reads the live fingerprint, which is what makes drift after a re-scrape
harmless and lets a resync task, rather than a Card callback, keep them
in step."
```

---

### Task 3: Split detection into matching and suggestion

`Decks::ArchetypeDetector` conflates two jobs under one name, and the false-positive risk is not the same on each side.

**Matching** — is there an existing archetype for this deck? Its members were chosen by a human, so containment is a safe question: a false positive can only come from a badly defined archetype, which is a data problem. It becomes type-agnostic, fingerprint-keyed, and fed **every** card in the deck.

**Suggestion** — which cards should pre-fill a "create archetype" form? Unchanged and still Pokémon-only. Ranking Trainers by copy count would propose Iono, Professor's Research and Ultra Ball on every deck ever imported.

**Files:**
- Modify: `app/services/decks/archetype_detector.rb`, `app/controllers/api/decks_controller.rb`, `app/javascript/controllers/archetype_picker_controller.js`
- Test: `test/services/decks/archetype_detector_test.rb`, `test/controllers/api/decks_controller_test.rb`

**Interfaces:**
- Consumes: `Archetype#primary_card` / `#secondary_card` (Task 1), `Card#fingerprint`, fixture fingerprints (Task 2).
- Produces: `Decks::ArchetypeDetector::Result` with members `archetype`, `suggested_primary`, `suggested_secondary` and `#matched?`. `Api::DecksController#suggested_archetype` answers `{ matched: false, suggested_primary: {…}, suggested_secondary: {…} }`.

- [ ] **Step 1: Write the failing tests**

Replace `test/services/decks/archetype_detector_test.rb` entirely:

```ruby
require "test_helper"

class Decks::ArchetypeDetectorTest < ActiveSupport::TestCase
  setup do
    @deck = decks(:one)
    @deck.deck_cards.destroy_all
  end

  # --- Suggestion (Pokémon only, unchanged) ---

  test "returns a blank result for a deck holding nothing an archetype names" do
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_not result.matched?
    assert_nil result.suggested_primary
  end

  test "suggests the deck's own Pokémon when no archetype matches" do
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_not result.matched?
    assert_equal cards(:doublade), result.suggested_primary
  end

  # Ranking Trainers by copy count would propose Iono and Ultra Ball on every deck
  # ever imported, so suggestion stays Pokémon-only even though matching no longer is.
  test "never suggests a Trainer, however many copies the deck plays" do
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)
    @deck.deck_cards.create!(card: cards(:doublade), quantity: 1)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal cards(:doublade), result.suggested_primary
    assert_nil result.suggested_secondary
  end

  # --- Matching (any card type, keyed on fingerprints) ---

  test "matches an existing single-member archetype" do
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)
    @deck.deck_cards.create!(card: cards(:trainer_card), quantity: 4)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert result.matched?
    assert_equal archetypes(:ogerpon), result.archetype
  end

  # The printing an archetype names is a display reference: identity is the
  # fingerprint, so a deck playing another printing of the same card still matches.
  test "matches a deck holding a different printing of the archetype's card" do
    reprint = cards(:froakie_cri)
    reprint.update_column(:fingerprint, "ogerpon_shared")
    @deck.deck_cards.create!(card: reprint, quantity: 2)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal archetypes(:ogerpon), result.archetype
  end

  test "matches a Trainer-led archetype" do
    trainer_archetype = Archetype.create!(primary_card: cards(:bosss_orders_meg), name: "Boss Box")
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal trainer_archetype, result.archetype
  end

  test "prefers a two-member archetype over a single-member one" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal archetypes(:budew_ogerpon), result.archetype
  end

  # A Trainer identifies a deck far less than a Pokémon does, so an archetype
  # named after one can only win when nothing better matches at all.
  test "a Pokémon archetype outranks a Trainer one on the same deck" do
    Archetype.create!(primary_card: cards(:bosss_orders_meg), name: "Boss Box")
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)
    @deck.deck_cards.create!(card: cards(:teal_mask_ogerpon_ex), quantity: 2)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_equal archetypes(:ogerpon), result.archetype
  end

  test "does not match a two-member archetype whose secondary is missing" do
    @deck.deck_cards.create!(card: cards(:budew_pre), quantity: 1)

    result = Decks::ArchetypeDetector.call(@deck.reload)

    assert_not result.matched?
    assert_equal cards(:budew_pre), result.suggested_primary
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `bin/rails test test/services/decks/archetype_detector_test.rb`
Expected: FAIL — `NoMethodError: undefined method 'suggested_primary'`, and the Trainer-led match returns nil.

- [ ] **Step 3: Rewrite the detector**

Replace `app/services/decks/archetype_detector.rb` entirely:

```ruby
# Infers the Archetype of a deck, and — separately — suggests what a new one
# should be built from. Those are two jobs with different false-positive risks,
# so they answer different questions from different inputs:
#
#   * Matching asks whether an existing Archetype's member cards are all in this
#     deck. Those members were chosen by a human, so containment is safe to ask
#     of the whole card pool, whatever the type. A false positive can only come
#     from a badly defined archetype, which is a data problem.
#   * Suggestion ranks the deck's own notable *Pokémon* to pre-fill a "create
#     archetype" form. Ranking Trainers by copies played would propose Iono,
#     Professor's Research and Ultra Ball on every deck ever imported, so it
#     stays Pokémon-only. A Trainer-led archetype is created by hand; once it
#     exists, matching finds it on its own.
#
# Returns a Result responding to #archetype, #suggested_primary and #suggested_secondary.
class Decks::ArchetypeDetector < ApplicationService
  Result = Struct.new(:archetype, :suggested_primary, :suggested_secondary, keyword_init: true) do
    def matched? = archetype.present?
  end

  # How much a member identifies a deck. The sum is the archetype's score, so
  # Gardevoir ex / Munkidori scores 6, Gardevoir ex alone 3, Lost Zone Box
  # (Comfey / Colress's Experiment) 3, and an ill-advised "Iono" archetype 1 —
  # it can only win when nothing else matches at all.
  RULE_BOX_WEIGHT = 3
  POKEMON_WEIGHT = 2
  OTHER_WEIGHT = 1

  def initialize(deck)
    @deck = deck
  end

  def call
    primary, secondary = notable_pokemon.first(2)

    Result.new(
      archetype: match_existing,
      suggested_primary: primary,
      suggested_secondary: secondary
    )
  end

  private

  # Distinct Pokémon cards, most representative first. Suggestion only.
  def notable_pokemon
    pokemon = @deck.deck_cards.select { |dc| dc.card&.card_type == "Pokémon" }

    pokemon
      .sort_by { |dc| [ dc.card.pokemon_subtype&.rule_box ? 0 : 1, -dc.card.hp.to_i, -dc.quantity ] }
      .map(&:card)
      .uniq(&:name)
  end

  # Every card in the deck, keyed on Card#fingerprint — the "same card, any
  # printing" key. Strictly more correct than the name matching it replaces,
  # which conflated unrelated cards that happen to share one.
  def deck_fingerprints
    @deck.deck_cards.filter_map { |dc| dc.card&.fingerprint }.uniq
  end

  # `preload` rather than `includes`: the WHERE clause already references `cards`
  # through the join on the primary, and letting Rails pick eager_load would make
  # it alias that same table twice for the two associations. preload always issues
  # separate queries, so there is nothing to alias.
  def match_existing
    fingerprints = deck_fingerprints
    return nil if fingerprints.empty?

    Archetype
      .joins(:primary_card)
      .where(cards: { fingerprint: fingerprints })
      .preload(primary_card: :pokemon_subtype, secondary_card: :pokemon_subtype)
      .map { |archetype| [ archetype, score(archetype, fingerprints) ] }
      .select { |(_, score)| score.positive? }
      .max_by { |(archetype, score)| [ score, member_count(archetype) ] }
      &.first
  end

  # Zero disqualifies. A secondary absent from the deck rules the archetype out
  # entirely rather than costing it points: it names a pairing the deck is not playing.
  def score(archetype, fingerprints)
    members = [ archetype.primary_card, archetype.secondary_card ].compact
    return 0 unless members.all? { |card| fingerprints.include?(card.fingerprint) }

    members.sum { |card| weight(card) }
  end

  def weight(card)
    return OTHER_WEIGHT unless card.card_type == "Pokémon"

    card.pokemon_subtype&.rule_box ? RULE_BOX_WEIGHT : POKEMON_WEIGHT
  end

  # Breaks a tie on the score — a Pokémon + Trainer pair and a lone rule-box
  # Pokémon both score 3, and the richer description should win, which is what
  # the old two-beats-one rule meant.
  def member_count(archetype)
    archetype.secondary_card_id ? 2 : 1
  end
end
```

- [ ] **Step 4: Run the detector tests**

Run: `bin/rails test test/services/decks/archetype_detector_test.rb`
Expected: PASS.

- [ ] **Step 5: Follow the Result rename to its two call sites**

`app/controllers/api/decks_controller.rb`, in `suggested_archetype` — `detection.primary` / `detection.secondary` become the suggested names, and the JSON keys follow so the payload does not read as if all three describe the match:

```ruby
      if detection.matched?
        render json: { matched: true, archetype: archetype_json(detection.archetype) }
      elsif detection.suggested_primary
        render json: {
          matched: false,
          suggested_primary: pokemon_json(detection.suggested_primary),
          suggested_secondary: pokemon_json(detection.suggested_secondary)
        }
      else
        render json: { matched: false }
      end
```

`app/services/decks/fetcher.rb` uses only `detection.matched?` and `detection.archetype` — no change.

`app/javascript/controllers/archetype_picker_controller.js:72-73`:

```js
    } else if (data.suggested_primary) {
      this.#prefillCreate(data.suggested_primary, data.suggested_secondary)
    }
```

`test/controllers/api/decks_controller_test.rb:56` asserts on the old key:

```ruby
    assert_equal cards(:budew_pre).id, json["suggested_primary"]["id"]
```

- [ ] **Step 6: Run the full suite**

Run: `bin/rails test && bin/rubocop`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Match archetypes on fingerprints, of any card type

The detector conflated two jobs whose false-positive risks differ.
Matching now asks whether an existing archetype's members are all in the
deck — a question about human-chosen cards, safe to ask of the whole pool
— and is keyed on Card#fingerprint rather than on name, which conflated
unrelated cards sharing one. A weighted score keeps a Trainer-led
archetype from outranking a rule-box Pokémon.

Suggestion is unchanged and still Pokémon-only: ranking Trainers by
copies played would propose Ultra Ball on every deck ever imported.
Result#primary/#secondary become #suggested_primary/#suggested_secondary,
since only #archetype describes the match."
```

---

### Task 4: The archetype API accepts any card and looks up by fingerprint

`Api::ArchetypesController#create` currently does `find_or_initialize_by(primary_card:, secondary_card:)`. That lookup is by card id. Since identity is now the fingerprint pair, picking a different printing of the same card looks like a new archetype, goes to `save!`, and is refused by the unique index — a 500 where the user merely re-designated a card they own.

**Files:**
- Modify: `app/controllers/api/archetypes_controller.rb`, `app/controllers/api/decks_controller.rb`
- Test: `test/controllers/api/archetypes_controller_test.rb` (new)

**Interfaces:**
- Consumes: `Archetype#primary_fingerprint` / `#secondary_fingerprint` (Task 2).
- Produces: `POST /api/archetypes` accepting `primary_card_id` / `secondary_card_id` of any card type. Both API controllers' `archetype_json` answers `{ id, name, primary_card: { id, name, set_name, set_number } | null, secondary_card: …, parent_id }`.

- [ ] **Step 1: Write the failing test**

Create `test/controllers/api/archetypes_controller_test.rb`:

```ruby
require "test_helper"

class Api::ArchetypesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in @user
  end

  test "creates an archetype from a Trainer" do
    assert_difference "Archetype.count", 1 do
      post api_archetypes_path, params: { primary_card_id: cards(:bosss_orders_meg).id }, as: :json
    end

    assert_response :created
    json = JSON.parse(response.body)
    assert_equal "Boss's Orders", json["name"]
    assert_equal "MEG", json["primary_card"]["set_name"]
    assert_nil json["secondary_card"]
  end

  # Identity is the fingerprint pair, so this is the same archetype the fixture
  # already holds. Looking up by card id would miss it, go to save!, and be
  # refused by the unique index — a 500 for what is a no-op.
  test "returns the existing archetype when given another printing of the same card" do
    reprint = cards(:froakie_cri)
    reprint.update_column(:fingerprint, "ogerpon_shared")

    assert_no_difference "Archetype.count" do
      post api_archetypes_path, params: { primary_card_id: reprint.id }, as: :json
    end

    assert_response :created
    assert_equal archetypes(:ogerpon).id, JSON.parse(response.body)["id"]
  end

  test "answers 422 for a card that has never been scraped into a fingerprint" do
    post api_archetypes_path, params: { primary_card_id: cards(:trainer_card).id }, as: :json

    assert_response :unprocessable_entity
    assert_includes JSON.parse(response.body)["errors"].join, "Primary fingerprint"
  end

  test "answers 404 for an unknown card" do
    post api_archetypes_path, params: { primary_card_id: 0 }, as: :json

    assert_response :not_found
  end

  test "the index returns each member's printing, not a bare name" do
    get api_archetypes_path, params: { q: "Ogerpon" }

    assert_response :success
    entry = JSON.parse(response.body).find { |a| a["id"] == archetypes(:ogerpon).id }
    assert_equal "TWM", entry["primary_card"]["set_name"]
    assert_equal "25", entry["primary_card"]["set_number"]
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `bin/rails test test/controllers/api/archetypes_controller_test.rb`
Expected: FAIL — the Trainer create answers 404, because `create` scopes the lookup to `card_type: "Pokémon"`.

- [ ] **Step 3: Rewrite the controller**

Replace `app/controllers/api/archetypes_controller.rb`:

```ruby
module Api
  class ArchetypesController < ApplicationController
    before_action :authenticate_user!

    def index
      q = params[:q].to_s.strip
      archetypes = if q.present?
        Archetype.search(q).includes(:primary_card, :secondary_card).limit(10)
      else
        Archetype.includes(:primary_card, :secondary_card).order(:name).limit(10)
      end

      render json: archetypes.map { |a| archetype_json(a) }
    end

    def create
      primary = Card.find(params[:primary_card_id])
      secondary = params[:secondary_card_id].present? ? Card.find(params[:secondary_card_id]) : nil

      archetype = existing(primary, secondary) || build(primary, secondary)
      archetype.save! if archetype.new_record?

      render json: archetype_json(archetype), status: :created
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Card not found" }, status: :not_found
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_entity
    end

    private

    # Identity is the fingerprint pair, not the pair of card ids: designating a
    # different printing of the same card is the same archetype. Looking up by id
    # would miss it, go to save!, and be refused by the unique index — a 500 for
    # what the user experiences as a no-op.
    def existing(primary, secondary)
      return nil if primary.fingerprint.blank?

      Archetype.find_by(
        primary_fingerprint: primary.fingerprint,
        secondary_fingerprint: secondary&.fingerprint.to_s
      )
    end

    def build(primary, secondary)
      Archetype.new(primary_card: primary, secondary_card: secondary, parent_id: params[:parent_id])
    end

    def archetype_json(a)
      {
        id: a.id,
        name: a.name,
        primary_card: card_json(a.primary_card),
        secondary_card: card_json(a.secondary_card),
        parent_id: a.parent_id
      }
    end

    # The printing, not a bare name: several cards share a name, and which one an
    # archetype designates is now the user's choice to make and to see.
    def card_json(card)
      return nil if card.nil?

      { id: card.id, name: card.name, set_name: card.set_name, set_number: card.set_number }
    end
  end
end
```

Note `existing` returns nil for a fingerprint-less card, so the flow falls through to `build` and the model's `primary_fingerprint` presence validation produces the readable 422.

- [ ] **Step 4: Match the shape in the decks API**

`app/controllers/api/decks_controller.rb` — `archetype_json` must answer the same shape, since `archetype_picker_controller.js` renders results from both endpoints:

```ruby
    def archetype_json(archetype)
      {
        id: archetype.id,
        name: archetype.name,
        primary_card: card_json(archetype.primary_card),
        secondary_card: card_json(archetype.secondary_card)
      }
    end
```

`pokemon_json` is renamed to `card_json` and gains the printing:

```ruby
    def card_json(card)
      return nil if card.nil?

      { id: card.id, name: card.name, set_name: card.set_name, set_number: card.set_number }
    end
```

`pokemon_json` has four callers in that file — the two in `archetype_json` above and the two in `suggested_archetype` (Task 3 Step 5 left them named `pokemon_json`). All four become `card_json`; after the edit, `grep -n pokemon_json app/controllers/api/decks_controller.rb` must return nothing.

- [ ] **Step 5: Run the tests**

Run: `bin/rails test test/controllers/api/ && bin/rubocop`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "Let the archetype API designate any card, keyed on its fingerprint

find_or_initialize_by looked archetypes up by card id, so picking a
different printing of the same card looked like a new archetype, went to
save!, and was refused by the unique index — a 500 where the user merely
re-designated a card they own. The lookup moves to the fingerprint pair.

The Pokémon scope on both find calls is gone, and the JSON now carries
each member's set and number: several cards share a name, and which
printing an archetype designates is the user's choice to see."
```

---

### Task 5: The autocomplete searches cards, and stops collapsing printings

`Ui::PokemonSelect` hardcodes `type=Pokémon` in three Stimulus controllers, and each of them deduplicates results by name. That dedup is now actively wrong: if the user cannot see the printings, they cannot designate one — which is the whole feature.

The spec proposed an optional `type:` filter on the renamed component. **This plan drops it (YAGNI):** all three call sites are archetype pickers, all three now want every type, and the parameter would ship with zero users. It is a one-line addition if a typed picker ever appears.

**Files:**
- Create: `app/views/components/ui/card_select.rb`, `app/javascript/controllers/card_select_controller.js`
- Delete: `app/views/components/ui/pokemon_select.rb`, `app/javascript/controllers/pokemon_select_controller.js`
- Modify: `app/javascript/controllers/{archetype_picker,result_modal}_controller.js`, `app/views/components/admin/archetypes/form.rb`, `app/views/components/decks/{archetype_field,result_modal}.rb`

**Interfaces:**
- Consumes: `GET /api/cards?q=…` (already type-optional), the `card_json` shape from Task 4.
- Produces: `Ui::CardSelect` with the same keyword arguments as `Ui::PokemonSelect` minus the Pokémon wording; Stimulus identifier `card-select` with targets `input`, `hiddenField`, `results`.

- [ ] **Step 1: Rename the component**

```bash
git mv app/views/components/ui/pokemon_select.rb app/views/components/ui/card_select.rb
git mv app/javascript/controllers/pokemon_select_controller.js app/javascript/controllers/card_select_controller.js
```

In `app/views/components/ui/card_select.rb`, rename the class and every `pokemon_select` occurrence to `card_select` / `card-select`, and reword the docstring. The three constants and the two defaults become:

```ruby
module Ui
  # Renders a card autocomplete group: a visible text input, an optional hidden ID
  # field, and a results dropdown — all wrapped in a `Ui::FormGroup`.
  #
  # Searches every card type. Its only users are the archetype pickers, and an
  # archetype may designate a Pokémon, a Trainer or an Energy.
  #
  # ## Standalone mode (own `card-select` Stimulus controller)
  #
  # Pass `hidden_field_name:` to render a plain hidden input owned by the
  # `card-select` controller. Use when there is no parent form builder.
  #
  #   render Ui::CardSelect.new(
  #     label: "Primary card",
  #     hidden_field_name: "archetype[primary_card_id]",
  #     current_value: @archetype.primary_card&.name
  #   )
  #
  # ## Embedded mode (parent Stimulus controller provides targets)
  #
  # Omit `hidden_field_name:`. Supply explicit `data:` hashes for each element.
  # Optionally yield a block to render a custom hidden field (e.g. from a form builder).
  #
  #   render Ui::CardSelect.new(
  #     label: "Primary card",
  #     hidden_data: { result_modal_target: "primaryId" },
  #     input_data:  { result_modal_target: "primaryInput",
  #                    action: "input->result-modal#searchPrimary" },
  #     results_data: { result_modal_target: "primaryResults" }
  #   )
  #
  # ## Form-builder hidden field (block form)
  #
  #   render Ui::CardSelect.new(
  #     label: "Primary card",
  #     current_value: card&.name,
  #     input_data:  { card_select_target: "input",
  #                    action: "input->card-select#search" },
  #     results_data: { card_select_target: "results" },
  #     wrapper_data: { controller: "card-select" }
  #   ) do
  #     f.hidden_field :primary_card_id, data: { card_select_target: "hiddenField" }
  #   end
  class CardSelect < ApplicationComponent
    STANDALONE_INPUT_DATA = { card_select_target: "input", action: "input->card-select#search" }.freeze
    STANDALONE_RESULTS_DATA = { card_select_target: "results" }.freeze
    STANDALONE_HIDDEN_DATA = { card_select_target: "hiddenField" }.freeze
```

and the placeholder default plus the standalone fallback:

```ruby
      placeholder: "Search cards...",
```

```ruby
      return { controller: "card-select" } if standalone?
```

- [ ] **Step 2: Rewrite the standalone Stimulus controller**

`app/javascript/controllers/card_select_controller.js` — change the identifier in the rendered action, drop the type filter, drop the dedup, reword the empty state:

```js
  async #fetchResults(query) {
    const response = await fetch(`/api/cards?q=${encodeURIComponent(query)}`, {
      credentials: "same-origin"
    })

    if (!response.ok) return
    // No deduplication by name: which printing an archetype designates is the
    // user's choice, and collapsing them would hide every option but the first.
    this.#renderResults(await response.json())
  }

  #renderResults(cards) {
    if (cards.length === 0) {
      this.resultsTarget.innerHTML = '<div class="archetype-search-empty">No cards found</div>'
      return
    }

    this.resultsTarget.innerHTML = cards.map(card => `
      <div class="archetype-search-item"
           data-action="click->card-select#select"
           data-card-id="${card.id}"
           data-card-name="${this.#escape(card.name)}">
        <strong>${this.#escape(card.name)}</strong>
        <span class="archetype-search-pokemon">${this.#escape(card.set_name)} ${this.#escape(card.set_number)}</span>
      </div>
    `).join("")
  }
```

- [ ] **Step 3: Do the same in the two embedded controllers**

In `app/javascript/controllers/archetype_picker_controller.js`, replace the body of `#searchCard` (renamed from `#searchPokemon`) — the URL loses `&type=Pokémon` and the `seen`/`unique` block goes:

```js
  #searchCard(inputTarget, resultsTarget, prefix) {
    clearTimeout(this[`${prefix}Timeout`])
    const query = inputTarget.value.trim()

    if (query.length < 2) {
      resultsTarget.innerHTML = ""
      return
    }

    this[`${prefix}Timeout`] = setTimeout(async () => {
      const response = await fetch(`/api/cards?q=${encodeURIComponent(query)}`, {
        credentials: "same-origin"
      })
      if (!response.ok) return
      // Every type, and every printing: an archetype may designate a Trainer, and
      // which printing it designates is the user's choice to see.
      const cards = await response.json()

      const action = prefix === "primary" ? "selectPrimary" : "selectSecondary"
      resultsTarget.innerHTML = cards.map(card => `
        <div class="archetype-search-item"
             data-action="click->archetype-picker#${action}"
             data-card-id="${card.id}"
             data-card-name="${this.#escape(card.name)}">
          <strong>${this.#escape(card.name)}</strong>
          <span class="archetype-search-pokemon">${this.#escape(card.set_name)} ${this.#escape(card.set_number)}</span>
        </div>
      `).join("")
    }, 300)
  }
```

Update its two callers, `searchPrimary` and `searchSecondary`, to call `#searchCard`.

Apply the same change to `app/javascript/controllers/result_modal_controller.js`, keeping its own action-name interpolation:

```js
      resultsTarget.innerHTML = cards.map(card => `
        <div class="archetype-search-item"
             data-action="click->result-modal#select${prefix === 'primary' ? 'Primary' : 'Secondary'}"
             data-card-id="${card.id}"
             data-card-name="${this.#escape(card.name)}">
          <strong>${this.#escape(card.name)}</strong>
          <span class="archetype-search-pokemon">${this.#escape(card.set_name)} ${this.#escape(card.set_number)}</span>
        </div>
      `).join("")
```

- [ ] **Step 4: Update the three call sites**

`app/views/components/admin/archetypes/form.rb` — rename the helper and its labels:

```ruby
          card_autocomplete(f, :primary_card_id, "Primary card", @archetype.primary_card)
          card_autocomplete(f, :secondary_card_id, "Secondary card (optional)", @archetype.secondary_card)
```

```ruby
      def card_autocomplete(f, field, label_text, current_card)
        render Ui::CardSelect.new(
          label: label_text,
          current_value: current_card&.name,
          wrapper_data: { controller: "card-select" },
          input_data:   { card_select_target: "input", action: "input->card-select#search" },
          results_data: { card_select_target: "results" }
        ) do
          f.hidden_field field, data: { card_select_target: "hiddenField" }
        end
      end
```

and the name field's placeholder on line 14: `placeholder: "Auto-generated from card names"`.

`app/views/components/decks/archetype_field.rb:51-52,61` and `app/views/components/decks/result_modal.rb:53-54,60` — rename `pokemon_search_group` to `card_search_group`, its labels to `"Primary card"` / `"Secondary card (optional)"`, and `Ui::PokemonSelect` to `Ui::CardSelect`. Neither passes `input_data` targets named after the component, so nothing else changes there.

- [ ] **Step 5: Check nothing still names the old component**

Run:

```bash
grep -rn "PokemonSelect\|pokemon_select\|pokemon-select\|type=Pokémon" app/ test/
```

Expected: no output.

- [ ] **Step 6: Run the suite**

Run: `bin/rails test && bin/rails test:system && SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system && bin/rubocop && bin/importmap audit`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "Search every card type in the archetype picker, printings included

Ui::PokemonSelect becomes Ui::CardSelect: an archetype may designate a
Trainer or an Energy, so the hardcoded type filter goes. The dedup by
name goes with it — it was harmless while identity was a name, and is
actively wrong now that the user picks a printing, since it hid every
option but the first.

The spec's optional type: parameter is deliberately not implemented: all
three call sites are archetype pickers and all three want every type, so
it would ship with no users."
```

---

### Task 6: End-to-end coverage and documentation

**Files:**
- Create: `test/system/archetype_any_card_test.rb`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything above.
- Produces: nothing other tasks depend on.

- [ ] **Step 1: Write the system test**

The badge fallback and the empty type stripe already work — `Decks::ClassificationBadges#archetype_badge` falls back to `badge-archetype` when `primary_energy_type` is nil, and `Decks::DeckCard#type_stripe` renders nothing on an empty type list. This test is what proves a Trainer-led archetype actually reaches them.

Create `test/system/archetype_any_card_test.rb`:

```ruby
require "application_system_test_case"

class ArchetypeAnyCardTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    login_as @user, scope: :user
    @deck = @user.decks.create!(name: "Boss Box", physical: true)
    @deck.deck_cards.create!(card: cards(:bosss_orders_meg), quantity: 4)
  end

  # A Trainer-led archetype has no energy type, so its badge falls back to the
  # neutral style rather than a typed one. That fallback already existed; what is
  # new is that an archetype can reach it at all.
  test "a Trainer-led archetype renders with the neutral badge" do
    archetype = Archetype.create!(primary_card: cards(:bosss_orders_meg), name: "Boss Box")
    @deck.update!(archetype: archetype)

    visit deck_path(@deck)

    assert_selector ".badge.badge-archetype", text: "Boss Box"
    assert_no_selector ".badge.badge-energy", text: "Boss Box"
  end

  test "the deck's archetype picker offers a Trainer and shows its printing" do
    visit edit_deck_path(@deck)
    click_button "Suggest" if page.has_button?("Suggest")

    find("[data-archetype-picker-target='input']").fill_in with: "Boss"
    find(".archetype-create-item", text: "Create new archetype").click

    within(".create-archetype-section") do
      find("[data-archetype-picker-target='primaryInput']").fill_in with: "Boss's Orders"
      assert_selector ".archetype-search-item", text: "MEG 114"
      find(".archetype-search-item", text: "MEG 114").click
      click_button "Create & select"
    end

    assert_field(with: "Boss's Orders")
  end
end
```

- [ ] **Step 2: Run it on both sides of the breakpoint**

Run: `bin/rails test test/system/archetype_any_card_test.rb`
Then: `SYSTEM_TEST_VIEWPORT=mobile bin/rails test test/system/archetype_any_card_test.rb`
Expected: PASS on both. Every system test must pass on both sides — if the mobile run fails on a nav click, use `click_nav_link` rather than clicking the link directly.

- [ ] **Step 3: Sabotage-verify the two system assertions**

A system test that only clicks and asserts can pass with a modal open over the page. Prove each assertion can go red before trusting it:

1. Temporarily change `Decks::ClassificationBadges#archetype_badge` to always take the typed branch (`slug = "grass"`). Run the first test — expect FAIL on `.badge.badge-archetype`. Revert.
2. Temporarily restore the dedup-by-name in `archetype_picker_controller.js#searchCard`. Run the second test — expect FAIL, since only one Boss's Orders printing would render and the "MEG 114" row would be the PAL one. Revert.

- [ ] **Step 4: Update CLAUDE.md**

Three edits.

In **Architecture → Key services**, replace the `Decks::ArchetypeDetector` bullet:

```markdown
- `Decks::ArchetypeDetector` — two jobs behind one name, deliberately separated. *Matching* asks whether an existing `Archetype`'s member cards are all in the deck: its members were chosen by a human, so containment is safe to ask of the **whole** card pool of **any** type, and it is keyed on `Card#fingerprint` (the "same card, any printing" key) rather than on name, which conflated unrelated cards sharing one. A weighted score — rule-box Pokémon 3, other Pokémon 2, Trainer/Energy 1, summed, ties broken by member count — keeps an ill-advised "Iono" archetype from winning unless nothing else matches; a secondary absent from the deck disqualifies outright. *Suggestion* is unchanged and stays **Pokémon-only**: ranking Trainers by copies played would propose Ultra Ball on every deck ever imported, so a Trainer-led archetype is created by hand and matching finds it afterwards. The `Result` names this split: `archetype` describes the match, `suggested_primary`/`suggested_secondary` only the notable Pokémon.
- `Archetypes::FingerprintSync` — recomputes `archetypes.primary_fingerprint`/`secondary_fingerprint` from the cards they point at and **reports** the pairs that would collide rather than writing one of them (`bin/rails archetypes:resync_fingerprints`). It is a repair tool, not a callback: a `force: true` rescrape moves a card's fingerprint, and a `Card` callback would have to fail a whole set rescrape halfway through to keep the index honest.
```

In **Models**, after the Card paragraph, add:

```markdown
**Archetype identity is a fingerprint pair, not a card pair.** `primary_card_id`/`secondary_card_id` say which printing to *display*; `(primary_fingerprint, secondary_fingerprint)` is UNIQUE and says which archetype it *is* — two archetypes built from two printings of the same cards are duplicates, not siblings. A missing secondary is the **empty string, never NULL**: the previous `(primary_pokemon_id, secondary_pokemon_id)` index looked unique but SQLite treats NULLs as distinct, so duplicate single-member archetypes got through it for as long as it existed. Members may be **any** `card_type`, which is what lets a Trainer engine (Lost Zone Box, Mill/Stall) be an archetype at all. The denormalised columns back the index and **nothing else** — detection joins `cards` and reads the live fingerprint — which is what makes drift after a re-scrape harmless and lets `Archetypes::FingerprintSync` repair it out of band. `Archetype.search` spells its second join alias by hand (`secondary_cards_archetypes`), derived from the association name, so renaming that association breaks the scope at *query* time, not at load time.
```

In **Frontend**, after the design-system paragraph, add:

```markdown
`Ui::CardSelect` (Stimulus `card-select`) is the card autocomplete behind all three archetype pickers — the admin form, the deck archetype field and the deck result modal. It searches **every** card type and never deduplicates results by name: which printing an archetype designates is the user's choice, so collapsing them would hide every option but the first.
```

- [ ] **Step 5: Run everything one last time**

Run: `bin/rails test && bin/rails test:system && SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system && bin/rubocop && bin/brakeman --no-pager && bin/importmap audit`
Expected: PASS on all five.

- [ ] **Step 6: Commit and open the PR**

```bash
git add -A
git commit -m "Cover the Trainer-led archetype end to end, and document the split

The neutral badge fallback and the empty type stripe already existed; what
is new is that an archetype can reach them. Both system assertions are
sabotage-verified — the badge one against a forced typed branch, the
picker one against the dedup this work removed."
git push -u origin feat/120-archetype-exact-card
gh pr create --title "Archetypes designate an exact card, of any type" --body "Closes #120"
```

---

## Self-Review

**Spec coverage**

| Spec section | Task |
|---|---|
| Renaming, `search` alias trap | 1 |
| Denormalised fingerprints, empty-string sentinel, DB uniqueness | 2 |
| Backfill + duplicate detection that names rather than deletes | 2 |
| Resync task (drift tolerance) | 2 |
| Matching: type-agnostic, fingerprint-keyed, whole deck | 3 |
| Weighted scoring, tie-break, disqualifying secondary | 3 |
| Suggestion unchanged, Pokémon-only | 3 |
| `Result` renamed to `suggested_*` | 3 |
| `Api::ArchetypesController#create` keyed on fingerprints | 4 |
| Pokémon scope dropped, params renamed, JSON carries the printing | 4 |
| `Ui::PokemonSelect` → `Ui::CardSelect`, JS shows set/number | 5 |
| Badge fallback / empty stripe verified, not built | 6 |
| Every "Testing" bullet in the spec | 1-6 |

**Deviations from the spec, both deliberate:**

1. **No `type:` parameter on `Ui::CardSelect`** (Task 5). All three call sites want every type, so the parameter would ship with no users. YAGNI; one line to add later.
2. **The name-dedup removal is new work the spec did not name** (Task 5). It follows from the spec's decision that the printing is the user's to choose: a dedup by name makes every printing but the first unreachable.

**One spec item made explicit here:** `decks_controller.rb`'s deck-list filters (`primary_filter_options` / `secondary_filter_options`, and the two `where(archetypes: …)` clauses) also carry the old column names. The spec's "the rest is mechanical" did not enumerate them; Task 1 Step 5 does.

**Interfaces cross-check:** `primary_card` / `secondary_card` (Task 1) are used unchanged in Tasks 2-6. `Result#suggested_primary` / `#suggested_secondary` (Task 3) are consumed only by `Api::DecksController#suggested_archetype` and `archetype_picker_controller.js#suggest`, both updated in Task 3 Step 5. `card_json` is the name used in both API controllers after Task 4. `Archetypes::FingerprintSync::Result` members `updated` / `collisions` match between Task 2's service, its test, and the rake task.
