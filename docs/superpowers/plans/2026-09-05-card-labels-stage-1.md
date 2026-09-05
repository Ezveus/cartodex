# Card labels, stage 1: the store and the `type` family — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give Cartodex one store for card labels, fill its `type` family from Limitless's `is:`
search, and show ACE SPEC on the deck report — closing #154 and laying the table #155's roles will
live in.

**Architecture:** Two tables. `card_labels` is the vocabulary (`slug`, `family`, `position`, and
for a `type` label the `is:` token it is imported by); `card_label_assignments` maps a label to a
`cards.fingerprint`, keeping the printing it was decided from beside it and recording its
provenance. One service reads a whole label from Limitless in a single request, one writes it
without ever deleting, one job runs the pair against an `Import` row. The deck report joins the
assignments in one extra query and renders a type label as a badge on the card's name line — no
new section, no card moved out of its category.

**Tech Stack:** Rails 8.1, Ruby 3.4.1, SQLite, Minitest + fixtures, Nokogiri, Phlex components,
Solid Queue.

**Spec:** `docs/superpowers/specs/2026-09-05-card-labels-and-roles-design.md`

## Global Constraints

- **Stage 1 only.** The `role` family — `CardLabel::ROLES`, `CardLabels::RoleSuggester`, the
  curation screen, the report's `?group=role` mode — is stage 2 and must not appear here. The
  `family` column accepts `"role"` from the start; nothing writes one.
- **Two families, two governances.** `Admin::CardLabelsController` refuses `create` and `destroy`
  for `family: "role"`. Stage 1 seeds one `type` row, `ace-spec`.
- **Assignments are keyed on `fingerprint`.** `card_id` is kept beside it as the printing the
  decision came from, and is nullable. A card with no fingerprint is never labelled.
- **Provenance decides overwrites.** `source` ∈ `imported` / `suggested` / `curated`. The importer
  writes `imported` rows and **never** modifies a row it did not create.
- **The import never deletes and never scrapes a card.** Assignments the source no longer lists
  are reported; printings the catalogue does not hold are counted.
- **One request per label**: `GET https://limitlesstcg.com/cards?q=<token>&show=all`. No
  pagination. The announced count in `.search-summary` is an integrity check.
- Comments explain **why**, in the register of the surrounding code. English code, English
  comments, English docs.
- `bin/rubocop` on the files written (never repo-wide — `mise` resolves Ruby 4.0.1 here and
  reports ~159 pre-existing offences CI does not), `bin/brakeman --no-pager`, and the system suite
  at **both** viewports (`bin/rails test:system` and `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`).
- Every new test is **sabotage-verified**: break the implementation, watch that test go red, restore.

---

### Task 0: Measure what the existing suite would not catch

The spec makes this a step, not an intention: two blockers in #153 survived a fully green suite,
and the §9.4 reflex is to write down what stays green *before* writing code.

**Files:**
- Create: `tmp/155-ce-qui-ne-rougirait-pas.md` (unversioned handoff, French — the repo convention)

**Interfaces:**
- Consumes: nothing.
- Produces: a written list the later tasks' tests answer. No code.

- [ ] **Step 1: Prove the first entry, which is already suspected**

`Archetypes::CardStats::CATEGORIES` is a partition today — every card sits in exactly one — and
nothing asserts it. Sabotage `category_of` so that a Trainer is returned under two keys (make
`categories` duplicate the `:item` group into `:other`), then run:

```bash
bin/rails test test/services/archetypes/card_stats_test.rb test/controllers/archetypes_controller_test.rb
```

Record whether anything went red. Restore the file.

- [ ] **Step 2: Answer the same question for the four decisions this stage makes**

For each, find the test that would catch it or record that none exists:

1. an assignment written against a card with a NULL fingerprint;
2. an importer that *updates* an existing assignment instead of leaving it alone;
3. an importer that deletes assignments the source no longer lists;
4. an admin who creates a `family: "role"` label through the CRUD.

- [ ] **Step 3: Write the file and stop**

`tmp/155-ce-qui-ne-rougirait-pas.md` lists each item as *couvert par …* or *rien ne rougirait*.
Every "rien ne rougirait" line must be matched by a test in Tasks 1–8; the file is the checklist
Task 9 verifies against. Nothing is committed (the directory is unversioned).

---

### Task 1: The two tables and their models

**Files:**
- Create: `db/migrate/<timestamp>_create_card_labels.rb`
- Create: `app/models/card_label.rb`
- Create: `app/models/card_label_assignment.rb`
- Test: `test/models/card_label_test.rb`
- Test: `test/models/card_label_assignment_test.rb`

**Interfaces:**
- Consumes: `Card` (its `fingerprint` and `id`).
- Produces: `CardLabel` with `FAMILIES = %w[role type]`, scopes `.roles` / `.types`, `#role?`,
  `#type?`, `has_many :assignments`; `CardLabelAssignment` with `SOURCES = %w[imported suggested
  curated]`, `belongs_to :card_label`, `belongs_to :card, optional: true`, scope `.active`.

**No fixtures for either table.** Every other test in the suite would inherit them, and the report
tests in Task 8 assert what a card's badges are — a fixture label would make those assertions true
for reasons the test does not state. Records are built in the tests that need them.

- [ ] **Step 1: Write the failing model tests**

`test/models/card_label_test.rb`:

```ruby
require "test_helper"

class CardLabelTest < ActiveSupport::TestCase
  test "a slug is unique across families" do
    CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    duplicate = CardLabel.new(slug: "ace-spec", name: "Ace Spec", family: "role", position: 10)

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:slug], "has already been taken"
  end

  test "a family outside the vocabulary is refused" do
    label = CardLabel.new(slug: "gust", name: "Gust", family: "mechanic", position: 10)

    assert_not label.valid?
    assert_includes label.errors[:family], "is not included in the list"
  end

  # The slug reaches a URL query and a DOM class, and it is what stage 2's rules will key on.
  test "a slug that is not lowercase-kebab is refused" do
    assert_not CardLabel.new(slug: "ACE SPEC", name: "x", family: "type", position: 1).valid?
  end

  test "the family scopes order by position then slug" do
    b = CardLabel.create!(slug: "b", name: "B", family: "type", position: 20)
    a = CardLabel.create!(slug: "a", name: "A", family: "type", position: 10)
    CardLabel.create!(slug: "c", name: "C", family: "role", position: 5)

    assert_equal [ a, b ], CardLabel.types.to_a
    assert_equal [ "c" ], CardLabel.roles.pluck(:slug)
  end

  test "destroying a label takes its assignments with it" do
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    label.assignments.create!(fingerprint: "fp", source: "imported")

    assert_difference "CardLabelAssignment.count", -1 do
      label.destroy
    end
  end
end
```

`test/models/card_label_assignment_test.rb`:

```ruby
require "test_helper"

class CardLabelAssignmentTest < ActiveSupport::TestCase
  setup do
    @label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
  end

  # The fingerprint is the identity. A blank one would be a row the report can never join to and
  # that the UNIQUE key would let through once per label.
  test "a blank fingerprint is refused" do
    assert_not @label.assignments.new(fingerprint: "", source: "imported").valid?
    assert_not @label.assignments.new(fingerprint: nil, source: "imported").valid?
  end

  test "one decision per label and fingerprint" do
    @label.assignments.create!(fingerprint: "fp", source: "imported")
    second = @label.assignments.new(fingerprint: "fp", source: "curated")

    assert_not second.valid?
    assert_raises(ActiveRecord::RecordNotUnique) do
      second.save(validate: false)
    end
  end

  test "a source outside the vocabulary is refused" do
    assert_not @label.assignments.new(fingerprint: "fp", source: "guessed").valid?
  end

  # `active` is what every reader of this table uses: a rejected row is a human saying no, and it
  # must survive rather than being deleted, or the next suggestion run proposes it again.
  test "active excludes rejected rows" do
    kept = @label.assignments.create!(fingerprint: "kept", source: "curated")
    @label.assignments.create!(fingerprint: "refused", source: "curated", rejected: true)

    assert_equal [ kept ], @label.assignments.active.to_a
  end

  # The card is the printing the decision came from, not the decision itself: deleting it from the
  # admin panel must not delete what a human decided about the card it was a printing of.
  test "deleting the card leaves the assignment standing" do
    card = cards(:honedge)
    assignment = @label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")

    card.destroy

    assert_nil assignment.reload.card_id
    assert_equal "honedge_fp", assignment.fingerprint
  end
end
```

- [ ] **Step 2: Run them and watch them fail**

```bash
bin/rails test test/models/card_label_test.rb test/models/card_label_assignment_test.rb
```

Expected: `NameError: uninitialized constant CardLabel`.

- [ ] **Step 3: Write the migration**

`db/migrate/<timestamp>_create_card_labels.rb`:

```ruby
# One store for what a card is beyond its card_type, and — from stage 2 — for what it does.
#
# The vocabulary is a table rather than a constant because half of it moves: Ancient and Future
# arrived mid-block in Scarlet & Violet, ACE SPEC was revived from Black & White in the middle of
# the same block, and Limitless's own `is:` documentation is already incomplete (is:ancient,
# is:future and is:tera all answer and none is listed). A closed list in code is a deploy per set.
class CreateCardLabels < ActiveRecord::Migration[8.1]
  def change
    create_table :card_labels do |t|
      t.string :slug, null: false
      t.string :name, null: false
      t.string :family, null: false
      t.integer :position, null: false, default: 0
      t.text :description
      # The Limitless search token a `type` label is imported by ("is:ace"). Nullable: a `role`
      # label has none, and a curated `type` label need not have one either.
      t.string :source_query
      t.timestamps
    end
    add_index :card_labels, :slug, unique: true
    add_index :card_labels, [ :family, :position ]

    create_table :card_label_assignments do |t|
      # index: false — the composite UNIQUE below leads with this column and serves every lookup
      # a plain index would.
      t.references :card_label, null: false, foreign_key: true, index: false
      # The identity: "same card, any printing", the key Archetypes::CardStats already groups on.
      t.string :fingerprint, null: false
      # The printing the decision was made from — Archetype's primary_card_id / primary_fingerprint
      # pair, for the same reason: it is what makes a fingerprint drift repairable out of band
      # rather than silent.
      t.references :card, foreign_key: true
      t.string :source, null: false
      # A human saying no. Deleting the row instead would have the next suggestion run propose it
      # again, forever.
      t.boolean :rejected, null: false, default: false
      t.timestamps
    end
    add_index :card_label_assignments, [ :card_label_id, :fingerprint ], unique: true
    add_index :card_label_assignments, :fingerprint
  end
end
```

- [ ] **Step 4: Write the models**

`app/models/card_label.rb`:

```ruby
# The label vocabulary: what a card *is* beyond its card_type ("type"), and — from stage 2 — what
# it *does* ("role").
#
# The two families are governed differently on purpose. A `role` slug is referenced by code, since
# stage 2's suggestion rules are keyed on it, so an admin-invented role would be a label no rule
# can ever propose; a `type` slug is referenced by nothing but its own `source_query`, so a new one
# is a row plus a run. Admin::CardLabelsController is where that asymmetry is enforced.
class CardLabel < ApplicationRecord
  FAMILIES = %w[role type].freeze

  has_many :assignments, class_name: "CardLabelAssignment", dependent: :destroy

  # Lowercase kebab, because the slug reaches a URL query and a DOM class, and stage 2's rules key
  # on it.
  validates :slug, presence: true, uniqueness: true, format: {
    with: /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
    message: "must be lowercase words joined by dashes"
  }
  validates :name, presence: true
  validates :family, inclusion: { in: FAMILIES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :roles, -> { where(family: "role").order(:position, :slug) }
  scope :types, -> { where(family: "type").order(:position, :slug) }

  def role? = family == "role"
  def type? = family == "type"

  # Only a label that says where to read it can be imported. The admin screen offers the action on
  # exactly these.
  def importable? = source_query.present?
end
```

`app/models/card_label_assignment.rb`:

```ruby
# One label on one card — where "one card" is a fingerprint, not a printing: what a card is and
# what it does are properties of the card, and every printing of Prime Catcher is an ACE SPEC.
#
# `source` is what decides who may overwrite whom. The importer writes `imported` rows and touches
# nothing else; stage 2's suggester rewrites only its own `suggested` rows; a `curated` row is a
# human decision and is never overwritten by anything automatic. A `curated` row with `rejected`
# set is that human saying no, kept rather than deleted so the next run does not undo the refusal.
class CardLabelAssignment < ApplicationRecord
  SOURCES = %w[imported suggested curated].freeze

  belongs_to :card_label
  # The printing the decision came from. Optional, and nullified rather than cascaded: deleting a
  # printing from the admin panel must not delete what was decided about the card.
  belongs_to :card, optional: true

  validates :fingerprint, presence: true
  validates :source, inclusion: { in: SOURCES }
  # The UNIQUE index is the guarantee; this exists for the readable error — the same division of
  # labour as (set_name, set_number) on Card.
  validates :card_label_id, uniqueness: { scope: :fingerprint }

  scope :active, -> { where(rejected: false) }
  scope :imported, -> { where(source: "imported") }
end
```

Add `dependent: :nullify` for the printing on the `Card` side — `app/models/card.rb`, beside the
other `has_many`s:

```ruby
  # The printing a label decision was made from. Nullified, never cascaded: see
  # CardLabelAssignment.
  has_many :card_label_assignments, dependent: :nullify
```

- [ ] **Step 5: Migrate and run the tests**

```bash
bin/rails db:migrate
bin/rails test test/models/card_label_test.rb test/models/card_label_assignment_test.rb
```

Expected: PASS, and `db/schema.rb` updated.

- [ ] **Step 6: Sabotage-verify**

Drop `validates :fingerprint, presence: true` → the blank-fingerprint test goes red. Change
`dependent: :nullify` to `:destroy` on `Card` → the "deleting the card leaves the assignment
standing" test goes red. Restore both.

- [ ] **Step 7: Commit**

```bash
git add db/migrate db/schema.rb app/models test/models
git commit -m "Store card labels as a vocabulary plus fingerprint-keyed assignments"
```

---

### Task 2: Seed the `ace-spec` label

**Files:**
- Create: `db/seeds/card_labels.rb`
- Modify: `db/seeds.rb` (beside the two existing `load` lines)
- Test: `test/models/card_label_seed_test.rb`

**Interfaces:**
- Consumes: `CardLabel` from Task 1.
- Produces: a `card_labels` row `slug: "ace-spec"`, `family: "type"`, `source_query: "is:ace"`,
  present on every boot. Task 6's admin screen and Task 5's job both assume it exists in
  production without a manual step.

- [ ] **Step 1: Write the failing test**

`test/models/card_label_seed_test.rb`:

```ruby
require "test_helper"

# The seed is a bootstrap, not the source of truth — bin/docker-entrypoint runs db:seed on every
# boot, so a seed that reasserted its values would revert an admin's correction on each deploy.
# That is the rule db/seeds/standard_pools.rb already follows, and this test is what holds it.
class CardLabelSeedTest < ActiveSupport::TestCase
  def load_seed = load Rails.root.join("db/seeds/card_labels.rb")

  test "it creates the ace-spec label with the token it is imported by" do
    assert_difference "CardLabel.count", 1 do
      load_seed
    end

    label = CardLabel.find_by(slug: "ace-spec")

    assert_equal "type", label.family
    assert_equal "is:ace", label.source_query
  end

  test "running it twice creates nothing and rewrites nothing" do
    load_seed
    CardLabel.find_by(slug: "ace-spec").update!(name: "Ace Spec (corrected)", source_query: "is:ace-spec")

    assert_no_difference "CardLabel.count" do
      load_seed
    end

    label = CardLabel.find_by(slug: "ace-spec")

    assert_equal "Ace Spec (corrected)", label.name
    assert_equal "is:ace-spec", label.source_query
  end
end
```

- [ ] **Step 2: Run it and watch it fail**

```bash
bin/rails test test/models/card_label_seed_test.rb
```

Expected: FAIL — `LoadError`, no such file.

- [ ] **Step 3: Write the seed**

`db/seeds/card_labels.rb`:

```ruby
# A bootstrap, not the source of truth. bin/docker-entrypoint runs db:seed before the server
# accepts traffic on every deploy, and labels are maintained from the admin panel — so this file
# adds a slug it does not find and never rewrites one it does, exactly like
# db/seeds/standard_pools.rb. Reasserting the values here would silently revert an admin's
# correction on the next deploy.
#
# Stage 2 grows a second loop over CardLabel::ROLES for the `role` family.
TYPE_LABELS = [
  {
    slug: "ace-spec",
    name: "ACE SPEC",
    position: 10,
    source_query: "is:ace",
    description: "A deck may hold at most one. Nothing in a scraped card page says so — the flag " \
                 "comes from Limitless's card search, which is the only source that carries it."
  }
].freeze

TYPE_LABELS.each do |attributes|
  next if CardLabel.exists?(slug: attributes[:slug])

  CardLabel.create!(family: "type", **attributes)
  puts "Created card label #{attributes[:slug]}"
end
```

- [ ] **Step 4: Wire it into `db/seeds.rb`**

```ruby
load Rails.root.join("db/seeds/card_labels.rb")
```

placed after the `standard_pools` line.

- [ ] **Step 5: Run the test and the seed**

```bash
bin/rails test test/models/card_label_seed_test.rb
bin/rails db:seed
```

Expected: PASS, and the seed prints `Created card label ace-spec` once and nothing the second time.

- [ ] **Step 6: Sabotage-verify**

Replace `next if CardLabel.exists?(...)` with an unconditional
`CardLabel.find_or_initialize_by(slug:).update!(...)` → the "rewrites nothing" test goes red.
Restore.

- [ ] **Step 7: Commit**

```bash
git add db/seeds.rb db/seeds/card_labels.rb test/models/card_label_seed_test.rb
git commit -m "Seed the ACE SPEC label as a bootstrap that never overwrites"
```

---

### Task 3: `CardLabels::LimitlessSearch` — read a whole label in one request

**Files:**
- Create: `app/services/card_labels/limitless_search.rb`
- Create: `test/fixtures/files/limitless_card_search.html`
- Test: `test/services/card_labels/limitless_search_test.rb`

**Interfaces:**
- Consumes: `HttpFetcher.call(url)`.
- Produces: `CardLabels::LimitlessSearch.call("is:ace") -> Result(printings:, announced_count:)`
  where `printings` is an Array of `Printing(set_code:, number:)` and `Result#complete?` compares
  the two. Raises `CardLabels::LimitlessSearch::ParseError`. Task 4 consumes exactly this.

- [ ] **Step 1: Write the HTML fixture**

`test/fixtures/files/limitless_card_search.html` — the real page's shape, trimmed to five links
and an announced count that deliberately **disagrees** with them, so one test can prove the
integrity check:

```html
<!DOCTYPE html>
<html><body>
  <div class="search-summary">
    7 cards found where
    <span class="search-key">card</span> is
    <span class="search-values">ACE SPEC</span>.
  </div>
  <section>
    <div class="card-search-grid">
      <a href="/cards/PRE/116"><img class="card shadow" src="https://example.test/PRE_116.png"></a>
      <a href="/cards/PRE/117"><img class="card shadow" src="https://example.test/PRE_117.png"></a>
      <a href="/cards/TEF/157"><img class="card shadow" src="https://example.test/TEF_157.png"></a>
      <a href="/cards/SVI/SV107"><img class="card shadow" src="https://example.test/SVI_SV107.png"></a>
      <a href="/cards/PRE/116"><img class="card shadow" src="https://example.test/PRE_116.png"></a>
    </div>
  </section>
  <a href="/cards/syntax">Search syntax</a>
</body></html>
```

The trailing `/cards/syntax` link and the repeated `PRE/116` are both deliberate: the first proves
the href pattern is matched rather than "any link under /cards", the second proves the result is
de-duplicated.

- [ ] **Step 2: Write the failing test**

`test/services/card_labels/limitless_search_test.rb`:

```ruby
require "test_helper"

class CardLabels::LimitlessSearchTest < ActiveSupport::TestCase
  SEARCH_HTML = File.read(Rails.root.join("test/fixtures/files/limitless_card_search.html")).freeze

  setup do
    @original_http = HttpFetcher.method(:call)
    @urls = []
    stub_http(SEARCH_HTML)
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http)
  end

  # One request, not a page walk: `show=all` returns every match at once. Measured against the
  # live source — is:ace 46 of 46 in 25 KB, is:tera 151 of 151, is:ex 986 of 986 in 234 KB, a
  # quarter of the standings page HttpFetcher already reads inside its 30-second read timeout.
  test "reads the whole label in a single request" do
    result = CardLabels::LimitlessSearch.call("is:ace")

    assert_equal [ "https://limitlesstcg.com/cards?q=is%3Aace&show=all" ], @urls
    assert_equal [
      [ "PRE", "116" ], [ "PRE", "117" ], [ "TEF", "157" ], [ "SVI", "SV107" ]
    ], result.printings.map { |p| [ p.set_code, p.number ] }
  end

  # A set number is a String holding something like "SV107" as often as it holds a number, and it
  # is half of the (set_name, set_number) pair the importer looks a printing up by.
  test "keeps a non-numeric card number as written" do
    assert_includes CardLabels::LimitlessSearch.call("is:ace").printings.map(&:number), "SV107"
  end

  # The count the page states is the integrity check. A run that read four of an announced seven
  # has to be able to say so rather than implying the source lost three cards.
  test "reads the count the page announces and compares it" do
    result = CardLabels::LimitlessSearch.call("is:ace")

    assert_equal 7, result.announced_count
    assert_not result.complete?
  end

  test "a page with no card grid is a ParseError naming the URL" do
    stub_http("<html><body><p>Nothing here.</p></body></html>")

    error = assert_raises(CardLabels::LimitlessSearch::ParseError) do
      CardLabels::LimitlessSearch.call("is:ace")
    end

    assert_match "cards?q=is%3Aace", error.message
  end

  # The token is interpolated into a URL that is then fetched. HttpFetcher refuses a non-HTTP URI
  # as a backstop, but a backstop is not the caller saying what it will interpolate.
  test "a token that is not a search term is refused before any request" do
    assert_raises(ArgumentError) { CardLabels::LimitlessSearch.call("is:ace https://evil.test") }
    assert_empty @urls
  end

  private

  def stub_http(body)
    urls = @urls
    HttpFetcher.define_singleton_method(:call) do |url|
      urls << url
      body
    end
  end
end
```

- [ ] **Step 3: Run it and watch it fail**

```bash
bin/rails test test/services/card_labels/limitless_search_test.rb
```

Expected: `NameError: uninitialized constant CardLabels`.

- [ ] **Step 4: Write the service**

`app/services/card_labels/limitless_search.rb`:

```ruby
require "nokogiri"

# Read every printing carrying one Limitless search label, in one request.
#
# `limitlesstcg.com/cards?q=<token>&show=all` answers with the whole result set: measured on
# 2026-09-05, is:ace 46 links for an announced 46 in 25 KB, is:tera 151 for 151, and the largest
# plausible label, is:ex, 986 for 986 in 234 KB. So there is no pagination to write and no page cap
# to tune, and the count the page announces is free to be an integrity check rather than a
# stopping condition.
#
# It returns printings, not cards. Resolving them against the catalogue — and deciding what to do
# about the ones it does not hold — is CardLabels::Importer's job.
class CardLabels::LimitlessSearch < ApplicationService
  class ParseError < StandardError; end

  BASE_URL = "https://limitlesstcg.com".freeze

  # What a Limitless search token may contain. Narrow because it is interpolated into a URL that is
  # then fetched: `is:ace`, `is:fusion+aa`, `is:prism,tt`, `-is:gx`.
  TOKEN_RE = /\A-?[a-z]+:[a-z0-9,+\-]+\z/

  CARD_HREF_RE = %r{\A/cards/([A-Za-z0-9]+)/([A-Za-z0-9]+)\z}
  # "46 cards found where …" — and "1 card found" for a label with one printing.
  COUNT_RE = /\A\s*([\d,]+)\s+cards?\s+found/

  Printing = Struct.new(:set_code, :number, keyword_init: true)

  Result = Struct.new(:printings, :announced_count, keyword_init: true) do
    # False when the page said one thing and the grid held another. Not an error here: the caller
    # writes what it read and says so in the receipt, which is more useful than refusing a run
    # over a count it cannot check any other way.
    def complete? = announced_count.nil? || announced_count == printings.size
  end

  def initialize(token)
    @token = token.to_s
    return if @token.match?(TOKEN_RE)

    raise ArgumentError, "#{@token.inspect} is not a Limitless search token"
  end

  def call
    doc = Nokogiri::HTML(HttpFetcher.call(url))
    grid = doc.at_css(".card-search-grid")
    raise ParseError, "no card grid at #{url} — the page layout may have changed" if grid.nil?

    printings = grid.css("a[href]").filter_map { |link| printing_for(link["href"]) }.uniq
    raise ParseError, "no cards at #{url}" if printings.empty?

    Result.new(printings: printings, announced_count: announced_count(doc))
  end

  def url = "#{BASE_URL}/cards?#{{ q: @token, show: "all" }.to_query}"

  private

  # Matched against the whole href rather than searched for: the page carries other links under
  # /cards (the syntax page, the advanced search), and "any link starting with /cards" would read
  # them as printings.
  def printing_for(href)
    match = CARD_HREF_RE.match(href.to_s) or return nil

    Printing.new(set_code: match[1], number: match[2])
  end

  def announced_count(doc)
    summary = doc.at_css(".search-summary")&.text or return nil
    match = COUNT_RE.match(summary) or return nil

    match[1].delete(",").to_i
  end
end
```

- [ ] **Step 5: Run the tests**

```bash
bin/rails test test/services/card_labels/limitless_search_test.rb
```

Expected: PASS (5 tests).

- [ ] **Step 6: Verify against the live source once**

```bash
bin/rails runner 'r = CardLabels::LimitlessSearch.call("is:ace"); puts [ r.printings.size, r.announced_count, r.complete? ].inspect'
```

Expected: `[46, 46, true]`. If the shape has moved, fix the parser now rather than discovering it
from a failed admin run.

- [ ] **Step 7: Sabotage-verify**

Change `CARD_HREF_RE` to `%r{/cards/([A-Za-z0-9]+)/([A-Za-z0-9]+)}` (unanchored) → the fixture's
`/cards/syntax` link is still refused but `.uniq` no longer saves the duplicate, so relax it
further by dropping `.uniq` → the first test goes red. Drop `&show=all` from `url` → the first
test goes red. Restore.

- [ ] **Step 8: Commit**

```bash
git add app/services/card_labels test/services/card_labels test/fixtures/files/limitless_card_search.html
git commit -m "Read a Limitless card-search label in one request"
```

---

### Task 4: `CardLabels::Importer` — write what is held, report the rest

**Files:**
- Create: `app/services/card_labels/importer.rb`
- Test: `test/services/card_labels/importer_test.rb`

**Interfaces:**
- Consumes: `CardLabels::LimitlessSearch` (injectable as `search:` so the test needs no HTTP),
  `CardLabel`, `Card`, `CardLabelAssignment`.
- Produces: `CardLabels::Importer.call(label, search: CardLabels::LimitlessSearch) -> Result` with
  `created`, `already_present`, `missing_printings` (Array of `"SET NUMBER"`), `unfingerprinted`
  (Array of `"SET NUMBER"`), `unlisted_fingerprints` (Array of String), `announced_count`,
  `read_count`, and `#complete?`. Task 5 renders exactly these into the receipt.

- [ ] **Step 1: Write the failing test**

`test/services/card_labels/importer_test.rb`:

```ruby
require "test_helper"

class CardLabels::ImporterTest < ActiveSupport::TestCase
  Printing = CardLabels::LimitlessSearch::Printing
  SearchResult = CardLabels::LimitlessSearch::Result

  setup do
    @label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type",
                               position: 10, source_query: "is:ace")
    @honedge = cards(:honedge)
    @doublade = cards(:doublade)
  end

  test "it labels every printing the catalogue holds, keyed on the fingerprint" do
    result = import([ printing_for(@honedge), printing_for(@doublade) ])

    assert_equal 2, result.created
    assert_equal %w[doublade_fp honedge_fp].sort,
      @label.assignments.pluck(:fingerprint).sort
    assert_equal [ "imported" ], @label.assignments.pluck(:source).uniq
    assert_equal @honedge.id, @label.assignments.find_by(fingerprint: "honedge_fp").card_id
  end

  # A printing Limitless lists and the catalogue lacks is counted, never created: acquiring cards
  # is CardSets::Importer's job, and since #121 a known printing is never re-scraped.
  test "a printing the catalogue does not hold is counted, not created" do
    assert_no_difference "Card.count" do
      @result = import([ printing_for(@honedge), Printing.new(set_code: "ZZZ", number: "999") ])
    end

    assert_equal 1, @result.created
    assert_equal [ "ZZZ 999" ], @result.missing_printings
  end

  # A second run must be a no-op, not a rewrite: it is the ordinary way an admin picks up a set
  # that landed since the last one.
  test "a second run creates nothing and reports what was already there" do
    import([ printing_for(@honedge) ])

    assert_no_difference "CardLabelAssignment.count" do
      @result = import([ printing_for(@honedge) ])
    end

    assert_equal 0, @result.created
    assert_equal 1, @result.already_present
  end

  # The whole point of `source`. A human decision outranks the source, including a refusal.
  test "it never touches a curated decision" do
    @label.assignments.create!(fingerprint: "honedge_fp", source: "curated", rejected: true)

    result = import([ printing_for(@honedge) ])

    assignment = @label.assignments.find_by(fingerprint: "honedge_fp")

    assert_equal "curated", assignment.source
    assert assignment.rejected?
    assert_equal 0, result.created
  end

  # Reported, never deleted: a page truncated by a transport failure would otherwise depopulate a
  # label, and an admin would have no way to tell that from the source dropping a card.
  test "an assignment the source no longer lists is reported and kept" do
    import([ printing_for(@honedge), printing_for(@doublade) ])

    result = import([ printing_for(@honedge) ])

    assert_equal [ "doublade_fp" ], result.unlisted_fingerprints
    assert_equal 2, @label.assignments.count
  end

  # compute_fingerprint is a before_save, so only a callback-bypassing write produces this. The
  # report keys such a card under its own id and can never join it to a label, so labelling it
  # would write a row nothing can read.
  test "a card with no fingerprint is skipped and named" do
    @honedge.update_column(:fingerprint, nil)

    result = import([ printing_for(@honedge) ])

    assert_equal 0, result.created
    assert_equal [ "POR 56" ], result.unfingerprinted
  end

  # Two printings of one card are one card. Both are recorded as the source of the decision only
  # once, and nothing raises on the UNIQUE key.
  test "two printings sharing a fingerprint produce one assignment" do
    result = import([ printing_for(cards(:budew_pre)), printing_for(cards(:budew_asc)) ])

    assert_equal 1, result.created
    assert_equal [ "budew_shared" ], @label.assignments.pluck(:fingerprint)
  end

  test "it carries the counts the receipt needs" do
    result = import([ printing_for(@honedge) ], announced_count: 4)

    assert_equal 4, result.announced_count
    assert_equal 1, result.read_count
    assert_not result.complete?
  end

  private

  def printing_for(card) = Printing.new(set_code: card.set_name, number: card.set_number)

  def import(printings, announced_count: nil)
    search = Class.new do
      define_singleton_method(:call) do |_token|
        SearchResult.new(printings: printings, announced_count: announced_count || printings.size)
      end
    end

    CardLabels::Importer.call(@label, search: search)
  end
end
```

`budew_pre` and `budew_asc` are two printings of one card in `test/fixtures/cards.yml`, both
carrying `fingerprint: budew_shared` — verified, not assumed.

- [ ] **Step 2: Run it and watch it fail**

```bash
bin/rails test test/services/card_labels/importer_test.rb
```

Expected: `NameError: uninitialized constant CardLabels::Importer`.

- [ ] **Step 3: Write the service**

`app/services/card_labels/importer.rb`:

```ruby
# Write one label's assignments from what Limitless's card search lists.
#
# Three rules, and each is a refusal to do the obvious thing:
#
#   * it writes on the *fingerprint*, so a printing of an already-labelled card that arrives later
#     inherits the label with nothing re-run;
#   * it never modifies a row it did not create, so a curated decision — including a refusal —
#     outranks the source;
#   * it never deletes. An assignment the source no longer lists is reported, because a page
#     truncated by a transport failure is indistinguishable from a card the source dropped, and
#     only one of those two should depopulate a label.
#
# It never creates a Card either: a printing the catalogue does not hold is counted. Acquiring
# cards is CardSets::Importer's job, and since #121 a known printing is never re-scraped.
class CardLabels::Importer < ApplicationService
  Result = Struct.new(
    :created, :already_present, :missing_printings, :unfingerprinted,
    :unlisted_fingerprints, :announced_count, :read_count,
    keyword_init: true
  ) do
    def complete? = announced_count.nil? || announced_count == read_count
  end

  # `search:` is injected so a test can drive this without HTTP, and so stage 2 can point a role
  # importer at a different reader if one ever exists.
  def initialize(card_label, search: CardLabels::LimitlessSearch)
    @label = card_label
    @search = search
  end

  def call
    found = @search.call(@label.source_query)
    resolved = resolve(found.printings)

    serialized_transaction { write(resolved[:cards]) }

    Result.new(
      created: @created,
      already_present: @already_present,
      missing_printings: resolved[:missing],
      unfingerprinted: resolved[:unfingerprinted],
      unlisted_fingerprints: unlisted(resolved[:cards]),
      announced_count: found.announced_count,
      read_count: found.printings.size
    )
  end

  private

  # One query for the whole label rather than one per printing: is:ex is 986 of them.
  def resolve(printings)
    pairs = printings.map { |printing| [ printing.set_code, printing.number ] }
    cards = Card.where([ pairs.map { "(set_name = ? AND set_number = ?)" }.join(" OR "), *pairs.flatten ])
                .index_by { |card| [ card.set_name, card.set_number ] }

    missing = pairs.reject { |pair| cards.key?(pair) }.map { |set_code, number| "#{set_code} #{number}" }
    held = pairs.filter_map { |pair| cards[pair] }
    unfingerprinted = held.select { |card| card.fingerprint.blank? }

    {
      cards: held - unfingerprinted,
      missing: missing,
      unfingerprinted: unfingerprinted.map { |card| "#{card.set_name} #{card.set_number}" }
    }
  end

  # find_or_create_by! and not upsert: leaving an existing row exactly as it is *is* the rule, and
  # an upsert would quietly rewrite a curated decision back to "imported".
  def write(cards)
    @created = 0
    @already_present = 0

    cards.group_by(&:fingerprint).each do |fingerprint, printings|
      assignment = CardLabelAssignment.find_or_initialize_by(card_label: @label, fingerprint: fingerprint)

      if assignment.persisted?
        @already_present += 1
        next
      end

      assignment.update!(card: printings.first, source: "imported")
      @created += 1
    end
  end

  # Only rows this importer wrote: a curated assignment the source never listed is not a stray, it
  # is somebody's decision.
  def unlisted(cards)
    @label.assignments.imported.where.not(fingerprint: cards.map(&:fingerprint)).pluck(:fingerprint)
  end
end
```

- [ ] **Step 4: Run the tests**

```bash
bin/rails test test/services/card_labels/importer_test.rb
```

Expected: PASS (8 tests).

- [ ] **Step 5: Sabotage-verify the three rules**

1. Replace `find_or_initialize_by` + the `persisted?` guard with
   `CardLabelAssignment.upsert(...)` writing `source: "imported"` → "it never touches a curated
   decision" goes red.
2. Add `@label.assignments.imported.where.not(fingerprint: …).destroy_all` → "an assignment the
   source no longer lists is reported and kept" goes red.
3. Drop the `unfingerprinted` filter → "a card with no fingerprint is skipped and named" goes red.

Restore after each.

- [ ] **Step 6: Commit**

```bash
git add app/services/card_labels/importer.rb test/services/card_labels/importer_test.rb
git commit -m "Import a card label without ever overwriting a decision or deleting a row"
```

---

### Task 5: `CardLabels::ImportJob` and the new `Import` kind

**Files:**
- Create: `app/jobs/card_labels/import_job.rb`
- Modify: `app/models/import.rb` (`KINDS`, a scope)
- Modify: `app/controllers/admin/imports_controller.rb` (`UNRETRYABLE_REASONS`)
- Test: `test/jobs/card_labels/import_job_test.rb`

**Interfaces:**
- Consumes: `CardLabels::Importer` (Task 4), `Import`, `CardLabel`.
- Produces: `CardLabels::ImportJob.perform_later(import_id, card_label_id, user_id)`. On success
  the `Import` is `completed` with a receipt in `error_message`; on failure `failed` with the
  message. Task 6's controller enqueues exactly this.

- [ ] **Step 1: Write the failing test**

`test/jobs/card_labels/import_job_test.rb`:

```ruby
require "test_helper"

class CardLabels::ImportJobTest < ActiveJob::TestCase
  Printing = CardLabels::LimitlessSearch::Printing
  SearchResult = CardLabels::LimitlessSearch::Result

  setup do
    @user = users(:one)
    @label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type",
                               position: 10, source_query: "is:ace")
    @import = @user.imports.create!(kind: "card_labels", label: "ACE SPEC (is:ace)")
    @original_http = HttpFetcher.method(:call)
    HttpFetcher.define_singleton_method(:call) { |_url| raise "no HTTP in this test" }
  end

  teardown do
    HttpFetcher.define_singleton_method(:call, @original_http)
  end

  test "a finished run completes the import and says what it wrote" do
    stub_search([ Printing.new(set_code: "POR", number: "56") ])

    perform

    assert_equal "completed", @import.reload.status
    assert_match "1 card labelled", @import.error_message
  end

  # The receipt has to name every way a run can be partial, because none of them is a failure and
  # all of them change what the report will say.
  test "the receipt names the printings not held, the unlisted rows and a count mismatch" do
    CardLabelAssignment.create!(card_label: @label, fingerprint: "doublade_fp", source: "imported")
    stub_search([ Printing.new(set_code: "POR", number: "56"),
                  Printing.new(set_code: "ZZZ", number: "999") ], announced_count: 5)

    perform

    receipt = @import.reload.error_message

    assert_match "1 printing not in the catalogue", receipt
    assert_match "ZZZ 999", receipt
    assert_match "1 assignment the source no longer lists", receipt
    assert_match "read 2 of an announced 5", receipt
  end

  # Enqueued with ids for exactly this: handed the record, GlobalID raises before #perform is
  # entered and the rescue below never runs, leaving the Import at "pending" forever with no way
  # to clear it — Admin::ImportsController#retry refuses this kind.
  test "a label deleted while the run was queued fails the import instead of hanging it" do
    @label.destroy

    perform

    assert_equal "failed", @import.reload.status
    assert_match "no longer exists", @import.error_message
  end

  test "a fetch failure fails the import with the reason" do
    CardLabels::Importer.define_singleton_method(:call) do |_label, **_options|
      raise HttpFetcher::FetchError, "HTTP 429 for https://limitlesstcg.com/cards"
    end

    perform

    assert_equal "failed", @import.reload.status
    assert_match "HTTP 429", @import.error_message
  ensure
    CardLabels::Importer.singleton_class.remove_method(:call)
  end

  # The Import can be deleted from the admin panel while the run is in flight. That is an ordinary
  # lookup miss, not an error to report — there is nowhere left to report it.
  test "a deleted import ends the run quietly" do
    stub_search([ Printing.new(set_code: "POR", number: "56") ])
    @import.destroy

    assert_nothing_raised { perform }
  end

  private

  def perform = CardLabels::ImportJob.perform_now(@import.id, @label.id, @user.id)

  def stub_search(printings, announced_count: nil)
    result = SearchResult.new(printings: printings, announced_count: announced_count || printings.size)
    CardLabels::LimitlessSearch.define_singleton_method(:call) { |_token| result }
  end
end
```

Add a `teardown` restoring `CardLabels::LimitlessSearch.call` the way the HTTP stub is restored:
capture `CardLabels::LimitlessSearch.method(:call)` in `setup` and re-define it in `teardown`.

- [ ] **Step 2: Run it and watch it fail**

```bash
bin/rails test test/jobs/card_labels/import_job_test.rb
```

Expected: FAIL on `Import` validation — `"card_labels" is not included in the list`.

- [ ] **Step 3: Add the kind**

`app/models/import.rb`:

```ruby
  # "card_labels" is a run of Limitless's card search for one label's `is:` token. Like
  # "limitless_standings" it points at no tournament; unlike it, it leaves no receipt to undo,
  # because a re-run writes exactly the same rows and deletes nothing.
  KINDS = %w[deck card_set standing_list limitless_standings card_labels].freeze
```

and beside the other scopes:

```ruby
  scope :card_label_imports, -> { where(kind: "card_labels") }
```

`app/controllers/admin/imports_controller.rb`, in `UNRETRYABLE_REASONS`:

```ruby
      "card_labels" => "A card-label import cannot be retried: run it again from the label, which " \
                       "is where the search token lives.",
```

- [ ] **Step 4: Write the job**

`app/jobs/card_labels/import_job.rb`:

```ruby
# Run one admin "import this label from Limitless" against an Import row.
#
# Enqueued with ids rather than records, for the reason Tournaments::StandingListImportJob is: a
# label can be deleted from the admin panel while the run is queued, and a record handed to a job
# that no longer exists raises ActiveRecord::DeserializationError *before* #perform is entered,
# where the rescue below cannot see it — leaving the Import at "pending" forever, with
# Admin::ImportsController#retry refusing this kind and no other way to clear it.
class CardLabels::ImportJob < ApplicationJob
  class LabelDeleted < StandardError; end

  queue_as :default

  def perform(import_id, card_label_id, user_id)
    # An Import deleted mid-flight is an ordinary lookup miss: there is nowhere left to report to.
    import = Import.find_by(id: import_id) or return
    user = User.find_by(id: user_id)

    label = CardLabel.find_by(id: card_label_id)
    raise LabelDeleted, "That card label no longer exists." if label.nil?

    finish(import, user, CardLabels::Importer.call(label), label)
  rescue StandardError => e
    report_failure(import, user, e)
  end

  private

  def finish(import, user, result, label)
    import.update!(status: "completed", error_message: summarise(result))
    broadcast(user, "flash-notice", %(Import of "#{label.name}" finished: #{outcome(result)}.))
  end

  # Every clause is stated only when it applies: a run with nothing missing should not have to
  # explain a zero, and a run that quietly skipped half its cards must not read like one that had
  # nothing to skip.
  def outcome(result)
    parts = [ "#{result.created} #{"card".pluralize(result.created)} labelled" ]
    parts << "#{result.already_present} already labelled" if result.already_present.positive?
    parts << "#{result.missing_printings.size} not in the catalogue" if result.missing_printings.any?
    parts.join(", ")
  end

  def summarise(result)
    lines = [ outcome(result) ]
    lines << "read #{result.read_count} of an announced #{result.announced_count}" unless result.complete?
    if result.missing_printings.any?
      lines << "#{result.missing_printings.size} #{"printing".pluralize(result.missing_printings.size)} " \
               "not in the catalogue: #{result.missing_printings.join(", ")}"
    end
    if result.unfingerprinted.any?
      lines << "#{result.unfingerprinted.size} skipped for having no fingerprint: " \
               "#{result.unfingerprinted.join(", ")}"
    end
    if result.unlisted_fingerprints.any?
      lines << "#{result.unlisted_fingerprints.size} " \
               "#{"assignment".pluralize(result.unlisted_fingerprints.size)} the source no longer " \
               "lists, kept: #{result.unlisted_fingerprints.join(", ")}"
    end
    lines.join("\n")
  end

  def report_failure(import, user, error)
    return if import.nil?

    import.update!(status: "failed", error_message: error.message)
    broadcast(user, "flash-alert", %(Import of "#{import.label}" failed: #{error.message}))
  end

  def broadcast(user, css_class, message)
    return if user.nil?

    Turbo::StreamsChannel.broadcast_append_to(
      user, :notifications,
      target: "flash-messages",
      html: %(<div class="flash #{css_class}">#{ERB::Util.html_escape(message)}</div>)
    )
  end
end
```

- [ ] **Step 5: Run the tests**

```bash
bin/rails test test/jobs/card_labels/import_job_test.rb test/models/import_test.rb
```

Expected: PASS.

- [ ] **Step 6: Sabotage-verify**

Change `perform(import_id, card_label_id, user_id)` to take the records and enqueue them
(`perform_now(@import, @label, @user)` with a destroyed label) → the "deleted label" test goes red
in the way the comment describes. Drop the `unless result.complete?` line → the receipt test goes
red. Restore.

- [ ] **Step 7: Commit**

```bash
git add app/jobs/card_labels app/models/import.rb app/controllers/admin/imports_controller.rb test/jobs/card_labels
git commit -m "Run a card-label import as its own Import kind"
```

---

### Task 6: The admin screen

**Files:**
- Modify: `config/routes.rb` (inside `namespace :admin`)
- Create: `app/controllers/admin/card_labels_controller.rb`
- Create: `app/views/components/admin/card_labels/index_view.rb`
- Create: `app/views/components/admin/card_labels/form_view.rb`
- Test: `test/controllers/admin/card_labels_controller_test.rb`

**Interfaces:**
- Consumes: `CardLabel`, `CardLabels::ImportJob` (Task 5).
- Produces: `/admin/card_labels` (index, new, create, edit, update, destroy) and
  `POST /admin/card_labels/:id/import`. No Pundit call: `Admin::BaseController#require_admin!` is
  the gate for this namespace, and an `authorize` here would be the only one in the panel.

- [ ] **Step 1: Write the failing controller test**

`test/controllers/admin/card_labels_controller_test.rb`:

```ruby
require "test_helper"

class Admin::CardLabelsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    # There is no admin fixture: the panel's tests promote users(:one), which is what
    # Admin::StandardPoolsControllerTest does.
    @admin = users(:one)
    @admin.update!(admin: true)
    sign_in @admin
    @type_label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type",
                                    position: 10, source_query: "is:ace")
    @role_label = CardLabel.create!(slug: "gust", name: "Gust", family: "role", position: 10)
  end

  test "the index lists both families and their assignment counts" do
    @type_label.assignments.create!(fingerprint: "fp", source: "imported")

    get admin_card_labels_path

    assert_response :success
    assert_select "td", text: "ACE SPEC"
    assert_select "td", text: "Gust"
  end

  test "an admin creates a type label with its search token" do
    assert_difference "CardLabel.count", 1 do
      post admin_card_labels_path, params: {
        card_label: { slug: "radiant", name: "Radiant", family: "type", position: 20,
                      source_query: "is:radiant" }
      }
    end

    assert_redirected_to admin_card_labels_path
    assert_equal "is:radiant", CardLabel.find_by(slug: "radiant").source_query
  end

  # The asymmetry the whole design rests on: a role slug is referenced by code (stage 2's
  # suggestion rules), so one invented here would be a label no rule can ever propose.
  test "creating a role label is refused" do
    assert_no_difference "CardLabel.count" do
      post admin_card_labels_path, params: {
        card_label: { slug: "healing", name: "Healing", family: "role", position: 30 }
      }
    end

    assert_redirected_to admin_card_labels_path
    assert_match(/seeded/, flash[:alert])
  end

  test "deleting a role label is refused and deleting a type label is not" do
    assert_no_difference "CardLabel.count" do
      delete admin_card_label_path(@role_label)
    end

    assert_match(/seeded/, flash[:alert])

    assert_difference "CardLabel.count", -1 do
      delete admin_card_label_path(@type_label)
    end
  end

  # A role label is still editable: a typo in a name or a wrong display order is a correction, not
  # a new vocabulary entry.
  test "a role label's name and position stay editable" do
    patch admin_card_label_path(@role_label), params: { card_label: { name: "Gust (bench)", position: 40 } }

    assert_equal "Gust (bench)", @role_label.reload.name
    assert_equal 40, @role_label.position
  end

  test "importing enqueues the job and records the import" do
    assert_difference [ "Import.count" ], 1 do
      assert_enqueued_with(job: CardLabels::ImportJob) do
        post import_admin_card_label_path(@type_label)
      end
    end

    assert_redirected_to admin_imports_path
    assert_equal "card_labels", Import.last.kind
  end

  # Only a label that says where to read it can be imported, and the screen must refuse rather
  # than enqueue a run that will fail with an ArgumentError from a service constructor.
  test "importing a label with no search token is refused before anything is enqueued" do
    assert_no_enqueued_jobs do
      post import_admin_card_label_path(@role_label)
    end

    assert_match(/no search token/, flash[:alert])
  end

  test "a non-admin cannot reach the screen" do
    sign_in users(:two)

    get admin_card_labels_path

    assert_redirected_to root_path
  end
end
```

Check the redirect a refused non-admin actually gets against
`Admin::BaseController#require_admin!` before asserting `root_path`.

- [ ] **Step 2: Run it and watch it fail**

```bash
bin/rails test test/controllers/admin/card_labels_controller_test.rb
```

Expected: `NameError: undefined local variable or method 'admin_card_labels_path'`.

- [ ] **Step 3: Add the routes**

`config/routes.rb`, inside `namespace :admin`, after `resources :archetypes`:

```ruby
      # The card-label vocabulary. `import` is a POST on the member: it enqueues a run of that
      # label's own `is:` token, so there is nothing to preview and nothing to type.
      resources :card_labels do
        post :import, on: :member
      end
```

- [ ] **Step 4: Write the controller**

`app/controllers/admin/card_labels_controller.rb`:

```ruby
module Admin
  # The card-label vocabulary, and the button that fills a `type` label from Limitless.
  #
  # No Pundit call anywhere below: Admin::BaseController#require_admin! is the whole gate for this
  # namespace, and an `authorize` here would be the only one in the panel.
  #
  # `role` labels are visible and editable but cannot be created or deleted here. They are seeded
  # from CardLabel::ROLES because stage 2's suggestion rules key on their slugs — an invented role
  # would be a label no rule can propose, and a deleted one would silently take a rule's output
  # with it. A `type` label is referenced by nothing but its own search token, so it is ordinary
  # data.
  class CardLabelsController < BaseController
    SEEDED_FAMILY_MESSAGE = "Role labels are seeded from the application, not created here.".freeze

    before_action :set_card_label, only: %i[edit update destroy import]

    def index
      # One grouped count rather than a per-row association read: the index prints a number per
      # row and loading every assignment to produce it is a payload nobody looks at.
      @card_labels = CardLabel.order(:family, :position, :slug)
      @assignment_counts = CardLabelAssignment.active.group(:card_label_id).count
    end

    def new
      @card_label = CardLabel.new(family: "type")
    end

    def create
      @card_label = CardLabel.new(card_label_params)
      return redirect_to(admin_card_labels_path, alert: SEEDED_FAMILY_MESSAGE) if @card_label.role?

      if @card_label.save
        redirect_to admin_card_labels_path, notice: "Card label created."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      # `family` is not permitted (see card_label_params), so an edit cannot move a label between
      # the two governances — which is the only way the create refusal above could be walked round.
      if @card_label.update(card_label_params)
        redirect_to admin_card_labels_path, notice: "Card label updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      return redirect_to(admin_card_labels_path, alert: SEEDED_FAMILY_MESSAGE) if @card_label.role?

      count = @card_label.assignments.count
      @card_label.destroy
      redirect_to admin_card_labels_path,
        notice: "Card label deleted, with #{count} #{"assignment".pluralize(count)}."
    end

    def import
      unless @card_label.importable?
        redirect_to admin_card_labels_path,
          alert: "#{@card_label.name} has no search token, so there is nothing to import it from."
        return
      end

      import = current_user.imports.create!(
        kind: "card_labels",
        label: "#{@card_label.name} (#{@card_label.source_query})"
      )
      CardLabels::ImportJob.perform_later(import.id, @card_label.id, current_user.id)

      redirect_to admin_imports_path,
        notice: "Importing #{@card_label.name} from Limitless. Watch this table for the result."
    end

    private

    def set_card_label
      @card_label = CardLabel.find(params[:id])
    end

    # `family` is permitted on create alone: see #update.
    def card_label_params
      permitted = params.require(:card_label).permit(:slug, :name, :position, :description, :source_query)
      permitted[:family] = params[:card_label][:family] if action_name == "create"
      permitted
    end
  end
end
```

- [ ] **Step 5: Write the two Phlex views**

`app/views/components/admin/card_labels/index_view.rb` — follow
`Admin::StandardPools::IndexView` exactly (`Ui::PageHeader`, `Ui::DataTable`, `Ui::AdminActions`):

```ruby
module Admin
  module CardLabels
    class IndexView < ApplicationComponent
      def initialize(card_labels:, assignment_counts:)
        @card_labels = card_labels
        @assignment_counts = assignment_counts
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Card Labels") do
            link_to "New Label", new_admin_card_label_path, class: "btn btn-primary"
          end

          render Ui::DataTable.new(
            columns: [ "Label", "Family", "Slug", "Search", "Cards", "Actions" ]
          ) do |t|
            @card_labels.each { |label| row(t, label) }
          end
        end
      end

      private

      def row(t, label)
        t.row do
          t.cell { label.name }
          t.cell { label.family }
          t.cell { label.slug }
          t.cell { label.source_query.presence || "—" }
          t.cell { @assignment_counts.fetch(label.id, 0).to_s }
          t.cell { actions(label) }
        end
      end

      # A role label carries no delete link at all, rather than one the controller then refuses:
      # the refusal is the rule, and a button that only ever says no is a worse way to state it.
      def actions(label)
        div(class: "admin-actions") do
          button_to("Import", import_admin_card_label_path(label), class: "btn btn-secondary btn-sm") if label.importable?
          link_to "Edit", edit_admin_card_label_path(label), class: "btn btn-secondary btn-sm"
          unless label.role?
            button_to "Delete", admin_card_label_path(label), method: :delete,
              class: "btn btn-danger btn-sm",
              form: { data: { turbo_confirm: "Delete #{label.name} and its assignments?" } }
          end
        end
      end
    end
  end
end
```

`app/views/components/admin/card_labels/form_view.rb` — a `form_with model: [ :admin, @card_label ]`
carrying `slug`, `name`, `family` (a select, disabled on edit — the controller ignores it there),
`position`, `source_query`, `description`. Copy the markup and CSS classes from
`app/views/components/admin/standard_pools/form_view.rb`.

Render both from the controller the way `Admin::StandardPoolsController` renders its views — check
that file for whether it renders the component explicitly or relies on a template, and match it.

- [ ] **Step 6: Run the tests**

```bash
bin/rails test test/controllers/admin/card_labels_controller_test.rb
```

Expected: PASS (8 tests).

- [ ] **Step 7: Sabotage-verify**

Add `:family` to the permitted params unconditionally → the "role label's name and position stay
editable" test still passes, so add an assertion to it first
(`assert_equal "role", @role_label.reload.family` after patching with `family: "type"`), watch it
go red, then restore. Drop the `role?` guard in `#create` → the "creating a role label is refused"
test goes red.

- [ ] **Step 8: Commit**

```bash
git add config/routes.rb app/controllers/admin/card_labels_controller.rb app/views/components/admin/card_labels test/controllers/admin/card_labels_controller_test.rb
git commit -m "Give card labels an admin screen, with roles seeded and types editable"
```

---

### Task 7: `card_labels:resync_fingerprints`

**Files:**
- Create: `lib/tasks/card_labels.rake`
- Test: `test/lib/tasks/card_labels_rake_test.rb`

**Interfaces:**
- Consumes: `CardLabelAssignment`, `Card`.
- Produces: `bin/rails card_labels:resync_fingerprints`, which rewrites an assignment whose
  fingerprint no card carries when its own `card_id` unambiguously says what it moved to, and
  **reports** every other case. Exits non-zero when it reports something, the way
  `standard_pools:backfill_anchors` fails a boot on purpose.

- [ ] **Step 1: Read the precedent**

```bash
sed -n 1,60p lib/tasks/archetypes.rake
```

`Archetypes::FingerprintSync` is the model: it reports the pairs it cannot write rather than
writing one of them. Match its output shape and its exit behaviour.

- [ ] **Step 2: Write the failing test**

`test/lib/tasks/card_labels_rake_test.rb`:

```ruby
require "test_helper"
require "rake"

class CardLabelsRakeTest < ActiveSupport::TestCase
  setup do
    Rake::Task.clear
    Cartodex::Application.load_tasks
    @label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    @card = cards(:honedge)
  end

  # A force: true rescrape can move a Pokémon's fingerprint. The assignment then points at a
  # fingerprint no card carries, the report can never join it, and the card silently loses its
  # label — which is exactly the drift Archetypes::FingerprintSync exists to repair out of band.
  test "it moves an assignment onto the card's current fingerprint" do
    assignment = @label.assignments.create!(fingerprint: "honedge_fp", card: @card, source: "imported")
    @card.update_column(:fingerprint, "honedge_fp_v2")

    run

    assert_equal "honedge_fp_v2", assignment.reload.fingerprint
  end

  test "an assignment with no card to read is reported, not guessed" do
    @label.assignments.create!(fingerprint: "orphan_fp", source: "imported")

    output = run

    assert_match "orphan_fp", output
  end

  # Writing through would break the UNIQUE key half way into a run and leave the rest unexamined.
  test "a move that would collide with an existing decision is reported, not written" do
    kept = @label.assignments.create!(fingerprint: "doublade_fp", source: "curated")
    moving = @label.assignments.create!(fingerprint: "honedge_fp", card: @card, source: "imported")
    @card.update_column(:fingerprint, "doublade_fp")

    output = run

    assert_equal "honedge_fp", moving.reload.fingerprint
    assert_equal "curated", kept.reload.source
    assert_match "doublade_fp", output
  end

  test "it says nothing and changes nothing when every assignment resolves" do
    @label.assignments.create!(fingerprint: @card.fingerprint, card: @card, source: "imported")

    assert_no_changes "CardLabelAssignment.maximum(:updated_at)" do
      run
    end
  end

  private

  def run
    capture_io { Rake::Task["card_labels:resync_fingerprints"].tap(&:reenable).invoke }.join
  end
end
```

- [ ] **Step 3: Run it and watch it fail**

```bash
bin/rails test test/lib/tasks/card_labels_rake_test.rb
```

Expected: `RuntimeError: Don't know how to build task 'card_labels:resync_fingerprints'`.

- [ ] **Step 4: Write the task**

`lib/tasks/card_labels.rake`:

```ruby
namespace :card_labels do
  # Repair assignments whose fingerprint has moved under them.
  #
  # A force: true rescrape rewrites a card's fingerprint, and an assignment keyed on the old one
  # then joins to nothing: the card silently loses its label. This is why the assignment keeps the
  # printing it was decided from beside the fingerprint — the same pair, for the same reason, as
  # Archetype's primary_card_id / primary_fingerprint.
  #
  # It reports rather than writes wherever the answer is ambiguous, exactly like
  # Archetypes::FingerprintSync: an assignment with no card left to read, and a move that would
  # collide with a decision already recorded for the target fingerprint. Writing either would abort
  # a run part way through and leave the rest unexamined.
  desc "Move card label assignments onto their card's current fingerprint, reporting what it cannot"
  task resync_fingerprints: :environment do
    reports = []
    moved = 0

    CardLabelAssignment.includes(:card).find_each do |assignment|
      next if Card.exists?(fingerprint: assignment.fingerprint)

      card = assignment.card
      if card.nil? || card.fingerprint.blank?
        reports << "#{assignment.card_label.slug}: #{assignment.fingerprint} matches no card, and " \
                   "the assignment names no printing to read one from"
        next
      end

      if CardLabelAssignment.exists?(card_label_id: assignment.card_label_id, fingerprint: card.fingerprint)
        reports << "#{assignment.card_label.slug}: #{assignment.fingerprint} moved to " \
                   "#{card.fingerprint}, which already carries a decision — resolve by hand"
        next
      end

      assignment.update_column(:fingerprint, card.fingerprint)
      moved += 1
    end

    puts "Moved #{moved} #{"assignment".pluralize(moved)}."
    next if reports.empty?

    puts "#{reports.size} could not be moved:"
    reports.each { |line| puts "  #{line}" }
    abort "card_labels:resync_fingerprints left #{reports.size} assignments unresolved."
  end
end
```

`update_column`, not `update!`: moving a key has no business asking whether the rest of the row
validates, the same call `#unclaim` and `DecksController#share` make.

- [ ] **Step 5: Run the tests**

```bash
bin/rails test test/lib/tasks/card_labels_rake_test.rb
```

Expected: PASS. The `abort` makes the reporting tests raise `SystemExit`; wrap `run` in
`assert_raises(SystemExit)` where the test expects a report, or have the task collect and print
before aborting so `capture_io` still sees the output — the code above prints first, so
`assert_raises(SystemExit) { run }` in those two tests is the adjustment to make.

- [ ] **Step 6: Sabotage-verify**

Replace the collision report with an unconditional `update_column` → the collision test goes red
with `ActiveRecord::RecordNotUnique`. Restore.

- [ ] **Step 7: Commit**

```bash
git add lib/tasks/card_labels.rake test/lib/tasks/card_labels_rake_test.rb
git commit -m "Repair card label assignments whose fingerprint moved, reporting what is ambiguous"
```

---

### Task 8: The deck report shows the label

**Files:**
- Modify: `app/services/archetypes/card_stats.rb`
- Modify: `app/views/components/archetypes/name_group_row.rb`
- Modify: `app/assets/stylesheets/application.css`
- Test: `test/services/archetypes/card_stats_test.rb`
- Test: `test/controllers/archetypes_controller_test.rb`
- Test: `test/system/archetype_metagame_test.rb`

**Interfaces:**
- Consumes: `CardLabelAssignment` (Task 1), `CardLabel`.
- Produces: `Archetypes::CardStats::Entry#labels` — an Array of `CardLabel`, `family: "type"` only
  in stage 1, ordered by `position` then `slug`. Stage 2 reads the same association for its role
  mode.

- [ ] **Step 1: Write the failing service test**

Append to `test/services/archetypes/card_stats_test.rb`:

```ruby
  test "an entry carries the type labels of the card it reports" do
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    card = cards(:honedge)
    label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")

    entry = entry_for(card)

    assert_equal [ "ACE SPEC" ], entry.labels.map(&:name)
  end

  # A human's refusal is a row, not an absence, and the report must read it as the refusal it is.
  test "a rejected assignment is not a label" do
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    card = cards(:honedge)
    label.assignments.create!(fingerprint: card.fingerprint, source: "curated", rejected: true)

    assert_empty entry_for(card).labels
  end

  test "labels cost one query however many cards the report holds" do
    # Build the sample the existing flat-cost helpers in this file build, then:
    assert_equal one_card_queries, ten_card_queries
  end
```

Write `entry_for(card)` against whatever this file's existing helpers build a report from — read
the top of the file first and reuse them rather than inventing a second way to build a sample.

- [ ] **Step 2: Run it and watch it fail**

```bash
bin/rails test test/services/archetypes/card_stats_test.rb
```

Expected: `NoMethodError: undefined method 'labels' for an instance of Struct`.

- [ ] **Step 3: Load the labels in one query**

In `app/services/archetypes/card_stats.rb`, add `:labels` to the `Entry` struct's members, fill it
in `entry_for`, and add:

```ruby
    # fingerprint -> the labels on that card, in one query for the whole report.
    #
    # Keyed on the fingerprint and not on the card id because that is what a label is about: every
    # printing of Prime Catcher is an ACE SPEC, and the report already groups on the same key. A
    # card the key cannot fold (GROUPING_KEY's 'card:<id>' fallback) matches no assignment and is
    # simply unlabelled — which is honest, and is the state a labelled row could not describe.
    def labels_by_fingerprint
      @labels_by_fingerprint ||= CardLabelAssignment
        .active
        .where(fingerprint: rows_by_key.keys)
        .includes(:card_label)
        .group_by(&:fingerprint)
        .transform_values { |assignments| assignments.map(&:card_label).sort_by { |l| [ l.position, l.slug ] } }
    end
```

and in `entry_for`, `labels: labels_by_fingerprint.fetch(key, [])`.

- [ ] **Step 4: Render the badge**

In `app/views/components/archetypes/name_group_row.rb`, inside `.archetype-card-name`, after
`fixed_flag`:

```ruby
        # A type label annotates the card and never opens a section: an ACE SPEC is still an Item,
        # and moving it out would stop the category counts being a partition of the list. Read off
        # the group's first entry, since a name group's printings share a fingerprint whenever the
        # group is not split, and a split group's printings are genuinely different cards.
        def type_labels
          @group.entries.flat_map(&:labels).uniq
        end

        def label_flags
          type_labels.each do |label|
            span(class: "badge archetype-card-label", title: label.description) { label.name }
          end
        end
```

Call `label_flags` from `main_line`'s name div.

- [ ] **Step 5: Style it**

In `app/assets/stylesheets/application.css`, beside the `.archetype-fixed-flag` rule, add
`.archetype-card-label` with the same shape and a different token so it does not read as a second
"fixed". Keep it single-class specificity, in the same layer.

- [ ] **Step 6: Update the flat-cost test and add the rendering test**

In `test/controllers/archetypes_controller_test.rb`, the flat-cost test asserts `small == large`
and needs no number change — but its comment says "measured at 16 queries". Update the comment to
17 and state why (one grouped read of `card_label_assignments`). Add:

```ruby
  test "show badges a card's type label on its row" do
    archetype = quiet_archetype(400, name: "Labelled Archetype")
    standing = listed_standing_for(archetype, 400)
    card = standing.deck.deck_cards.first.card
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    label.assignments.create!(fingerprint: card.fingerprint, card: card, source: "imported")

    get archetype_path(archetype)

    assert_response :success
    assert_select ".archetype-card-row .archetype-card-label", text: "ACE SPEC"
  end
```

- [ ] **Step 7: Add the mobile geometry system test**

In `test/system/archetype_metagame_test.rb` (the file #161 added the `/archetypes` geometry test
to — read it and copy its `drive_at` usage), assert that at 390 px the badge sits on its own line
rather than as a flex sibling squeezing the name:

```ruby
  test "the label badge does not squeeze the card name on a narrow screen" do
    # …build an archetype with one labelled card, visit it…
    name = find(".archetype-card-row .archetype-card-name")
    badge = find(".archetype-card-row .archetype-card-label")

    assert_operator badge.rect.width, :<, name.rect.width / 2,
      "the badge is taking half the name cell"
  end
```

Both viewports must pass:

```bash
bin/rails test test/system/archetype_metagame_test.rb
SYSTEM_TEST_VIEWPORT=mobile bin/rails test test/system/archetype_metagame_test.rb
```

- [ ] **Step 8: Sabotage-verify**

Change `.active` to `.all` in `labels_by_fingerprint` → the rejected-assignment test goes red.
Move the `where(fingerprint:)` read inside `entry_for` (one query per entry) → the flat-cost test
goes red. Restore.

- [ ] **Step 9: Commit**

```bash
git add app/services/archetypes/card_stats.rb app/views/components/archetypes/name_group_row.rb app/assets/stylesheets/application.css test/services/archetypes test/controllers/archetypes_controller_test.rb test/system/archetype_metagame_test.rb
git commit -m "Badge a card's type label on the deck report"
```

---

### Task 9: Correct what has become false, and verify the whole thing

**Files:**
- Modify: `CLAUDE.md`
- Modify: `app/services/archetypes/card_stats.rb` (the comment above `category_of`)
- Modify: `docs/superpowers/specs/2026-09-05-archetype-metagame-stats-design.md` (its "no ACE SPEC
  category" paragraph)

**Interfaces:**
- Consumes: everything above.
- Produces: documentation that matches the code, and a green suite at both viewports.

- [ ] **Step 1: Correct the three texts**

Each currently asserts, with measurements, that an ACE SPEC category is not derivable. Half of that
is now false, and the §9.2 lesson of the handoffs is that a measured refusal outliving its own
truth is how a spec starts lying. Each becomes: the *report* still has no ACE SPEC **category** —
the label is an annotation and the categories stay a partition — and the flag itself is now
recorded, imported from Limitless's card search rather than derived from the card page. Keep the
measurement that explains why nothing else could have produced it (rarity does not isolate it, 0 of
4720 effects mention it, the card page does not carry it).

Add to `CLAUDE.md`, in the architecture section beside the other services, a paragraph on the
store: the two families and their two governances, the fingerprint key with `card_id` beside it,
the provenance rule, "the import never deletes and never scrapes a card", and the one-request
`show=all` measurement.

- [ ] **Step 2: Run the whole suite**

```bash
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system
```

Expected: 0 failures on all four. The unit baseline before this stage is **1350 tests**; record
the new number.

- [ ] **Step 3: Lint and scan the files written**

```bash
bin/rubocop app/models/card_label.rb app/models/card_label_assignment.rb app/services/card_labels app/jobs/card_labels app/controllers/admin/card_labels_controller.rb app/views/components/admin/card_labels lib/tasks/card_labels.rake db/seeds/card_labels.rb test/services/card_labels test/jobs/card_labels test/models/card_label_test.rb test/models/card_label_assignment_test.rb test/controllers/admin/card_labels_controller_test.rb
bin/brakeman --no-pager
bin/importmap audit
```

Never repo-wide: `mise` resolves Ruby 4.0.1 in this worktree and reports ~159 offences CI does not.

- [ ] **Step 4: Check Task 0's list**

Open `tmp/155-ce-qui-ne-rougirait-pas.md`. Every line reading *rien ne rougirait* must now name the
test that covers it. Anything left uncovered is either a test to write now or a line to move into
the PR description as a known blind spot — not something to leave unsaid.

- [ ] **Step 5: Run the import against the real source, in development**

```bash
bin/rails runner 'label = CardLabel.find_by(slug: "ace-spec"); r = CardLabels::Importer.call(label); puts r.inspect'
```

Expected on the production dump: assignments created for the ACE SPEC printings the catalogue
holds (18 were measured in #154, before the online import added cards), a `missing_printings` list
for the rest of the 46, `unlisted_fingerprints` empty, `complete?` true. Read the numbers rather
than the exit status — this is the one check that the whole chain works end to end.

- [ ] **Step 6: Commit and open the PR**

```bash
git add CLAUDE.md app/services/archetypes/card_stats.rb docs/superpowers/specs
git commit -m "Record that ACE SPEC is now imported, and that the categories stay a partition"
gh pr create --title "Store card labels, and import ACE SPEC from Limitless" --body "…"
```

The PR body states: what stage 1 does, the three rules the importer follows and why each is a
refusal, the measurements behind `show=all`, the flat cost moving 16 → 17, and what stage 2 will
add on top.

---

## Self-review notes

**Spec coverage.** Every decision in the spec maps to a task: decision 1 → Tasks 1, 2, 6;
decision 2 → Tasks 1, 7; decision 3 → Tasks 1, 4; decision 4 → Task 4; decision 5 → stage 2;
decision 6 → stage 2; decision 7 → stage 2; decision 8 → Task 8. The spec's two "tests that must be
written" habits are Task 0 and Task 9 step 4, plus the second-run tests in Task 4.

**Deliberately deferred to stage 2, and named here so it is not read as an omission:**
`CardLabel::ROLES`, the role seed, `CardLabels::RoleSuggester`, `Admin::CardRolesController`, the
`?group=role` mode, the "No role recorded" section, and the overlap sentence.

**One known adjustment for the implementer:** Task 7's task `abort`s when it reports, so the two
reporting tests need `assert_raises(SystemExit)`; the plan says so at the step rather than leaving
it to be discovered.
