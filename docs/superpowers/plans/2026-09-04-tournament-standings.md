# Tournament Standings Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let any member catalogue what the field played at a tournament — one public,
wiki-editable row per player, naming an archetype and optionally an imported decklist owned by
nobody — and let a member link their own private participation to the public row that names them.

**Architecture:** A new `TournamentStanding` hangs off `Tournament` (not off `User`: the players
recorded here have no account). Its optional decklist is a `Deck` with `user_id` NULL, which
forces `decks.user_id` to become nullable and turns three latent `deck.user` reads into bugs that
ship fixed in the same commit. The write surface is a nested `Tournaments::StandingsController`
whose every action is open to any signed-in member (wiki governance), with one owner-scoped
exception (`unclaim`). The decklist import reuses `Decks::Fetcher` through a new job — not
`Decks::ImportJob`, which broadcasts into the contributor's own deck grid.

**Tech Stack:** Rails 8.1, Ruby 3.4.1, SQLite3, Phlex components, Pundit, Turbo Streams,
Solid Queue, Minitest + Capybara/Selenium.

**Spec:** `docs/superpowers/specs/2026-09-04-tournament-standings-design.md`

## Global Constraints

- Code and code comments in English. Versioned docs in English.
- **All views are Phlex components** under `app/views/components/`; ERB files are one-line
  wrappers only. Never write view logic in ERB. See the `phlex-architecture` skill.
- `tokens()` does not exist in Phlex 2.4 — build conditional classes with
  `[ "a", ("b" if cond) ].compact.join(" ")`.
- Phlex dasherizes **Symbol** attribute values. Any attribute whose exact text is load-bearing
  (`name`, `id`, `value`) must be a **String**.
- Every system test must pass on **both** viewports: `bin/rails test:system` and
  `SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`. Never click a navbar link directly — use
  `click_nav_link`.
- Fixtures skip callbacks: any normalized mirror column (`player_name_normalized`,
  `name_normalized`) and `decks.key` must be spelled out by hand in YAML.
- `division` values are the three strings of `TournamentProfile::DIVISIONS`
  (`junior`, `senior`, `masters`). Never declare a second list.
- Deck addressing: a `Deck` is addressed by `key` in every URL and JSON payload
  (`Deck#to_param` returns it). `decks.id` stays the FK target.
- Run `bin/rubocop` (rubocop-rails-omakase) and `bin/brakeman --no-pager` before every commit.
- `bin/rails test` must be green at the end of every task.

## Preflight rulings already applied to this plan (2026-09-04)

The pre-flight conflict scan found three real defects in the first draft; the text below is
already corrected. Full reasoning and cost-if-wrong live in the SDD ledger at
`.superpowers/sdd/2026-09-04-tournament-standings/progress.md`.

1. `Deck has_one :tournament_standing, dependent: :nullify` lives in **Task 2**, not Task 1 —
   in Task 1 the class does not exist and Task 1's own deck-destroy test fires the callback.
2. The nested `resources :standings` route block lives in **Task 4**, not Task 6 — Task 4's Row
   emits `unclaim_tournament_standing_path` and one of its tests exercises that branch.
3. `Tournaments::StandingsController` carries its own
   `rescue_from Pundit::NotAuthorizedError` — nothing outside `PubliclyReachable` rescues it, so
   a refused `unclaim` would otherwise be a 500. Task 7 asserts a redirect, not a 403.
4. Contingent: if Task 6's `RecordNotUnique` assertion does not raise through the request stack,
   move it to the model test. Noted inline.

## Interpretation notes (read before Task 8)

The spec says the table "renders a pending state on that row (`Ui::ImportingList`'s vocabulary)
until the job replaces it". `Import` carries no link to a standing, and the spec's migration is
three parts that do not add one — so the pending state is rendered as an `Ui::ImportingList`
**beside** the table (the component the phrase names, reused unchanged, whose `importing-<id>`
item the job already removes by target) rather than as a spinner inside the row. This is
reload-safe, adds no column, and the row itself is still replaced by the broadcast when the
list lands. If you want a per-row spinner instead, that needs a
`tournament_standing_id` on `imports` — a fourth migration part, and the user's call.

## File Structure

**Created**

| File | Responsibility |
| --- | --- |
| `db/migrate/20260904120000_create_tournament_standings.rb` | The table, the three division counters, the nullable `decks.user_id` |
| `app/models/tournament_standing.rb` | One line of the public sheet: normalization, uniqueness, placement/entry rules, ownerless-deck cascade |
| `app/policies/tournament_standing_policy.rb` | Wiki writes for any member; `unclaim?` owner-scoped |
| `app/controllers/tournaments/standings_controller.rb` | CRUD + claim/unclaim, entry lookups scoped to the reader |
| `app/views/components/tournaments/standings/row.rb` | One `.data-table-row`, broadcastable on its own |
| `app/views/components/tournaments/standings/table.rb` | The sheet, grouped by division in age order |
| `app/views/components/tournaments/standings/form.rb` | Shared by `new` and `edit` |
| `app/views/components/tournaments/standings/new_view.rb` | Page wrapper |
| `app/views/components/tournaments/standings/edit_view.rb` | Page wrapper |
| `app/views/tournaments/standings/new.html.erb` | One-line Phlex wrapper |
| `app/views/tournaments/standings/edit.html.erb` | One-line Phlex wrapper |
| `app/views/components/ui/archetype_picker.rb` | `Decks::ArchetypeField` with the deck made optional |
| `app/jobs/tournaments/standing_list_import_job.rb` | Imports the field list as an ownerless deck |
| `test/fixtures/tournament_standings.yml` | Standing fixtures |
| `test/models/tournament_standing_test.rb` | Model rules |
| `test/policies/tournament_standing_policy_test.rb` | Policy rules |
| `test/controllers/tournaments/standings_controller_test.rb` | Controller rules |
| `test/jobs/tournaments/standing_list_import_job_test.rb` | Job rules |
| `test/system/tournament_standings_test.rb` | Both viewports |

**Modified**

| File | Change |
| --- | --- |
| `app/models/deck.rb` | `belongs_to :user, optional:`, `has_one :tournament_standing`, `ownerless_deck_is_shared_and_virtual`, `owner_label` |
| `app/models/tournament.rb` | `has_many :standings`, three counters + validations, `participant_count_for` |
| `app/models/tournament_entry.rb` | `has_one :standing, dependent: :nullify`, comment on `participant_count` |
| `app/models/import.rb` | `KINDS` gains `standing_list`, plus a scope |
| `app/controllers/decks_controller.rb` | `#show`'s owner branch must not be true for nil == nil |
| `app/services/search/global.rb` | `shared_deck_scope` must keep NULL-owner rows |
| `app/services/decks/fetcher.rb` | `shared:`/`format:`/`standard_pool:` keywords, nil user |
| `app/controllers/admin/imports_controller.rb` | `#retry` refuses `standing_list` explicitly |
| `app/views/components/admin/decks/index_view.rb`, `.../show_view.rb`, `.../dashboard/index_view.rb` | `deck.user.email` → `deck.owner_label` |
| `app/views/components/decks/classification_fields.rb` | Renders `Ui::ArchetypePicker` |
| `app/views/components/decks/archetype_field.rb` | Deleted (replaced by the Ui component) |
| `app/views/components/tournaments/show_view.rb` | Standings section + "Publish my participation" |
| `app/views/tournaments/show.html.erb` | Passes the new keywords |
| `app/controllers/tournaments_controller.rb` | `#show` loads standings, pending imports, claimable entries |
| `app/views/components/ui/importing_list.rb` | `list_id:` keyword (two lists must not share one DOM id) |
| `config/routes.rb` | Nested `resources :standings` |
| `app/assets/stylesheets/application.css` | `.tournament-standings` spacing |
| `test/controllers/public_access_test.rb` | Deck count, standings write actions per action |
| `CLAUDE.md` | The four paragraphs the spec's Documentation section names |

---

### Task 1: The migration and the nullable `decks.user_id` audit

**Files:**
- Create: `db/migrate/20260904120000_create_tournament_standings.rb`
- Modify: `app/models/deck.rb`, `app/controllers/decks_controller.rb:99`,
  `app/services/search/global.rb` (`shared_deck_scope`),
  `app/views/components/admin/decks/index_view.rb:16`,
  `app/views/components/admin/decks/show_view.rb:15`,
  `app/views/components/admin/dashboard/index_view.rb:57`,
  `db/schema.rb` (regenerated), `test/fixtures/decks.yml`,
  `test/controllers/public_access_test.rb:75`
- Test: `test/models/deck_test.rb`, `test/controllers/decks_controller_test.rb`,
  `test/services/search/global_test.rb`, `test/controllers/admin/decks_controller_test.rb`,
  `test/controllers/admin/dashboard_controller_test.rb`

**Interfaces:**
- Consumes: nothing.
- Produces: the `tournament_standings` table (unused until Task 2); the three
  `<division>_participant_count` columns on `tournaments`; `decks.user_id` nullable;
  `Deck#owner_label → String`; the `decks(:field_list)` fixture (ownerless, shared,
  non-physical, `key: deck-field-list-key`).

- [ ] **Step 1: Write the migration**

`db/migrate/20260904120000_create_tournament_standings.rb`:

```ruby
# Three parts, one migration — and the third is why the other two cannot ship without it. Making
# decks.user_id nullable turns three `deck.user.email` reads in the admin panel from dead code
# into NoMethodErrors and two more reads into wrong answers, so the audit fixes ship in this
# same commit.
class CreateTournamentStandings < ActiveRecord::Migration[8.1]
  def change
    create_table :tournament_standings do |t|
      t.references :tournament, null: false, foreign_key: true
      t.string :player_name, null: false
      # NOT NULL although the model maintains it in a callback, for the reason
      # tournaments.name_normalized is: the UNIQUE index below depends on it.
      t.string :player_name_normalized, null: false
      t.string :division, null: false
      t.integer :placement
      t.integer :wins
      t.integer :losses
      t.integer :ties
      # NOT NULL: the archetype is the point of the record. A row that names nobody's deck
      # archetype records nothing a metagame reader can use.
      t.references :archetype, null: false, foreign_key: true
      # The event's field list — a Deck owned by nobody. Optional: most rows name an archetype
      # and no list.
      t.references :deck, foreign_key: true
      # index: false because the partial UNIQUE index below covers this column on its own, and a
      # second plain index on the same single column would be pure duplication.
      t.references :tournament_entry, foreign_key: true, index: false
      t.references :created_by, foreign_key: { to_table: :users }

      t.timestamps
    end

    # One player, one row per division. The model validation exists for the readable error, this
    # index for the guarantee — the same division of labour as (set_name, set_number) on Card and
    # (name_normalized, date) on Tournament.
    add_index :tournament_standings, [ :tournament_id, :player_name_normalized, :division ],
      unique: true, name: "index_tournament_standings_on_event_and_player"
    # The sheet's own sort. The null-last expression the scope adds is computed, so this index
    # serves the (tournament_id, division) prefix rather than the whole ORDER BY.
    add_index :tournament_standings, [ :tournament_id, :division, :placement ],
      name: "index_tournament_standings_on_event_division_placement"
    # A participation is published at most once. This is the index that actually stops a member
    # publishing themselves twice under two spellings of their own name, which the name key
    # cannot see. Partial, because SQLite treats NULLs as distinct and every unclaimed row
    # carries one — the trap Archetype's old index fell into.
    add_index :tournament_standings, :tournament_entry_id, unique: true,
      where: "tournament_entry_id IS NOT NULL",
      name: "index_tournament_standings_on_claimed_entry"

    # Per-division field sizes, on the event rather than on each row: two players in the same
    # division at the same event are ranked against the same number.
    add_column :tournaments, :junior_participant_count, :integer
    add_column :tournaments, :senior_participant_count, :integer
    add_column :tournaments, :masters_participant_count, :integer

    # A tournament field list belongs to an event, not to a member. No backfill: every existing
    # deck keeps its owner.
    change_column_null :decks, :user_id, true
  end
end
```

- [ ] **Step 2: Run the migration**

```bash
bin/rails db:migrate
bin/rails db:test:prepare
```

Expected: `db/schema.rb` gains `tournament_standings`, the three counters, and `decks.user_id`
loses `null: false`. Confirm with `grep -n 'create_table "tournament_standings"' -A 20 db/schema.rb`
and `grep -n '"user_id"' db/schema.rb | head`.

- [ ] **Step 3: Write the failing model tests**

Append to `test/models/deck_test.rb`:

```ruby
  test "an ownerless deck must be shared" do
    deck = Deck.new(name: "Field list", standard_pool: standard_pools(:twm_por), shared: false)

    refute_predicate deck, :valid?
    assert_includes deck.errors[:shared], "must be true for a deck with no owner"
  end

  test "an ownerless deck must not be physical" do
    deck = Deck.new(name: "Field list", standard_pool: standard_pools(:twm_por),
                    shared: true, physical: true)

    refute_predicate deck, :valid?
    assert_includes deck.errors[:physical], "must be false for a deck with no owner"
  end

  test "an ownerless shared virtual deck saves" do
    deck = Deck.new(name: "Field list", standard_pool: standard_pools(:twm_por), shared: true)

    assert_predicate deck, :valid?
    assert deck.save
    assert_nil deck.reload.user_id
  end

  test "a deck with an owner is free to be private and physical" do
    deck = Deck.new(user: users(:one), name: "Mine",
                    standard_pool: standard_pools(:twm_por), physical: true)

    assert_predicate deck, :valid?
  end

  test "owner_label names the member, or says the deck is a field list" do
    assert_equal users(:one).email, decks(:one).owner_label
    assert_equal "Tournament field list", decks(:field_list).owner_label
  end
```

- [ ] **Step 4: Write the failing audit-regression tests**

Append to `test/controllers/decks_controller_test.rb`:

```ruby
  # `@deck.user_id == current_user&.id` was true with both sides nil, so an ownerless field list
  # served the owner's page — inline editing, allocation steppers and all — to the public.
  test "a visitor on an ownerless shared deck gets the public page, not the owner's" do
    sign_out @user

    get deck_path(decks(:field_list))

    assert_response :success
    assert_select ".deck-card-item"
    assert_select "form.deck-form", count: 0
    assert_select ".deck-actions-dropdown", count: 0
  end
```

Append to `test/services/search/global_test.rb`:

```ruby
  # `where.not(user: @user)` compiles to `user_id != ?`, which SQL evaluates to NULL — not true —
  # for an ownerless row, so every field list vanished from a signed-in member's spotlight.
  test "an ownerless shared deck reaches a signed-in member's shared results" do
    decks(:field_list).update!(name: "Zoroark Field List", shared: true)

    result = Search::Global.call(user: users(:one), query: "Zoroark")

    assert_includes result.shared_decks.map(&:name), "Zoroark Field List"
  end

  test "a visitor sees an ownerless shared deck too" do
    decks(:field_list).update!(name: "Zoroark Field List", shared: true)

    result = Search::Global.call(user: nil, query: "Zoroark")

    assert_includes result.shared_decks.map(&:name), "Zoroark Field List"
  end
```

Append to `test/controllers/admin/decks_controller_test.rb` (create the file with the standard
admin-test preamble if it does not exist — copy the `setup` block from
`test/controllers/admin/dashboard_controller_test.rb`, which signs in an admin):

```ruby
  # All three admin deck listings printed `deck.user.email`, which is a NoMethodError the moment
  # a deck has no owner.
  test "the deck index renders an ownerless deck" do
    get admin_decks_path

    assert_response :success
    assert_select ".data-table-cell", text: "Tournament field list"
  end

  test "the deck show page renders an ownerless deck" do
    get admin_deck_path(decks(:field_list))

    assert_response :success
    assert_select "p", text: /Tournament field list/
  end
```

Append to `test/controllers/admin/dashboard_controller_test.rb`:

```ruby
  test "the dashboard's recent decks render an ownerless deck" do
    decks(:field_list).update!(created_at: Time.current)

    get admin_root_path

    assert_response :success
    assert_select ".data-table-cell", text: "Tournament field list"
  end
```

- [ ] **Step 5: Add the fixture**

Append to `test/fixtures/decks.yml`:

```yaml
# An ownerless deck is a tournament field list: no user, shared (so /decks/shared is a listing
# that can show it at all) and never physical. DeckTest asserts those two rules; the audit
# regressions in DecksControllerTest, Search::GlobalTest and the two admin tests read this row.
field_list:
  name: Ash Ketchum — Regional Championship (2026-03-14)
  name_normalized: ash ketchum — regional championship (2026-03-14)
  standard_pool: twm_por
  key: deck-field-list-key
  shared: true
```

- [ ] **Step 6: Run the tests to verify they fail**

```bash
bin/rails test test/models/deck_test.rb test/services/search/global_test.rb \
  test/controllers/decks_controller_test.rb test/controllers/admin
```

Expected: FAIL — `Deck` has no `owner_label` (NoMethodError), the visitor gets the owner page,
the spotlight misses the field list, the admin views raise `NoMethodError: undefined method
'email' for nil`.

> **Preflight ruling 1 applied:** `Deck has_one :tournament_standing, dependent: :nullify`
> belongs to Task 2, not here. In this task `TournamentStanding` does not exist, and
> `test/models/deck_test.rb` destroys a deck — which would fire the nullify callback and raise
> `NameError`. Do not add it in this task.

- [ ] **Step 7: Implement the `Deck` changes**

In `app/models/deck.rb`, replace `belongs_to :user` with:

```ruby
  # Nullable since tournament standings: a field list belongs to an event, not to a member.
  # Every allocation service that reads deck.user sits behind an owner-only policy that a nil
  # user can never satisfy, so all of them are unreachable for such a deck by construction
  # rather than by convention — see ownerless_deck_is_shared_and_virtual below.
  belongs_to :user, optional: true
```

Add beside the other validations:

```ruby
  validate :ownerless_deck_is_shared_and_virtual
```

Add as a public method beside `format_label`:

```ruby
  # Who to print in the admin panel's three deck listings. Named here rather than repeated as
  # `deck.user&.email || "…"` in each of them: all three read `deck.user.email` and all three
  # raised the day user_id became nullable.
  def owner_label = user&.email || "Tournament field list"
```

Add to the `private` section:

```ruby
  # An ownerless deck is a tournament field list: it belongs to an event, not to a member. It
  # must be shared, because /decks/shared is the only listing that can show it, and it must not
  # be physical, because `physical` is what makes a deck consume a collection and there is no
  # collection to consume.
  def ownerless_deck_is_shared_and_virtual
    return if user_id.present?

    errors.add(:shared, "must be true for a deck with no owner") unless shared?
    errors.add(:physical, "must be false for a deck with no owner") if physical?
  end
```

- [ ] **Step 8: Fix the two live bugs and the three views**

`app/controllers/decks_controller.rb`, in `#show`:

```ruby
    # `current_user &&` first: `@deck.user_id == current_user&.id` alone is nil == nil for an
    # ownerless field list read by a visitor, which is `true`, which served the owner's page —
    # inline editing, steppers, result logging — to the public.
    if current_user && @deck.user_id == current_user.id
      owner_show
    else
      public_show
    end
```

`app/services/search/global.rb`, `shared_deck_scope`:

```ruby
    # Excluding the searcher's own decks is what keeps one deck out of two groups of the same
    # result list — and Search::ResultsList derives its option ids from the deck, so a duplicate
    # would emit one DOM id twice.
    #
    # The NULL branch is not decoration: `where.not(user: @user)` compiles to `user_id != ?`,
    # which SQL evaluates to NULL rather than true for an ownerless field list, so every one of
    # them vanished from a signed-in member's spotlight while a visitor still saw them.
    def shared_deck_scope
      @shared_deck_scope ||= begin
        scope = Deck.shared
        scope = scope.where(user_id: nil).or(scope.where.not(user_id: @user.id)) if @user
        scope.search(@query)
      end
    end
```

In the three admin views, replace `deck.user.email` / `@deck.user.email` with
`deck.owner_label` / `@deck.owner_label`.

- [ ] **Step 9: Fix the one literal count assertion**

`test/controllers/public_access_test.rb:75`:

```ruby
    # Three deck fixtures now: the two members' decks and the ownerless field list.
    assert_equal 3, Deck.count
```

- [ ] **Step 10: Run the whole suite**

```bash
bin/rails test
```

Expected: PASS. If another test asserts a literal `Deck` count or a shared-index row count, fix
it the same way and say so in the commit message.

- [ ] **Step 11: Sabotage-verify two of the new tests**

Prove each new test can actually go red before trusting it:

```bash
# 1. Put the nil == nil branch back and confirm the visitor test fails.
#    (edit decks_controller.rb: `if @deck.user_id == current_user&.id`)
bin/rails test test/controllers/decks_controller_test.rb -n "/ownerless shared deck gets the public page/"
# 2. Drop the NULL branch from shared_deck_scope and confirm the spotlight test fails.
bin/rails test test/services/search/global_test.rb -n "/reaches a signed-in member/"
```

Expected: both FAIL, then restore the fixes and both PASS.

- [ ] **Step 12: Lint, scan and commit**

```bash
bin/rubocop && bin/brakeman --no-pager
git add db/migrate db/schema.rb app/models/deck.rb app/controllers/decks_controller.rb \
  app/services/search/global.rb app/views/components/admin test/fixtures/decks.yml \
  test/models/deck_test.rb test/services/search/global_test.rb \
  test/controllers/decks_controller_test.rb test/controllers/admin \
  test/controllers/public_access_test.rb
git commit -m "Allow a deck to belong to no member, and fix what that broke"
```

---

### Task 2: The `TournamentStanding` model and the event's field sizes

**Files:**
- Create: `app/models/tournament_standing.rb`, `test/fixtures/tournament_standings.yml`,
  `test/models/tournament_standing_test.rb`
- Modify: `app/models/tournament.rb`, `app/models/tournament_entry.rb`, `app/models/deck.rb`
- Test: `test/models/tournament_standing_test.rb`, `test/models/tournament_test.rb`,
  `test/models/tournament_entry_test.rb`

**Interfaces:**
- Consumes: the `tournament_standings` table and the three counters from Task 1.
- Produces:
  - `TournamentStanding::DIVISIONS → ["junior", "senior", "masters"]` (Strings)
  - `TournamentStanding#record_label → String | nil` (`"3-1-0"`)
  - `TournamentStanding.as_a_sheet` (ordered relation, unplaced last)
  - `Tournament#standings` (has_many, `dependent: :destroy`)
  - `Tournament#participant_count_for(division) → Integer | nil`
  - `TournamentEntry#standing` (has_one, `dependent: :nullify`)
  - `tournament_standings(:ash_masters)`, `tournament_standings(:giovanni_masters)` fixtures

- [ ] **Step 1: Write the failing model test**

`test/models/tournament_standing_test.rb`:

```ruby
require "test_helper"

class TournamentStandingTest < ActiveSupport::TestCase
  setup do
    @tournament = tournaments(:one)
    @archetype = archetypes(:ogerpon)
  end

  # Fixtures skip callbacks, so player_name_normalized is spelled out by hand — the same trap
  # every NameNormalizable model has a test for.
  test "the fixtures' normalized player names are in step with their player names" do
    TournamentStanding.find_each do |standing|
      assert_equal standing.player_name.squish.downcase, standing.player_name_normalized,
        "#{standing.player_name.inspect} and its normalized mirror have drifted apart"
    end
  end

  test "player_name, division and archetype are required" do
    standing = TournamentStanding.new(tournament: @tournament)

    refute_predicate standing, :valid?
    assert_includes standing.errors.attribute_names, :player_name
    assert_includes standing.errors.attribute_names, :division
    assert_includes standing.errors.attribute_names, :archetype
  end

  test "placement and the record are optional but must be sane when given" do
    standing = build_standing(placement: 0, wins: -1)

    refute_predicate standing, :valid?
    assert_includes standing.errors.attribute_names, :placement
    assert_includes standing.errors.attribute_names, :wins

    assert_predicate build_standing(placement: nil, wins: nil, losses: nil, ties: nil), :valid?
  end

  test "an unknown division is refused" do
    standing = build_standing
    standing.division = "seniors"

    refute_predicate standing, :valid?
    assert_includes standing.errors.attribute_names, :division
  end

  # The readable half of the UNIQUE index, and it must fold case and squish: a player name
  # arrives copy-pasted off a standings sheet far more often than it arrives typed.
  test "one player gets one row per division, whatever the spacing or the case" do
    build_standing(player_name: "Brock").save!

    %w[Brock brock BROCK].each do |spelling|
      clash = build_standing(player_name: spelling)
      refute_predicate clash, :valid?, "#{spelling.inspect} should collide with Brock"
      assert_includes clash.errors[:player_name], "already has a standing in this division"
    end

    doubled = build_standing(player_name: "  Brock  ")
    refute_predicate doubled, :valid?
    assert_includes doubled.errors[:player_name], "already has a standing in this division"
  end

  test "the same player may hold a row in another division" do
    build_standing(player_name: "Brock", division: "masters").save!

    assert_predicate build_standing(player_name: "Brock", division: "senior"), :valid?
  end

  test "a placement may not exceed the field of its own division" do
    @tournament.update!(masters_participant_count: 8, junior_participant_count: 64)

    refute_predicate build_standing(division: "masters", placement: 9), :valid?
    # The junior field is larger, so the same placement is fine there — which is the whole
    # reason the counts are per division.
    assert_predicate build_standing(division: "junior", placement: 9), :valid?
  end

  test "a placement is accepted when the division's field size is unknown" do
    @tournament.update!(masters_participant_count: nil)

    assert_predicate build_standing(division: "masters", placement: 999), :valid?
  end

  test "a participation from another event cannot be linked" do
    standing = build_standing(tournament_entry: tournament_entries(:two))

    refute_predicate standing, :valid?
    assert_includes standing.errors[:tournament_entry], "must be a participation in this tournament"
  end

  test "a participation in this event may be linked" do
    assert_predicate build_standing(tournament_entry: tournament_entries(:one)), :valid?
  end

  test "record_label prints the W-L-T, and nothing at all when none is recorded" do
    assert_equal "3-1-0", build_standing(wins: 3, losses: 1, ties: 0).record_label
    # A partially recorded row still prints: a zero the user did not type reads better than a
    # blank cell beside two numbers they did.
    assert_equal "3-0-0", build_standing(wins: 3, losses: nil, ties: nil).record_label
    assert_nil build_standing(wins: nil, losses: nil, ties: nil).record_label
  end

  test "the sheet reads by placement with the unplaced last" do
    build_standing(player_name: "Unplaced", placement: nil).save!
    build_standing(player_name: "Second", placement: 2).save!
    build_standing(player_name: "First", placement: 1).save!

    names = @tournament.standings.as_a_sheet.where.not(id: tournament_standings(:ash_masters).id)
      .where.not(id: tournament_standings(:giovanni_masters).id).map(&:player_name)

    assert_equal %w[First Second Unplaced], names
  end

  test "destroying a standing destroys its ownerless field list" do
    standing = build_standing(deck: decks(:field_list))
    standing.save!

    assert_difference -> { Deck.count }, -1 do
      standing.destroy
    end
  end

  test "destroying a standing never destroys a member's own deck" do
    # Nothing points a standing at an owned deck today. The guard is what stops a future caller
    # detonating a member's deck through a standings delete.
    owned = decks(:one)
    standing = build_standing(deck: owned)
    standing.save!(validate: false)

    assert_no_difference -> { Deck.count } do
      standing.destroy
    end
    assert Deck.exists?(owned.id)
  end

  private

  def build_standing(**attrs)
    @tournament.standings.build(
      { player_name: "Brock", division: "masters", archetype: @archetype }.merge(attrs)
    )
  end
end
```

- [ ] **Step 2: Write the failing tests on the two existing models**

Append to `test/models/tournament_test.rb`:

```ruby
  test "participant_count_for reads the column for the division it is handed" do
    tournament = tournaments(:one)
    tournament.update!(junior_participant_count: 12, senior_participant_count: 30,
                       masters_participant_count: 512)

    assert_equal 12, tournament.participant_count_for("junior")
    assert_equal 30, tournament.participant_count_for(:senior)
    assert_equal 512, tournament.participant_count_for("masters")
    assert_nil tournament.participant_count_for("mystery")
  end

  test "a field size must be a positive integer when given" do
    tournament = tournaments(:one)

    refute tournament.update(masters_participant_count: 0)
    assert_includes tournament.errors.attribute_names, :masters_participant_count
    assert tournament.update(masters_participant_count: nil)
  end

  # :destroy, unlike :entries' restrict_with_error: a standing is a line of the event's own
  # public sheet, not somebody's private record of having been there.
  test "deleting an event takes its standings with it" do
    tournament = tournaments(:one)
    tournament.entries.destroy_all

    assert_difference -> { TournamentStanding.count }, -tournament.standings.count do
      assert tournament.destroy
    end
  end

  test "an event still refuses to be deleted while a participation survives" do
    tournament = tournaments(:one)

    assert_no_difference -> { TournamentStanding.count } do
      refute tournament.destroy
    end
  end
```

Append to `test/models/tournament_entry_test.rb`:

```ruby
  # Already true before this feature, and worth pinning now that a deck can have no owner:
  # deck_belongs_to_user compares deck.user_id != user_id, so a field list can never be used as
  # a member's own participation deck. The guard was there for free — this is the test that says
  # somebody checked.
  test "a tournament field list cannot be used as a participation deck" do
    entry = tournament_entries(:one)

    refute entry.update(deck: decks(:field_list))
    assert_includes entry.errors[:deck], "must belong to the same user"
  end

  # :nullify, not :destroy — the opposite call from Tournament#standings, and the whole reason
  # the two tables are separate: deleting my private participation must not erase a public row
  # other members read.
  test "deleting a participation unlinks its standing rather than deleting it" do
    entry = tournament_entries(:one)
    standing = tournament_standings(:ash_masters)
    standing.update!(tournament_entry: entry)

    assert_no_difference -> { TournamentStanding.count } do
      entry.destroy
    end
    assert_nil standing.reload.tournament_entry_id
  end
```

- [ ] **Step 3: Add the fixtures**

`test/fixtures/tournament_standings.yml`:

```yaml
# NOTE: fixtures skip callbacks, so player_name_normalized is spelled out by hand.
# TournamentStandingTest asserts it stays in step with player_name.
#
# Two rows on tournaments(:one) — the event tournament_entries(:one) and (:shared_event) point
# at — so a controller test has both a claimed-to-be and an unclaimed row to work with.

ash_masters:
  tournament: one
  player_name: Ash Ketchum
  player_name_normalized: ash ketchum
  division: masters
  placement: 33
  wins: 6
  losses: 3
  ties: 0
  archetype: ogerpon
  created_by: one

giovanni_masters:
  tournament: one
  player_name: Giovanni
  player_name_normalized: giovanni
  division: masters
  placement: 7
  wins: 7
  losses: 2
  ties: 0
  archetype: budew_ogerpon
  created_by: two
```

Note: the fixture set name is `tournament_standings`, so the accessor is
`tournament_standings(:ash_masters)`. The tests above use `tournament_standings(:ash_masters)` for
readability — add the alias in `test/test_helper.rb` **or** spell the full name in the tests.
Pick the full name: `tournament_standings(:ash_masters)`. Update the two tests above accordingly
(this plan writes `standings(...)` only where a relation is meant).

- [ ] **Step 4: Run the tests to verify they fail**

```bash
bin/rails test test/models/tournament_standing_test.rb test/models/tournament_test.rb \
  test/models/tournament_entry_test.rb
```

Expected: FAIL — `uninitialized constant TournamentStanding`.

- [ ] **Step 5: Write the model**

`app/models/tournament_standing.rb`:

```ruby
# One player's line in an event's public standings sheet.
#
# Not a TournamentEntry, and deliberately not merged into one: an entry is a *member's* private
# record of having been at an event, while a standing describes somebody who very likely has no
# account here — so it hangs off the Tournament, not off a User. Governance is wiki: any signed-in
# member may add, correct or delete any row, and `created_by` is the only trace of who typed it.
class TournamentStanding < ApplicationRecord
  # The same three values a TournamentProfile resolves to, as Strings because that is what the
  # column holds. Reused rather than re-declared: a second list would be free to drift from the
  # one that decides a real player's division.
  DIVISIONS = TournamentProfile::DIVISIONS.map(&:to_s).freeze

  belongs_to :tournament
  belongs_to :archetype
  # The event's field list: a Deck owned by nobody. Optional, because a row that names an
  # archetype and no list is the common case and still records something useful.
  belongs_to :deck, optional: true
  # The "this is me" link. Written only by Tournaments::StandingsController#claim/#unclaim and
  # never mass-assignable — see standing_params there for why.
  belongs_to :tournament_entry, optional: true
  belongs_to :created_by, class_name: "User", optional: true

  # validate: true rejects nil as well as an unknown value, which is what makes "division is
  # present" a readable error rather than a NOT NULL violation.
  enum :division, DIVISIONS.index_by(&:itself), validate: true

  validates :player_name, presence: true
  validates :placement, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :wins, :losses, :ties,
    numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validate :player_name_is_unique_in_division
  validate :placement_within_division_field
  validate :entry_belongs_to_same_tournament

  # before_validation as well as before_save, for the reason Tournament runs normalize_name
  # twice: the uniqueness validation has to compare the normalized value before the record is
  # saved, not once it already is. It squishes as well as downcasing — a player name arrives
  # copy-pasted off a standings sheet, with a trailing space or a double space where a column
  # wrapped, far more often than it arrives typed.
  #
  # NameNormalizable is not included: it normalizes `name`, and the column here is
  # `player_name`. Its `name_matching` scope is the point of that concern, and nothing searches
  # standings by player name.
  before_validation :normalize_player_name
  before_save :normalize_player_name

  # A destroyed standing takes its field list with it — but only a list nobody owns. Nothing
  # points a standing at an owned deck today; the guard is what keeps a future caller from
  # detonating a member's own deck through a standings delete.
  before_destroy :destroy_ownerless_deck

  # The sheet's order: ranked rows first, then the unplaced, then alphabetically. `placement IS
  # NULL` is what puts the unplaced last — SQLite sorts NULL *first* on a plain ASC. The index on
  # (tournament_id, division, placement) serves the equality and the division, not the computed
  # expression.
  scope :as_a_sheet, -> {
    order(:division, Arel.sql("placement IS NULL"), :placement, :player_name)
  }

  # The W-L-T as players write it, or nothing at all when no game was recorded. A missing half of
  # a partially typed record reads better as 0 than as a blank cell beside two numbers.
  def record_label
    return if wins.nil? && losses.nil? && ties.nil?

    [ wins, losses, ties ].map { |value| value || 0 }.join("-")
  end

  private

  def normalize_player_name
    self.player_name_normalized = player_name&.squish&.downcase
  end

  # The readable half of the (tournament_id, player_name_normalized, division) UNIQUE index — the
  # same division of labour as Tournament#name_and_date_are_unique. The error goes on
  # :player_name, a column the user has heard of, and the controller re-finds the offending row
  # from these three values so the form can link to it and offer to claim it.
  def player_name_is_unique_in_division
    return if tournament_id.blank? || player_name_normalized.blank? || division.blank?

    clash = TournamentStanding.where(
      tournament_id: tournament_id,
      player_name_normalized: player_name_normalized,
      division: division
    )
    clash = clash.where.not(id: id) if persisted?
    errors.add(:player_name, "already has a standing in this division") if clash.exists?
  end

  # A placement is ranked against the size of *this player's* age division, which is what the
  # three counters on Tournament hold. Silent when either half is unknown: placement is optional
  # by design, and an event whose field sizes nobody typed in must still accept rows.
  def placement_within_division_field
    return if placement.blank? || tournament.nil? || division.blank?

    field = tournament.participant_count_for(division)
    return if field.blank?
    return if placement <= field

    errors.add(:placement, "can't be greater than the #{division} field of #{field}")
  end

  # Whether the entry belongs to the *reader* is not a model concern — the model does not know
  # who is asking. The controller looks every entry up through current_user.tournament_entries,
  # so a stranger's entry is a RecordNotFound there rather than a policy question. What the model
  # can check is that the participation happened at this event.
  def entry_belongs_to_same_tournament
    return if tournament_entry.nil?
    return if tournament_entry.tournament_id == tournament_id

    errors.add(:tournament_entry, "must be a participation in this tournament")
  end

  def destroy_ownerless_deck
    deck&.destroy if deck && deck.user_id.nil?
  end
end
```

- [ ] **Step 6: Wire the two existing models**

In `app/models/tournament.rb`, add beside `has_many :entries`:

```ruby
  # :destroy, unlike :entries' restrict_with_error, and the difference is the whole point of the
  # split: an entry is somebody's private record of having been there, a standing is a line of the
  # event's own public sheet. Deleting the event takes the sheet with it — and still refuses while
  # any participation survives.
  has_many :standings, class_name: "TournamentStanding", dependent: :destroy
```

Add beside `TOP_CUT_BANDS`:

```ruby
  # The event's field size per age division. On the event rather than on each standing, because
  # two players in one division at one event are ranked against the same number — unlike
  # TournamentEntry#participant_count, which survives beside these (see the note there).
  DIVISION_COUNT_COLUMNS = {
    "junior" => :junior_participant_count,
    "senior" => :senior_participant_count,
    "masters" => :masters_participant_count
  }.freeze
```

Add beside the other validations:

```ruby
  validates :junior_participant_count, :senior_participant_count, :masters_participant_count,
    numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
```

Add as a public method:

```ruby
  # The size of one age division's field, or nil when nobody has typed it in. Keyed on the
  # division *name* so a standing can ask with its own column value whatever its type.
  def participant_count_for(division)
    column = DIVISION_COUNT_COLUMNS[division.to_s]
    column && public_send(column)
  end
```

In `app/models/deck.rb`, add beside the other `has_many`s (moved here from Task 1 by preflight
ruling 1 — the class it names did not exist there):

```ruby
  # :nullify, and the reverse direction of TournamentStanding#destroy_ownerless_deck.
  # Admin::DecksController#destroy is unscoped by design, so an admin can delete an ownerless
  # deck from the panel; without this the standing keeps a dangling deck_id and its row's list
  # link 404s.
  has_one :tournament_standing, dependent: :nullify
```

In `app/models/tournament_entry.rb`, add beside `has_many :deck_results`:

```ruby
  # :nullify, not :destroy — the opposite call from Tournament#standings, and for the reason the
  # two tables are separate at all: deleting my private participation must not erase a public row
  # other members read, only unlink it.
  has_one :standing, class_name: "TournamentStanding", dependent: :nullify
```

and put this comment above the `participant_count` validation:

```ruby
  # The event now carries a field size per division, and this column looks like a duplicate of
  # it. It is not derivable: an entry with no tournament_profile has no division, so there is
  # nothing on the event to read. Play! Pokémon ranks a placement against the size of *that
  # player's* age division, which is why the number is here at all — see CLAUDE.md.
```

- [ ] **Step 7: Run the tests to verify they pass**

```bash
bin/rails test test/models
```

Expected: PASS.

- [ ] **Step 8: Sabotage-verify three tests**

```bash
# 1. Drop `squish` from normalize_player_name → the double-space uniqueness case must fail.
# 2. Read tournament.participant_count in placement_within_division_field instead of
#    participant_count_for(division) → the per-division placement test must fail.
# 3. Change has_one :standing to dependent: :destroy → the entry-deletion test must fail.
bin/rails test test/models/tournament_standing_test.rb test/models/tournament_entry_test.rb
```

Expected: each sabotage produces exactly one red test; restore after each.

- [ ] **Step 9: Run the whole suite, lint, commit**

```bash
bin/rails test && bin/rubocop && bin/brakeman --no-pager
git add app/models test/models test/fixtures/tournament_standings.yml
git commit -m "Model an event's public standings sheet"
```

---

### Task 3: `TournamentStandingPolicy`

**Files:**
- Create: `app/policies/tournament_standing_policy.rb`,
  `test/policies/tournament_standing_policy_test.rb`

**Interfaces:**
- Consumes: `TournamentStanding` from Task 2.
- Produces: `TournamentStandingPolicy` answering `create?`, `new?`, `update?`, `edit?`,
  `destroy?`, `claim?`, `unclaim?`.

- [ ] **Step 1: Write the failing policy test**

`test/policies/tournament_standing_policy_test.rb`:

```ruby
require "test_helper"

class TournamentStandingPolicyTest < ActiveSupport::TestCase
  setup do
    @standing = tournament_standings(:ash_masters)
    @member = users(:two)   # did not create this row
    @author = users(:one)
    @admin = users(:one).tap { |u| u.update!(admin: true) }
  end

  # Wiki governance, decision 3 of the design: correcting a public record is not a property
  # question, so a member who typed nothing may still fix anything.
  test "any signed-in member may write any row" do
    policy = TournamentStandingPolicy.new(@member, @standing)

    assert_predicate policy, :create?
    assert_predicate policy, :new?
    assert_predicate policy, :update?
    assert_predicate policy, :edit?
    assert_predicate policy, :destroy?
    assert_predicate policy, :claim?
  end

  test "a visitor may write nothing" do
    policy = TournamentStandingPolicy.new(nil, @standing)

    refute_predicate policy, :create?
    refute_predicate policy, :update?
    refute_predicate policy, :destroy?
    refute_predicate policy, :claim?
    refute_predicate policy, :unclaim?
  end

  # The one owner-scoped rule: anybody may correct the public data on a row, but only the member
  # whose participation is linked may sever the link.
  test "only the member whose participation is linked may unclaim it" do
    @standing.update!(tournament_entry: tournament_entries(:one)) # users(:one)'s participation

    assert_predicate TournamentStandingPolicy.new(users(:one), @standing), :unclaim?
    refute_predicate TournamentStandingPolicy.new(users(:two), @standing), :unclaim?
  end

  test "an unlinked row cannot be unclaimed by anybody" do
    assert_nil @standing.tournament_entry_id

    refute_predicate TournamentStandingPolicy.new(users(:one), @standing), :unclaim?
    refute_predicate TournamentStandingPolicy.new(users(:two), @standing), :unclaim?
  end

  # Unlike TournamentPolicy, this policy reads no admin?: there is no moderation question here a
  # member cannot already answer, since every member can already edit every row. And a
  # participation stays its owner's, exactly as TournamentEntryPolicy has it.
  test "an admin gains nothing a member does not have" do
    @standing.update!(tournament_entry: tournament_entries(:two)) # users(:two)'s participation
    admin = users(:one)
    admin.update!(admin: true)

    refute_predicate TournamentStandingPolicy.new(admin, @standing), :unclaim?
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bin/rails test test/policies/tournament_standing_policy_test.rb
```

Expected: FAIL with `uninitialized constant TournamentStandingPolicy`.

- [ ] **Step 3: Write the policy**

`app/policies/tournament_standing_policy.rb`:

```ruby
# Wiki governance: any signed-in member may add, correct or delete any row of an event's
# standings sheet, because the sheet is the event's public record and not anybody's property.
#
# This policy grants an admin nothing beyond a member, unlike TournamentPolicy: there is no
# moderation question here that a member cannot already answer, since every member can already
# edit every row. And the one thing that *is* somebody's own — their participation — is guarded
# by #unclaim below, exactly as TournamentEntryPolicy guards an entry.
class TournamentStandingPolicy < ApplicationPolicy
  def create? = user.present?
  def new? = create?
  def update? = user.present?
  def edit? = update?
  def destroy? = user.present?

  # Which entry may be claimed is enforced by the controller's scoped lookup
  # (current_user.tournament_entries), not here: the policy is handed the standing, and the entry
  # arrives as a parameter it never sees.
  def claim? = user.present?

  # The one owner-scoped rule. Anybody may correct the public data on a row; only the member whose
  # participation is linked may sever the link — and an unlinked row can be unclaimed by nobody.
  def unclaim? = user.present? && record.tournament_entry&.user_id == user.id
end
```

- [ ] **Step 4: Run it to verify it passes**

```bash
bin/rails test test/policies/tournament_standing_policy_test.rb
```

Expected: PASS.

- [ ] **Step 5: Sabotage-verify**

Change `unclaim?` to `user.present?` and confirm two tests go red. Restore.

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop && git add app/policies test/policies
git commit -m "Say who may write a standing: any member, except the claim link"
```

---

### Task 4: The standings table on the event page

**Files:**
- Create: `app/views/components/tournaments/standings/row.rb`,
  `app/views/components/tournaments/standings/table.rb`
- Modify: `config/routes.rb`, `app/views/components/tournaments/show_view.rb`,
  `app/views/tournaments/show.html.erb`, `app/controllers/tournaments_controller.rb`,
  `app/views/components/ui/importing_list.rb`, `app/assets/stylesheets/application.css`
- Test: `test/controllers/tournaments_controller_test.rb`

**Interfaces:**
- Consumes: `TournamentStanding` (Task 2), `TournamentStandingPolicy` (Task 3),
  `Ui::ArchetypeBadge`, `Ui::AdminActions`, `Ui::ImportingList`.
- Produces:
  - `Tournaments::Standings::Row::COLUMNS → ["#", "Player", "Archetype", "Record", "List", ""]`
  - `Tournaments::Standings::Row.dom_id(standing) → "standing-<id>"`
  - `Tournaments::Standings::Row.new(standing:, viewer: nil, can_edit: false, claimable_entries: [])`
  - `Tournaments::Standings::Table.new(standings:, viewer: nil, can_edit: false, claimable_entries: [])`
  - `Ui::ImportingList.new(..., list_id: "importing-decks")`
  - `TournamentsController#show` assigns `@standings`, `@pending_standing_imports`,
    `@claimable_entries`
- Note: the Edit/Delete/claim controls this task renders point at routes that do not exist until
  Task 6. **Render them behind `can_edit`, which this task passes as `false`**, and turn it on in
  Task 6. The claim buttons likewise: pass `claimable_entries: []` here.

- [ ] **Step 1: Write the failing controller tests**

Append to `test/controllers/tournaments_controller_test.rb`:

```ruby
  test "show renders the event's standings, grouped by division and ranked" do
    get tournament_path(@tournament)

    assert_response :success
    assert_select "h3", text: "Masters"
    assert_select ".data-table-row", text: /Giovanni/
    assert_select ".data-table-row", text: /Ash Ketchum/
    # Ranked before unranked, and 7th before 33rd within the division.
    players = css_select(".tournament-standings .data-table-row").map(&:text)
    assert players.index { |row| row.include?("Giovanni") } <
           players.index { |row| row.include?("Ash Ketchum") },
      "expected the better placement first"
  end

  test "a standing's row names its archetype and its record" do
    get tournament_path(@tournament)

    assert_select ".data-table-row", text: /Giovanni/ do
      assert_select ".badge", text: archetypes(:budew_ogerpon).name
      assert_select ".data-table-cell", text: "7-2-0"
      assert_select ".data-table-cell", text: "#7"
    end
  end

  test "a standing with a field list links to it, and one without says so" do
    tournament_standings(:ash_masters).update!(deck: decks(:field_list))

    get tournament_path(@tournament)

    assert_select ".data-table-row", text: /Ash Ketchum/ do
      assert_select "a[href=?]", deck_path(decks(:field_list)), text: "Decklist"
    end
    assert_select ".data-table-row", text: /Giovanni/ do
      assert_select "a", text: "Decklist", count: 0
    end
  end

  test "an event with no standings says so with a class the stylesheet defines" do
    @tournament.standings.destroy_all

    get tournament_path(@tournament)

    assert_select "p.empty-state", text: "No standings recorded for this event yet."
  end

  test "the row of the reader's own linked participation is marked as theirs" do
    tournament_standings(:ash_masters).update!(tournament_entry: tournament_entries(:one))

    get tournament_path(@tournament)

    assert_select ".data-table-row", text: /Ash Ketchum/ do
      assert_select ".badge", text: "You"
    end
  end

  test "a visitor sees the sheet and no ownership marker on it" do
    tournament_standings(:ash_masters).update!(tournament_entry: tournament_entries(:one))
    sign_out @user

    get tournament_path(@tournament)

    assert_response :success
    assert_select ".data-table-row", text: /Ash Ketchum/
    assert_select ".badge", text: "You", count: 0
  end

  # Ui::ArchetypeBadge reads the archetype's cards and the "You" marker reads the linked entry's
  # user_id, so both belong in the includes. Modelled on the four tests that already guard
  # with_standard_pool.
  test "show issues a constant number of queries regardless of how many standings" do
    2.times { |i| record_standing(i) }

    get tournament_path(@tournament) # warm the session

    small = count_queries { get tournament_path(@tournament) }

    (2..7).each { |i| record_standing(i) }

    large = count_queries { get tournament_path(@tournament) }

    assert_response :success
    assert_equal small, large, "query count grew with the sheet: #{small} -> #{large}"
  end
```

and, in that file's `private` section:

```ruby
  # An archetype of its own per row, so two rows never issue identical SQL that the per-request
  # query cache would serve — which is what hides an N+1 from count_queries.
  def record_standing(index)
    card = Card.create!(
      name: "Quiet Pokémon #{index}", set_name: "QS#{index}", set_number: "1",
      card_type: "Pokémon", hp: 60, rarity: "Common"
    )
    archetype = Archetype.create!(primary_card: card, name: "Quiet #{index}", custom_name: "1")
    @tournament.standings.create!(
      player_name: "Quiet Player #{index}", division: "masters",
      placement: 100 + index, archetype: archetype
    )
  end
```

- [ ] **Step 2: Run them to verify they fail**

```bash
bin/rails test test/controllers/tournaments_controller_test.rb
```

Expected: FAIL — no `h3` "Masters", no `.tournament-standings` rows, no empty state.

- [ ] **Step 3: Add the standings routes**

> **Preflight ruling 2 applied:** these routes were originally declared in Task 6. They belong
> here, because `Row#claim_or_unclaim` emits `unclaim_tournament_standing_path` for the reader's
> own claimed row and one of this task's tests exercises that branch. Rails defines routes
> pointing at a controller that does not exist yet without complaint — only a *request* to them
> raises, and this task makes none. Task 6 writes the controller behind them; Task 7 writes the
> two member actions.

In `config/routes.rb`, inside `resources :tournaments do … end`, after the `entries` block:

```ruby
    # `resources :standings`, not `:tournament_standings`: the URL reads
    # /tournaments/:tournament_id/standings/:id, the same call the entries block makes — and with
    # the same cost, that polymorphic form_with cannot derive the path from the TournamentStanding
    # class name, so the standings form passes an explicit `url:`.
    #
    # No show and no index: the sheet lives inside tournaments#show, and a row is six fields —
    # the call Admin::StandardPoolsController makes for a five-field pool.
    #
    # These routes leave the app-wide `authenticate :user` block by nesting alone, exactly as
    # entries do. Tournaments::StandingsController keeps authenticate_user! as its only gate.
    resources :standings, only: %i[new create edit update destroy],
              controller: "tournaments/standings" do
      member do
        post :claim
        delete :unclaim
      end
    end
```

- [ ] **Step 4: Write `Tournaments::Standings::Row`**

`app/views/components/tournaments/standings/row.rb`:

```ruby
module Tournaments
  module Standings
    # One line of the sheet — and the unit a finished field-list import replaces over Turbo
    # Streams, which is why it renders its own `.data-table-row` instead of taking Ui::DataTable's
    # yielded builder: a row that only exists inside that block could not be rendered alone.
    # COLUMNS is shared with Table so the header and these cells' data-labels cannot drift.
    class Row < ApplicationComponent
      COLUMNS = [ "#", "Player", "Archetype", "Record", "List", "" ].freeze

      def self.dom_id(standing) = "standing-#{standing.id}"

      def initialize(standing:, viewer: nil, can_edit: false, claimable_entries: [])
        @standing = standing
        @viewer = viewer
        @can_edit = can_edit
        @claimable_entries = claimable_entries
      end

      def view_template
        div(class: "data-table-row", id: self.class.dom_id(@standing)) do
          cell(0) { @standing.placement ? "##{@standing.placement}" : "—" }
          cell(1) do
            plain @standing.player_name
            # The badge, not a sentence: the cell is narrow and the marker only has to be
            # recognisable to the one reader it applies to.
            span(class: "badge badge-archetype") { "You" } if mine?
          end
          cell(2) { render Ui::ArchetypeBadge.new(archetype: @standing.archetype) }
          cell(3) { @standing.record_label || "—" }
          cell(4) { list_link }
          cell(5) { actions }
        end
      end

      private

      # Ui::DataTable's own #cell writes the data-label from the column it is on; this row keeps
      # its own version because it renders outside that component. The index, not the label, so a
      # renamed column changes in one place.
      def cell(index, &block)
        div(class: "data-table-cell", data: { label: COLUMNS[index] }, &block)
      end

      # Reads the loaded association: TournamentsController#show preloads :tournament_entry
      # precisely for this, and a nil viewer is a visitor, who owns nothing.
      def mine? = @viewer.present? && @standing.tournament_entry&.user_id == @viewer.id

      def list_link
        return plain "—" if @standing.deck.nil?

        link_to "Decklist", deck_path(@standing.deck)
      end

      def actions
        claim_or_unclaim
        return unless @can_edit

        render Ui::AdminActions.new(
          edit_path: edit_tournament_standing_path(@standing.tournament_id, @standing),
          delete_path: tournament_standing_path(@standing.tournament_id, @standing),
          confirm_message: "Delete #{@standing.player_name}'s standing?"
        )
      end

      # Plural on purpose. Entry uniqueness is per Play! Pokémon profile, so a parent tracking
      # their own and their child's profiles legitimately has two participations at one event —
      # every reader of that rule has to be plural, and one button per claimable participation is
      # what stops the second one being unreachable.
      def claim_or_unclaim
        if mine?
          button_to "Unlink", unclaim_tournament_standing_path(@standing.tournament_id, @standing),
            method: :delete, class: "btn btn-secondary btn-sm"
        elsif @standing.tournament_entry_id.nil?
          @claimable_entries.each { |entry| claim_button(entry) }
        end
      end

      def claim_button(entry)
        button_to claim_label(entry),
          claim_tournament_standing_path(@standing.tournament_id, @standing,
            tournament_entry_id: entry.id),
          method: :post, class: "btn btn-secondary btn-sm"
      end

      def claim_label(entry)
        return "This is me" if @claimable_entries.one?

        name = entry.tournament_profile&.player_name
        name ? "This is #{name}" : "This is me (no profile)"
      end
    end
  end
end
```

- [ ] **Step 5: Write `Tournaments::Standings::Table`**

`app/views/components/tournaments/standings/table.rb`:

```ruby
module Tournaments
  module Standings
    # The event's field, grouped by age division and read in the order Play! Pokémon lists them —
    # junior, senior, masters. That is TournamentStanding::DIVISIONS' own order, and it is not the
    # alphabetical one a plain SQL sort on the column gives.
    class Table < ApplicationComponent
      def initialize(standings:, viewer: nil, can_edit: false, claimable_entries: [])
        @standings = standings
        @viewer = viewer
        @can_edit = can_edit
        @claimable_entries = claimable_entries
      end

      def view_template
        grouped = @standings.group_by(&:division)

        TournamentStanding::DIVISIONS.each do |division|
          rows = grouped[division]
          next if rows.blank?

          h3 { division.capitalize }
          division_table(rows)
        end
      end

      private

      # The wrapper is spelled out rather than delegated to Ui::DataTable because each row is its
      # own component — see Row's comment. The two halves of that component are four lines, and
      # this is the price of a broadcastable row.
      def division_table(rows)
        div(class: "data-table") do
          div(class: "data-table-header") do
            Row::COLUMNS.each { |column| div(class: "data-table-cell") { column } }
          end
          div(class: "data-table-body") do
            rows.each do |standing|
              render Row.new(
                standing: standing, viewer: @viewer,
                can_edit: @can_edit, claimable_entries: @claimable_entries
              )
            end
          end
        end
      end
    end
  end
end
```

- [ ] **Step 6: Give `Ui::ImportingList` its own DOM id**

In `app/views/components/ui/importing_list.rb`, replace the constructor and the `ul` id:

```ruby
    # list_id, because the id is a DOM id and two lists on one page must not share one: the
    # event page renders a standings list beside the deck grid's own vocabulary.
    def initialize(pending_imports: [], item_id_prefix: "importing", list_target: nil,
                   extra_data: {}, list_id: "importing-decks")
      @pending_imports = pending_imports
      @item_id_prefix = item_id_prefix
      @list_target = list_target
      @extra_data = extra_data
      @list_id = list_id
    end
```

and in `view_template`, `id: "importing-decks"` becomes `id: @list_id`.

- [ ] **Step 7: Render the section from `Tournaments::ShowView`**

In `app/views/components/tournaments/show_view.rb`, extend the constructor and call the new
section:

```ruby
    def initialize(tournament:, my_entries: [], standings: [], can_record: false,
                   can_record_another: false, can_edit: false, can_edit_standings: false,
                   viewer: nil, pending_standing_imports: [], claimable_entries: [])
      @tournament = tournament
      @my_entries = my_entries
      @standings = standings
      @can_record = can_record
      @can_record_another = can_record_another
      @can_edit = can_edit
      @can_edit_standings = can_edit_standings
      @viewer = viewer
      @pending_standing_imports = pending_standing_imports
      @claimable_entries = claimable_entries
    end
```

In `view_template`, after `render Tournaments::EventDetails.new(tournament: @tournament)`, add
`standings_section`, and add these private methods:

```ruby
    # The event's public sheet. Public by the same rule the page is: the catalog does not hide an
    # event, so it does not hide what was played there either. Only the write controls are gated.
    def standings_section
      div(class: "tournament-standings") do
        div(class: "admin-header") do
          h2 { "Standings" }
          if @can_edit_standings
            link_to "Add a standing", new_tournament_standing_path(@tournament),
              class: "btn btn-primary btn-sm"
          end
        end

        # The pending state, in Ui::ImportingList's own vocabulary: the item id is
        # importing-<import id>, which is exactly what the import job removes by target when the
        # field list lands.
        render Ui::ImportingList.new(
          pending_imports: @pending_standing_imports,
          item_id_prefix: "importing",
          list_id: "importing-standings"
        )

        if @standings.any?
          render Tournaments::Standings::Table.new(
            standings: @standings, viewer: @viewer,
            can_edit: @can_edit_standings, claimable_entries: @claimable_entries
          )
        else
          p(class: "empty-state") { "No standings recorded for this event yet." }
        end
      end
    end
```

- [ ] **Step 8: Load them in the controller**

In `app/controllers/tournaments_controller.rb#show`:

```ruby
  def show
    authorize @tournament
    @my_entries = my_entries
    @can_record_another = unrecorded_profile?
    # The preload the table actually reads: Ui::ArchetypeBadge reads the archetype's lead card
    # (and the parent, for a sub-archetype's name), and the "You" marker reads the linked entry's
    # user_id. A flat-cost test guards it, like the four that already guard with_standard_pool.
    @standings = @tournament.standings.as_a_sheet
      .includes(:deck, :tournament_entry, archetype: %i[primary_card secondary_card parent]).to_a
    @pending_standing_imports = pending_standing_imports
    @claimable_entries = claimable_entries
  end
```

and, in `private`:

```ruby
  # Field-list imports the reader has in flight. Empty for a visitor, and never queried for one.
  def pending_standing_imports
    return [] if current_user.nil?

    current_user.imports.pending.where(kind: "standing_list").to_a
  end

  # The reader's own participations at this event that no standing names yet — one claim button
  # each. Plural for the reason my_entries is: entry uniqueness is per profile.
  def claimable_entries
    return [] if current_user.nil?

    @my_entries.reject(&:standing)
  end
```

and add `:standing` to `my_entries`' preloads so `reject(&:standing)` costs nothing:

```ruby
    current_user.tournament_entries.where(tournament: @tournament)
      .includes(:tournament_profile, :standing).order(:id).to_a
```

- [ ] **Step 9: Pass the new keywords from the ERB wrapper**

`app/views/tournaments/show.html.erb`:

```erb
<%= render Tournaments::ShowView.new(tournament: @tournament, my_entries: @my_entries,
                                     standings: @standings,
                                     can_record: policy(Tournament).create?,
                                     can_record_another: @can_record_another,
                                     can_edit: policy(@tournament).edit?,
                                     can_edit_standings: false,
                                     viewer: current_user,
                                     pending_standing_imports: @pending_standing_imports,
                                     claimable_entries: []) %>
```

`can_edit_standings` and `claimable_entries` are wired to the policy in Task 6, once the routes
they point at exist.

- [ ] **Step 10: Add the one CSS rule**

Append to `app/assets/stylesheets/application.css`, beside `.tournaments-search`:

```css
/* The standings sheet sits under the event's own facts. One rule and nothing more: the table,
   the badges and the buttons inside it are the app's existing components. */
.tournament-standings { margin-top: 1.5rem; }
.tournament-standings h3 { margin: 1rem 0 0.5rem; }
```

- [ ] **Step 11: Run the tests to verify they pass**

```bash
bin/rails test test/controllers/tournaments_controller_test.rb
```

Expected: PASS.

- [ ] **Step 12: Sabotage-verify the flat-cost test**

Drop `:tournament_entry` from `#show`'s `includes` and re-run the flat-cost test.

Expected: FAIL with a growing query count. Restore.

- [ ] **Step 13: Run the whole suite, lint, commit**

```bash
bin/rails test && bin/rubocop && bin/brakeman --no-pager
git add config/routes.rb app/views app/controllers/tournaments_controller.rb \
  app/assets/stylesheets/application.css test/controllers/tournaments_controller_test.rb
git commit -m "Show an event's field on its own page"
```

---

### Task 5: Extract `Ui::ArchetypePicker` from `Decks::ArchetypeField`

**Files:**
- Create: `app/views/components/ui/archetype_picker.rb`
- Delete: `app/views/components/decks/archetype_field.rb`
- Modify: `app/views/components/decks/classification_fields.rb:20`
- Test: `test/controllers/decks_controller_test.rb`, `test/system/archetype_any_card_test.rb`
  (must stay green unchanged)

**Interfaces:**
- Consumes: `Ui::CardSelect`, `Ui::FormGroup`, `archetype_picker_controller.js`.
- Produces: `Ui::ArchetypePicker.new(form:, selected: nil, deck_key: nil, field_id: "deck_archetype")`.
  The Suggest button renders only when `deck_key` is present.

**Verified, no change needed:** `archetype_picker_controller.js` declares
`static values = { deckKey: String }`, so a missing value is `""`, and `suggest()` opens with
`if (!this.deckKeyValue) return`. The controller already connects and works without a deck. Do
not edit the JS; assert the fact instead (Step 1).

- [ ] **Step 1: Write the failing test for the deck-less picker**

Append to `test/controllers/decks_controller_test.rb`:

```ruby
  # The picker was soldered to a deck: it read @deck.key for the Suggest button and
  # @deck.archetype&.name for the input's value. A standings row has an archetype and no deck, and
  # a degraded copy of this picker was the alternative to extracting it.
  test "the archetype picker renders without a deck, minus the Suggest button" do
    # Rendered through a form for a record that is not a Deck, which is the whole point.
    html = ApplicationController.render(
      inline: <<~ERB,
        <%= form_with(model: TournamentStanding.new, url: "/nowhere") do |f| %>
          <%= render Ui::ArchetypePicker.new(form: f) %>
        <% end %>
      ERB
      layout: false
    )

    assert_includes html, "data-controller=\"archetype-picker\""
    assert_includes html, "archetype-picker-target=\"input\""
    refute_includes html, ">Suggest<"
    # Never a stale deck key: the Suggest handler is the only reader, and it must see nothing.
    refute_includes html, "archetype-picker-deck-key-value"
  end

  test "the archetype picker keeps its Suggest button when given a deck key" do
    html = ApplicationController.render(
      inline: <<~ERB,
        <%= form_with(model: Deck.new, url: "/nowhere") do |f| %>
          <%= render Ui::ArchetypePicker.new(form: f, deck_key: "abc123") %>
        <% end %>
      ERB
      layout: false
    )

    assert_includes html, ">Suggest<"
    assert_includes html, "archetype-picker-deck-key-value=\"abc123\""
  end
```

- [ ] **Step 2: Run it to verify it fails**

```bash
bin/rails test test/controllers/decks_controller_test.rb -n "/archetype picker/"
```

Expected: FAIL with `uninitialized constant Ui::ArchetypePicker`.

- [ ] **Step 3: Write the component**

`app/views/components/ui/archetype_picker.rb`, a move of
`app/views/components/decks/archetype_field.rb` with the deck made optional:

```ruby
module Ui
  # The archetype picker: search an existing archetype, create one inline, or — given a deck —
  # let "Suggest" infer one from its line-up. Backed by the `archetype-picker` Stimulus controller
  # and the `/api/archetypes` + `/api/decks/:key/suggested_archetype` endpoints.
  #
  # Lives under Ui:: because both the deck form and the tournament standings form render it. It
  # used to be Decks::ArchetypeField, soldered to a deck: it read @deck.key for the Suggest button
  # and @deck.archetype&.name for the input's value. A standings row has an archetype and no deck,
  # and a degraded copy of this picker was the alternative.
  #
  # `deck_key:` nil renders no Suggest button — the only thing here a deck is needed for. The
  # controller still connects: deckKey is a String value, so Stimulus defaults it to "", and
  # #suggest returns early on it.
  class ArchetypePicker < ApplicationComponent
    def initialize(form:, selected: nil, deck_key: nil, field_id: "deck_archetype")
      @form = form
      @selected = selected
      @deck_key = deck_key
      @field_id = field_id
    end

    def view_template
      div(
        class: "deck-archetype-field",
        data: { controller: "archetype-picker", archetype_picker_deck_key_value: @deck_key }
      ) do
        render Ui::FormGroup.new(label: "Archetype", field_name: @field_id) do
          @form.hidden_field :archetype_id, data: { archetype_picker_target: "archetypeId" }
          search_row
          div(class: "archetype-search-results", data: { archetype_picker_target: "results" })
        end
        create_section
      end
    end

    private

    def search_row
      div(class: "archetype-field-search") do
        input(
          type: "text",
          id: @field_id,
          class: "form-input",
          placeholder: "Search archetype…",
          value: @selected&.name,
          data: { archetype_picker_target: "input", action: "input->archetype-picker#search" }
        )
        suggest_button if @deck_key
      end
    end

    # Only reachable with a deck: it asks /api/decks/:key/suggested_archetype what the deck's
    # line-up looks like, and a standings row has no line-up to ask about. This replaces the old
    # component's `if @deck.persisted?`, which asked the same question about the wrong object.
    def suggest_button
      button(type: "button", class: "btn btn-secondary btn-sm",
             data: { action: "archetype-picker#suggest" }) { "Suggest" }
    end

    def create_section
      div(class: "create-archetype-section", style: "display: none;",
          data: { archetype_picker_target: "createSection" }) do
        p(class: "form-label", style: "font-weight: 600; margin-bottom: 0.5rem;") { "New archetype" }
        card_search_group(label_text: "Primary card", target: "primary")
        card_search_group(label_text: "Secondary card (optional)", target: "secondary")
        div(class: "form-actions") do
          button(type: "button", class: "btn btn-primary btn-sm",
            data: { action: "archetype-picker#createArchetype",
                    archetype_picker_target: "createButton" }) { "Create & select" }
          button(type: "button", class: "btn btn-secondary btn-sm",
            data: { action: "archetype-picker#cancelCreate" }) { "Cancel" }
        end
      end
    end

    def card_search_group(label_text:, target:)
      render Ui::CardSelect.new(
        label: label_text,
        hidden_data:  { archetype_picker_target: "#{target}Id" },
        input_data:   { archetype_picker_target: "#{target}Input",
                        action: "input->archetype-picker#search#{target.capitalize}" },
        results_data: { archetype_picker_target: "#{target}Results" }
      )
    end
  end
end
```

- [ ] **Step 4: Switch the deck form to the new component and delete the old one**

`app/views/components/decks/classification_fields.rb:20`:

```ruby
        render Ui::ArchetypePicker.new(
          form: @form, selected: @deck.archetype,
          # nil on an unsaved deck: /api/decks/:key/suggested_archetype needs a persisted deck to
          # read a line-up from, which is the condition the old component spelled as
          # `if @deck.persisted?`.
          deck_key: (@deck.key if @deck.persisted?)
        )
```

```bash
git rm app/views/components/decks/archetype_field.rb
grep -rn "ArchetypeField" app/ test/   # must return nothing
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
bin/rails test test/controllers/decks_controller_test.rb
bin/rails test:system TEST=test/system/archetype_any_card_test.rb
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system TEST=test/system/archetype_any_card_test.rb
```

Expected: PASS. The three existing picker system tests address the picker through
`[data-archetype-picker-target='…']` and `.archetype-search-item`, all of which the move
preserves byte for byte — if any of them fails, the markup drifted and the component is wrong,
not the test.

- [ ] **Step 6: Lint and commit**

```bash
bin/rubocop && git add -A app/views test/controllers/decks_controller_test.rb
git commit -m "Make the archetype picker usable without a deck"
```

---

### Task 6: `Tournaments::StandingsController` and its form

**Files:**
- Create: `app/controllers/tournaments/standings_controller.rb`,
  `app/views/components/tournaments/standings/form.rb`,
  `app/views/components/tournaments/standings/new_view.rb`,
  `app/views/components/tournaments/standings/edit_view.rb`,
  `app/views/tournaments/standings/new.html.erb`,
  `app/views/tournaments/standings/edit.html.erb`,
  `test/controllers/tournaments/standings_controller_test.rb`
- Modify: `app/views/tournaments/show.html.erb`,
  `test/controllers/public_access_test.rb`

**Interfaces:**
- Consumes: `TournamentStanding` (Task 2), `TournamentStandingPolicy` (Task 3),
  `Tournaments::Standings::Table` (Task 4), `Ui::ArchetypePicker` (Task 5).
- Produces: the routes `new_tournament_standing_path`, `tournament_standings_path`,
  `edit_tournament_standing_path`, `tournament_standing_path`. (`claim`/`unclaim` land in
  Task 7 — declare them in this task's route block so Task 4's buttons resolve, and implement
  the two actions in Task 7.)
- Produces: `Tournaments::Standings::Form.new(tournament:, standing:, existing: nil, entry: nil)`.

- [ ] **Step 1: Write the failing controller tests**

`test/controllers/tournaments/standings_controller_test.rb`:

```ruby
require "test_helper"

class Tournaments::StandingsControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @tournament = tournaments(:one)
    @standing = tournament_standings(:giovanni_masters) # created_by users(:two)
    sign_in @user
  end

  test "a member records a standing on an event they did not catalogue" do
    sign_in users(:two) # tournaments(:one) was catalogued by users(:one)

    assert_difference -> { TournamentStanding.count }, 1 do
      post tournament_standings_path(@tournament), params: { tournament_standing: {
        player_name: "Brock", division: "masters", placement: 4,
        wins: 6, losses: 2, ties: 1, archetype_id: archetypes(:ogerpon).id
      } }
    end

    assert_redirected_to tournament_path(@tournament)
    standing = TournamentStanding.order(:id).last
    assert_equal "Brock", standing.player_name
    assert_equal "brock", standing.player_name_normalized
    assert_equal users(:two), standing.created_by
  end

  # Wiki governance, decision 3: correcting a public record is not a property question.
  test "a member may edit and delete a row another member typed" do
    patch tournament_standing_path(@tournament, @standing),
      params: { tournament_standing: { placement: 3 } }

    assert_redirected_to tournament_path(@tournament)
    assert_equal 3, @standing.reload.placement

    assert_difference -> { TournamentStanding.count }, -1 do
      delete tournament_standing_path(@tournament, @standing)
    end
  end

  test "a row belonging to another event 404s rather than rendering under this header" do
    get edit_tournament_standing_path(tournaments(:two), @standing)

    assert_response :not_found
  end

  # Without this, the wiki edit form would let any member attach their own participation to a row
  # naming somebody else, or detach yours. The link is written only by claim/unclaim.
  test "tournament_entry_id is not mass-assignable" do
    patch tournament_standing_path(@tournament, @standing), params: { tournament_standing: {
      placement: 5, tournament_entry_id: tournament_entries(:one).id
    } }

    assert_redirected_to tournament_path(@tournament)
    assert_equal 5, @standing.reload.placement
    assert_nil @standing.tournament_entry_id
  end

  test "the uniqueness error renders a link to the clashing row" do
    assert_no_difference -> { TournamentStanding.count } do
      post tournament_standings_path(@tournament), params: { tournament_standing: {
        player_name: "  GIOVANNI  ", division: "masters", archetype_id: archetypes(:ogerpon).id
      } }
    end

    assert_response :unprocessable_entity
    assert_select ".form-hint", text: /already has a standing/
    assert_select ".form-hint a[href=?]", tournament_path(@tournament)
  end

  test "new prefills from the reader's own participation" do
    get new_tournament_standing_path(@tournament, tournament_entry_id: tournament_entries(:one).id)

    assert_response :success
    # tournament_profiles(:ash) was born in 2014, so the 2026 season puts them in juniors.
    assert_select "input[name=?][value=?]", "tournament_standing[player_name]", "Ash Ketchum"
    assert_select "select[name=?] option[selected][value=?]", "tournament_standing[division]", "junior"
    assert_select "input[name=?][value=?]", "tournament_standing[placement]", "33"
    # The hidden field is what carries the link through to #create, outside the permitted params.
    assert_select "input[type=hidden][name=tournament_entry_id][value=?]",
      tournament_entries(:one).id.to_s
  end

  test "prefilling from another member's participation 404s" do
    get new_tournament_standing_path(@tournament,
      tournament_entry_id: tournament_entries(:shared_event).id) # users(:two)'s

    assert_response :not_found
  end

  test "creating from a prefill links the participation" do
    post tournament_standings_path(@tournament), params: {
      tournament_entry_id: tournament_entries(:one).id,
      tournament_standing: {
        player_name: "Ash Ketchum", division: "junior",
        archetype_id: archetypes(:ogerpon).id
      }
    }

    assert_redirected_to tournament_path(@tournament)
    assert_equal tournament_entries(:one), TournamentStanding.order(:id).last.tournament_entry
  end

  test "a signed-out request is sent to sign in and writes nothing" do
    sign_out @user
    placement_was = @standing.placement

    post tournament_standings_path(@tournament), params: { tournament_standing: {
      player_name: "Brock", division: "masters", archetype_id: archetypes(:ogerpon).id
    } }
    assert_redirected_to new_user_session_path

    patch tournament_standing_path(@tournament, @standing),
      params: { tournament_standing: { placement: 1 } }
    assert_redirected_to new_user_session_path

    delete tournament_standing_path(@tournament, @standing)
    assert_redirected_to new_user_session_path

    assert_equal placement_was, @standing.reload.placement
    assert_equal 2, TournamentStanding.count
  end

  test "the event page offers the write controls to a member and none to a visitor" do
    get tournament_path(@tournament)
    assert_select "a[href=?]", new_tournament_standing_path(@tournament), text: "Add a standing"
    assert_select "a[href=?]", edit_tournament_standing_path(@tournament, @standing)

    sign_out @user
    get tournament_path(@tournament)
    assert_select "a[href=?]", new_tournament_standing_path(@tournament), count: 0
    assert_select "a[href=?]", edit_tournament_standing_path(@tournament, @standing), count: 0
  end
end
```

- [ ] **Step 2: Add the two write actions to `public_access_test.rb`**

In `test/controllers/public_access_test.rb`, extend the tournament-writes test — add to the body
of `"the tournament and participation writes send a visitor to sign in"`:

```ruby
    standing = tournament_standings(:ash_masters)
    standing_placement_was = standing.placement

    post tournament_standings_path(tournaments(:one)), params: { tournament_standing: {
      player_name: "x", division: "masters", archetype_id: archetypes(:ogerpon).id
    } }
    assert_redirected_to new_user_session_path

    patch tournament_standing_path(tournaments(:one), standing),
      params: { tournament_standing: { placement: 1 } }
    assert_redirected_to new_user_session_path

    delete tournament_standing_path(tournaments(:one), standing)
    assert_redirected_to new_user_session_path

    assert_equal standing_placement_was, standing.reload.placement
    assert_equal 2, TournamentStanding.count
```

and add to `owner_only_gets`:

```ruby
      # Like the three entry rows, these cannot catch a missing `authorize`:
      # Tournaments::StandingsController does not include PubliclyReachable and therefore has no
      # verify_authorized (deliberately — see CLAUDE.md). Worth having as a smoke test.
      "new tournament standing" => new_tournament_standing_path(tournaments(:one)),
      "edit tournament standing" =>
        edit_tournament_standing_path(tournaments(:one), tournament_standings(:ash_masters))
```

- [ ] **Step 3: Run them to verify they fail**

```bash
bin/rails test test/controllers/tournaments test/controllers/public_access_test.rb
```

Expected: FAIL. The routes exist (Task 4, preflight ruling 2) but nothing is behind them, so the
failure is `uninitialized constant Tournaments::StandingsController` — not a missing route
helper.

- [ ] **Step 4: Write the controller**

`app/controllers/tournaments/standings_controller.rb`:

```ruby
module Tournaments
  # One line of an event's public standings sheet. Wiki-governed: every write is open to any
  # signed-in member, so there is no owner scope on the *standing* — but the *participation* a row
  # is linked to is always looked up through current_user.tournament_entries, so a stranger's
  # entry is a RecordNotFound rather than a policy question.
  #
  # These routes leave the app-wide `authenticate :user` block by nesting under `tournaments`
  # alone. This controller therefore does NOT include PubliclyReachable: it keeps
  # authenticate_user! as its only gate and calls authorize in every action — the same deliberate
  # exception Tournaments::EntriesController and DeckResultsController are, with the same
  # consequence that nothing enforces the authorize call being present, which is what
  # test/controllers/public_access_test.rb covers per action.
  class StandingsController < ApplicationController
    before_action :set_tournament
    before_action :set_standing, only: %i[edit update destroy claim unclaim]

    # Preflight ruling 3. See #refuse_with_redirect below for why this controller carries its own
    # handler rather than leaning on a shared one.
    rescue_from Pundit::NotAuthorizedError, with: :refuse_with_redirect

    def new
      @entry = scoped_entry(params[:tournament_entry_id])
      @standing = @tournament.standings.build(prefill_attributes(@entry))
      authorize @standing, :create?
    end

    def create
      @standing = @tournament.standings.build(standing_params)
      authorize @standing, :create?
      @entry = scoped_entry(params[:tournament_entry_id])
      @standing.created_by = current_user
      @standing.tournament_entry = @entry

      if @standing.save
        redirect_to tournament_path(@tournament), notice: "Standing recorded."
      else
        @existing = existing_standing
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @standing
    end

    def update
      authorize @standing

      if @standing.update(standing_params)
        redirect_to tournament_path(@tournament), notice: "Standing updated."
      else
        @existing = existing_standing
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @standing
      @standing.destroy
      redirect_to tournament_path(@tournament), notice: "Standing deleted."
    end

    private

    def set_tournament
      # Unscoped: the event is public, and cataloguing its field is open to every member.
      @tournament = Tournament.with_standard_pool.find(params[:tournament_id])
    end

    # An event and its sheet are public — the event is *listed* at /tournaments — so a refusal
    # must say so and give the member somewhere to go, not answer with the deck rule's 404.
    # The same call TournamentsController#refuse_with_redirect makes, and this controller needs
    # its own: nothing outside PubliclyReachable rescues this exception, and the app's other
    # non-public controllers never reach a real Pundit refusal because their lookups are
    # user-scoped (every refusal there is already a RecordNotFound). Only #unclaim can refuse a
    # signed-in member here, and unrescued it would be a 500.
    #
    # params[:tournament_id] is always present: every route in this controller is nested.
    def refuse_with_redirect
      redirect_to tournament_path(params[:tournament_id]),
        alert: "Only the member whose participation is linked can unlink it."
    end

    def set_standing
      # Scoped by @tournament, not merely by id: a row belonging to another event must 404 rather
      # than render under this event's header — the reason Tournaments::EntriesController scopes
      # its entry by both.
      @standing = @tournament.standings.find(params[:id])
    end

    # A participation named by a request parameter, resolved through the reader's *own* entries at
    # *this* event, so a stranger's id is a RecordNotFound and never a policy question. nil when
    # no id was given, which is the ordinary "I am recording somebody else's row" case.
    def scoped_entry(id)
      return if id.blank?

      current_user.tournament_entries.find_by!(id: id, tournament_id: @tournament.id)
    end

    # Values *copied* from the reader's own participation, never derived from it: editing the
    # private record afterwards must not silently republish. The row is wiki-editable, so
    # correcting it is an ordinary edit — there is no resync mechanism, by design.
    #
    # The W-L-T is deliberately not prefilled: a participation records a placement and CP, not a
    # match record, and the reader's DeckResults are not the event's official line.
    def prefill_attributes(entry)
      return {} if entry.nil?

      profile = entry.tournament_profile
      {
        player_name: profile&.player_name,
        # A division is fixed for the whole season, so it is asked of the *event's* date rather
        # than of today — and #division answers with a Symbol the enum column will not take.
        division: profile&.division(on: @tournament.date)&.to_s,
        placement: entry.placement,
        archetype_id: entry.deck.archetype_id
      }.compact
    end

    # The row the failed save collided with, so the form can link to it and offer to claim it
    # instead of merely refusing — what TournamentsController#create does for a duplicate event.
    # nil unless the failure really was the uniqueness rule.
    def existing_standing
      return if @standing.errors[:player_name].none?

      @tournament.standings.find_by(
        player_name_normalized: @standing.player_name_normalized, division: @standing.division
      )
    end

    # tournament_entry_id is deliberately absent. Permitting it would let any member attach their
    # own participation to a row naming somebody else, or detach yours: the link is written only
    # by #claim and #unclaim, from an id resolved through scoped_entry.
    def standing_params
      params.require(:tournament_standing).permit(
        :player_name, :division, :placement, :wins, :losses, :ties, :archetype_id
      )
    end
  end
end
```

- [ ] **Step 5: Write the form and the two page wrappers**

`app/views/components/tournaments/standings/form.rb`:

```ruby
module Tournaments
  module Standings
    # Shared by new and edit. The archetype comes from Ui::ArchetypePicker with no deck: a
    # standing names an archetype and has no line-up to suggest one from.
    class Form < ApplicationComponent
      def initialize(tournament:, standing:, existing: nil, entry: nil)
        @tournament = tournament
        @standing = standing
        @existing = existing
        @entry = entry
      end

      def view_template
        # An explicit url: — the route resource is `standings` while the model is
        # TournamentStanding, so polymorphic form_with would build
        # tournament_tournament_standings_path.
        form_with(model: @standing, url: form_url, class: "deck-form") do |f|
          render Ui::FormErrors.new(resource: @standing)
          clash_hint
          event_hint
          # Outside the tournament_standing hash on purpose: the link is not mass-assignable, and
          # the controller resolves this id through the reader's own participations.
          helpers.hidden_field_tag(:tournament_entry_id, @entry.id) if @entry

          render Ui::FormGroup.new do
            f.label :player_name, "Player name", class: "form-label"
            f.text_field :player_name, class: "form-input", autofocus: true,
              placeholder: "As it appears on the standings sheet"
          end

          render Ui::FormGroup.new do
            f.label :division, class: "form-label"
            f.select :division,
              TournamentStanding::DIVISIONS.map { |d| [ d.capitalize, d ] }, {}, class: "form-input"
          end

          render Ui::ArchetypePicker.new(form: f, selected: @standing.archetype)

          render Ui::FormGroup.new(hint: placement_hint) do
            f.label :placement, "Final placement", class: "form-label"
            f.number_field :placement, class: "form-input", min: 1
          end

          div(class: "form-row") do
            %i[wins losses ties].each do |field|
              render Ui::FormGroup.new do
                f.label field, class: "form-label"
                f.number_field field, class: "form-input", min: 0
              end
            end
          end

          div(class: "form-actions deck-form-actions") do
            f.submit class: "btn btn-primary"
            link_to "Cancel", tournament_path(@tournament), class: "btn btn-secondary"
          end
        end
      end

      private

      def form_url
        return tournament_standings_path(@tournament) unless @standing.persisted?

        tournament_standing_path(@tournament, @standing)
      end

      # Being blocked is useless without being told where to go — the other half of the
      # anti-duplicate mechanism, exactly as Tournaments::Form does it for a duplicate event. The
      # link goes to the event, where the row and its "This is me" button already are.
      def clash_hint
        return if @existing.nil?

        p(class: "form-hint") do
          plain "#{@existing.player_name} already has a standing in this division: "
          link_to "see the event's sheet", tournament_path(@tournament)
        end
      end

      # One is filling in a placement and needs to see in what. Read-only: the event's own fields
      # are edited from its fiche.
      def event_hint
        p(class: "form-hint") do
          plain "#{@tournament.name} — "
          plain localize(@tournament.date, format: :long)
        end
      end

      def placement_hint
        field = @tournament.participant_count_for(@standing.division)
        return "Optional — leave blank if nobody remembers the final standing." if field.blank?

        "The #{@standing.division} field at this event held #{field} players."
      end
    end
  end
end
```

`app/views/components/tournaments/standings/new_view.rb`:

```ruby
module Tournaments
  module Standings
    class NewView < ApplicationComponent
      def initialize(tournament:, standing:, existing: nil, entry: nil)
        @tournament = tournament
        @standing = standing
        @existing = existing
        @entry = entry
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Add a standing")
          render Tournaments::Standings::Form.new(
            tournament: @tournament, standing: @standing, existing: @existing, entry: @entry
          )
        end
      end
    end
  end
end
```

`app/views/components/tournaments/standings/edit_view.rb`:

```ruby
module Tournaments
  module Standings
    class EditView < ApplicationComponent
      def initialize(tournament:, standing:, existing: nil)
        @tournament = tournament
        @standing = standing
        @existing = existing
      end

      def view_template
        div(class: "admin-container") do
          render Ui::PageHeader.new(title: "Edit #{@standing.player_name}'s standing")
          render Tournaments::Standings::Form.new(
            tournament: @tournament, standing: @standing, existing: @existing
          )
        end
      end
    end
  end
end
```

No `entry:` here: the link is written by `#claim`/`#unclaim` alone, so an edit form has no
participation to carry through.

`app/views/tournaments/standings/new.html.erb`:

```erb
<%= render Tournaments::Standings::NewView.new(tournament: @tournament, standing: @standing,
                                               existing: @existing, entry: @entry) %>
```

`app/views/tournaments/standings/edit.html.erb`:

```erb
<%= render Tournaments::Standings::EditView.new(tournament: @tournament, standing: @standing,
                                                existing: @existing) %>
```

- [ ] **Step 6: Turn the event page's write controls on**

`app/views/tournaments/show.html.erb` — replace the two placeholders from Task 4:

```erb
                                     can_edit_standings: policy(TournamentStanding).create?,
                                     claimable_entries: @claimable_entries) %>
```

`policy(TournamentStanding).create?` and not `.update?`: the question the section header asks is
"may this reader add a row", and every write query answers `user.present?` today — reading it as
the edit question is what would make the "Add" button vanish the day one of them grows a
condition. (The same call `TournamentsController#show` makes with `policy(Tournament).create?`.)

- [ ] **Step 7: Add `.form-row` if the stylesheet has no rule for it**

```bash
grep -n "\.form-row" app/assets/stylesheets/application.css
```

If it returns nothing, append beside the standings rule from Task 4:

```css
/* The W-L-T triplet, three narrow fields on one line. Single-class specificity, like every
   other rule in this layer. */
.form-row { display: flex; gap: 0.75rem; }
.form-row .form-group { flex: 1; }
```

- [ ] **Step 8: Run the tests to verify they pass**

```bash
bin/rails test test/controllers/tournaments test/controllers/public_access_test.rb
```

Expected: PASS. `claim`/`unclaim` are routed but not yet implemented — Task 7. Task 4's Row only
renders those buttons when `claimable_entries` is non-empty or the row is the reader's own, so
the two tests above that exercise the sheet stay green.

- [ ] **Step 9: Sabotage-verify two tests**

```bash
# 1. Add :tournament_entry_id to standing_params → the mass-assignment test must fail.
# 2. Replace scoped_entry's current_user.tournament_entries with TournamentEntry
#    → "prefilling from another member's participation 404s" must fail.
bin/rails test test/controllers/tournaments/standings_controller_test.rb
```

Expected: one red test each; restore after each.

- [ ] **Step 10: Run the whole suite, lint, commit**

```bash
bin/rails test && bin/rubocop && bin/brakeman --no-pager
git add app/controllers/tournaments app/views \
  test/controllers/tournaments test/controllers/public_access_test.rb
git commit -m "Let any member write a row of an event's standings sheet"
```

---

### Task 7: Claiming and unclaiming a row

**Files:**
- Modify: `app/controllers/tournaments/standings_controller.rb`,
  `app/views/components/tournaments/show_view.rb`
- Test: `test/controllers/tournaments/standings_controller_test.rb`,
  `test/controllers/tournaments_controller_test.rb`,
  `test/controllers/public_access_test.rb`

**Interfaces:**
- Consumes: the `claim`/`unclaim` routes declared in Task 6, `TournamentStandingPolicy#claim?`
  and `#unclaim?` (Task 3), `@claimable_entries` (Task 4).
- Produces: `POST /tournaments/:tournament_id/standings/:id/claim?tournament_entry_id=…` and
  `DELETE …/unclaim`; a "Publish my participation" action per unpublished entry on the event page.

- [ ] **Step 1: Write the failing tests**

Append to `test/controllers/tournaments/standings_controller_test.rb`:

```ruby
  test "a member claims a row somebody else typed" do
    post claim_tournament_standing_path(@tournament, @standing,
      tournament_entry_id: tournament_entries(:one).id)

    assert_redirected_to tournament_path(@tournament)
    assert_equal tournament_entries(:one), @standing.reload.tournament_entry
  end

  test "claiming with another member's participation 404s and links nothing" do
    post claim_tournament_standing_path(@tournament, @standing,
      tournament_entry_id: tournament_entries(:shared_event).id) # users(:two)'s

    assert_response :not_found
    assert_nil @standing.reload.tournament_entry_id
  end

  test "claiming with a participation from another event 404s" do
    post claim_tournament_standing_path(@tournament, @standing,
      tournament_entry_id: tournament_entries(:two).id) # users(:two)'s, and another event

    assert_response :not_found
  end

  # The partial UNIQUE index on tournament_entry_id is what stops a member publishing themselves
  # twice under two spellings of their own name, which the player-name key cannot see.
  # Preflight ruling 4: if this does not raise through the request stack (Rails 8 test env uses
  # show_exceptions = :rescuable, and RecordNotUnique is not rescuable, so it should), move the
  # test to test/models/tournament_standing_test.rb and assert the raise on
  # standing.update!(tournament_entry: …) directly. The property under test is the partial UNIQUE
  # index — a database guarantee, not a controller behaviour.
  test "one participation may back only one row" do
    @standing.update!(tournament_entry: tournament_entries(:one))

    assert_raises ActiveRecord::RecordNotUnique do
      post claim_tournament_standing_path(@tournament, tournament_standings(:ash_masters),
        tournament_entry_id: tournament_entries(:one).id)
    end
  end

  test "the member whose participation is linked may sever the link" do
    @standing.update!(tournament_entry: tournament_entries(:one))

    delete unclaim_tournament_standing_path(@tournament, @standing)

    assert_redirected_to tournament_path(@tournament)
    assert_nil @standing.reload.tournament_entry_id
  end

  # The one owner-scoped rule in this controller: anybody may correct the public data on a row,
  # only its claimant may unlink it.
  test "another member may not sever somebody else's link" do
    @standing.update!(tournament_entry: tournament_entries(:one)) # users(:one)'s
    sign_in users(:two)

    delete unclaim_tournament_standing_path(@tournament, @standing)

    # A redirect with an alert, not a 403 and not a 404: an event and its sheet are public, so the
    # refusal has somewhere to send the member — the same answer TournamentsController gives a
    # member who may not edit an event. See the controller's own refuse_with_redirect.
    assert_redirected_to tournament_path(@tournament)
    assert_match(/can unlink it/, flash[:alert])
    assert_equal tournament_entries(:one), @standing.reload.tournament_entry
  end
```

Append to `test/controllers/tournaments_controller_test.rb`:

```ruby
  test "the event page offers to publish each participation no standing names yet" do
    get tournament_path(@tournament)

    assert_select "a[href=?]",
      new_tournament_standing_path(@tournament, tournament_entry_id: tournament_entries(:one).id),
      text: "Publish my participation"
  end

  test "a published participation is no longer offered for publishing" do
    tournament_standings(:ash_masters).update!(tournament_entry: tournament_entries(:one))

    get tournament_path(@tournament)

    assert_select "a[href*=?]", "tournament_entry_id=#{tournament_entries(:one).id}", count: 0
  end

  # Plural, for the reason my_entries is: entry uniqueness is per Play! Pokémon profile, so a
  # parent tracking two profiles has two participations here and both must be publishable.
  test "two unpublished participations are offered separately, named by their player" do
    second_entry_for_misty

    get tournament_path(@tournament)

    assert_select "a", text: /Publish Ash Ketchum's participation/
    assert_select "a", text: /Publish Misty's participation/
  end

  test "a visitor is offered nothing to publish" do
    sign_out @user

    get tournament_path(@tournament)

    assert_response :success
    assert_select "a", text: /Publish/, count: 0
  end
```

Append to the standings block of `public_access_test.rb`'s tournament-writes test:

```ruby
    post claim_tournament_standing_path(tournaments(:one), standing,
      tournament_entry_id: tournament_entries(:one).id)
    assert_redirected_to new_user_session_path

    delete unclaim_tournament_standing_path(tournaments(:one), standing)
    assert_redirected_to new_user_session_path

    assert_nil standing.reload.tournament_entry_id
```

- [ ] **Step 2: Run them to verify they fail**

```bash
bin/rails test test/controllers/tournaments test/controllers/public_access_test.rb
```

Expected: FAIL — `AbstractController::ActionNotFound` for `claim`, no "Publish" links.

- [ ] **Step 3: Implement the two actions**

In `app/controllers/tournaments/standings_controller.rb`, after `#destroy`:

```ruby
    # The act of a member saying "the row naming this player is me". It writes the link and
    # nothing else: the public data on the row stays whatever whoever typed it wrote, and
    # correcting it is an ordinary wiki edit.
    #
    # A player with no account cannot do this, and that is not a gap: claiming *is* a member
    # linking their own participation, which is the whole reason the two tables are separate.
    def claim
      authorize @standing, :claim?
      @standing.update!(tournament_entry: scoped_entry!(params[:tournament_entry_id]))
      redirect_to tournament_path(@tournament), notice: "Standing linked to your participation."
    end

    def unclaim
      authorize @standing, :unclaim?
      @standing.update!(tournament_entry: nil)
      redirect_to tournament_path(@tournament), notice: "Standing unlinked from your participation."
    end
```

and in `private`, beside `scoped_entry`:

```ruby
    # #claim's entry is mandatory — the whole action is "link this row to that participation" —
    # so a missing id is a RecordNotFound rather than a silent no-op that reports success.
    def scoped_entry!(id)
      current_user.tournament_entries.find_by!(id: id, tournament_id: @tournament.id)
    end
```

- [ ] **Step 4: Add the publish actions to the event page**

In `app/views/components/tournaments/show_view.rb`, inside `entry_action` and after the
per-entry links, call `publish_actions`, then add:

```ruby
    # One per participation the reader owns that no standing names yet. Guarded by the same
    # can_record as the buttons above, for the same reason: a visitor's my_entries is [] by
    # construction, so the loop is empty for them anyway — but the guard is what says the whole
    # block belongs to a reader who may write, rather than resting on that emptiness.
    def publish_actions
      @claimable_entries.each do |entry|
        link_to publish_label(entry),
          new_tournament_standing_path(@tournament, tournament_entry_id: entry.id),
          class: "btn btn-secondary"
      end
    end

    # One participation needs no disambiguation; two do, and the player name is the only thing
    # that tells them apart — the same rule entry_label follows.
    def publish_label(entry)
      return "Publish my participation" if @my_entries.one?

      name = entry.tournament_profile&.player_name
      name ? "Publish #{name}'s participation" : "Publish my participation (no profile)"
    end
```

- [ ] **Step 5: Run the tests to verify they pass**

```bash
bin/rails test test/controllers/tournaments test/controllers/public_access_test.rb
```

Expected: PASS. `TournamentsController`'s own `refuse_with_redirect` is declared on that
controller alone and is *not* inherited here — this controller carries its own, added in Task 6
by preflight ruling 3. If the refusal comes back as a 500, that handler is missing.

- [ ] **Step 6: Sabotage-verify**

Change `unclaim`'s `authorize @standing, :unclaim?` to `:update?` and confirm "another member may
not sever somebody else's link" goes red. Restore.

- [ ] **Step 7: Run the whole suite, lint, commit**

```bash
bin/rails test && bin/rubocop && bin/brakeman --no-pager
git add app/controllers/tournaments app/views/components/tournaments test/controllers
git commit -m "Link a member's own participation to the public row that names them"
```

---

### Task 8: Importing the field list as an ownerless deck

**Files:**
- Create: `app/jobs/tournaments/standing_list_import_job.rb`,
  `test/jobs/tournaments/standing_list_import_job_test.rb`
- Modify: `app/services/decks/fetcher.rb`, `app/models/import.rb`,
  `app/controllers/tournaments/standings_controller.rb`,
  `app/views/components/tournaments/standings/form.rb`,
  `app/controllers/admin/imports_controller.rb`
- Test: `test/services/decks/fetcher_test.rb`,
  `test/controllers/tournaments/standings_controller_test.rb`,
  `test/controllers/admin/imports_controller_test.rb`

**Interfaces:**
- Consumes: `TournamentStanding` (Task 2), `Tournaments::Standings::Row` (Task 4),
  `Tournaments::StandingsController` (Task 6).
- Produces:
  - `Decks::Fetcher.call(decklist, user, name, shared: false, format: nil, standard_pool: nil) → Deck`
  - `Tournaments::StandingListImportJob.perform_later(standing, decklist, contributor, import)`
  - `Import::KINDS` includes `"standing_list"`; `Import.standing_list_imports`

- [ ] **Step 1: Write the failing `Decks::Fetcher` test**

Append to `test/services/decks/fetcher_test.rb`:

```ruby
  test "imports a deck owned by nobody, shared and anchored where it is told" do
    pool = standard_pools(:twm_asc)

    deck = Decks::Fetcher.call(@decklist, nil, "Field list",
      shared: true, format: "standard", standard_pool: pool)

    assert_nil deck.user_id
    assert_predicate deck, :shared?
    refute_predicate deck, :physical?
    # The event's pool, not StandardPool.current: the event has a date and it is the only thing
    # here that knows which pool was legal when the deck was played.
    assert_equal pool, deck.standard_pool
  end

  test "a non-Standard format drops the pool it was handed" do
    deck = Decks::Fetcher.call(@decklist, nil, "GLC field list",
      shared: true, format: "glc", standard_pool: standard_pools(:twm_por))

    assert_equal "glc", deck.format
    assert_nil deck.standard_pool_id
  end

  test "a member's own import is unchanged: owned, private and anchored to the current pool" do
    deck = Decks::Fetcher.call(@decklist, users(:one), "Mine")

    assert_equal users(:one), deck.user
    refute_predicate deck, :shared?
    assert_equal StandardPool.current, deck.standard_pool
  end
```

(Reuse whatever `@decklist` and `Cards::Fetcher` stub the existing file already sets up. If
`standard_pools(:twm_asc)` is not a fixture, use `standard_pools(:twm_por)` and assert against
that — the property is "the pool it was handed", not which pool.)

- [ ] **Step 2: Write the failing job test**

`test/jobs/tournaments/standing_list_import_job_test.rb`:

```ruby
require "test_helper"

class Tournaments::StandingListImportJobTest < ActiveSupport::TestCase
  setup do
    @contributor = users(:one)
    @standing = tournament_standings(:ash_masters)
    @tournament = @standing.tournament
    @decklist = File.read(Rails.root.join("test/fixtures/files/doublade_dudunsparce.txt"))
    @import = @contributor.imports.create!(kind: "standing_list", label: "Ash Ketchum's list")
    @original_cards_fetcher_call = Cards::Fetcher.method(:call)
    stub_cards_fetcher
  end

  teardown do
    Cards::Fetcher.define_singleton_method(:call, @original_cards_fetcher_call)
  end

  test "the imported list belongs to nobody, is shared, virtual, and attached to the standing" do
    assert_difference -> { Deck.count }, 1 do
      Tournaments::StandingListImportJob.perform_now(@standing, @decklist, @contributor, @import)
    end

    deck = @standing.reload.deck
    assert_not_nil deck
    assert_nil deck.user_id
    assert_predicate deck, :shared?
    refute_predicate deck, :physical?
    assert_equal "completed", @import.reload.status
  end

  test "the list is anchored to the event's pool, not to the current one" do
    @tournament.update!(format: "standard", standard_pool: standard_pools(:twm_por))

    Tournaments::StandingListImportJob.perform_now(@standing, @decklist, @contributor, @import)

    assert_equal standard_pools(:twm_por), @standing.reload.deck.standard_pool
  end

  test "the list's name situates it: /decks/shared prints no author" do
    Tournaments::StandingListImportJob.perform_now(@standing, @decklist, @contributor, @import)

    assert_equal "Ash Ketchum — #{@tournament.name} (#{@tournament.date})",
      @standing.reload.deck.name
  end

  # Decks::ImportJob broadcasts into #decks-grid and bumps #deck-count, which would file a
  # tournament field list in the contributor's own deck list — the one thing an ownerless deck
  # must never be. This job broadcasts the standing's row instead.
  test "it broadcasts the row and never the contributor's deck grid" do
    broadcasts = capture_turbo_broadcasts do
      Tournaments::StandingListImportJob.perform_now(@standing, @decklist, @contributor, @import)
    end

    assert_empty broadcasts.select { |b| b[:target] == "decks-grid" }
    assert_empty broadcasts.select { |b| b[:target] == "deck-count" }
    replace = broadcasts.find { |b| b[:action] == :replace }
    assert_equal Tournaments::Standings::Row.dom_id(@standing), replace[:target]
    assert_includes replace[:html], "Decklist"
    remove = broadcasts.find { |b| b[:action] == :remove }
    assert_equal "importing-#{@import.id}", remove[:target]
  end

  test "a failure marks the import failed and says so, leaving the standing listless" do
    broadcasts = capture_turbo_broadcasts do
      Tournaments::StandingListImportJob.perform_now(@standing, "not a decklist", @contributor, @import)
    end

    assert_equal "failed", @import.reload.status
    assert_nil @standing.reload.deck
    flash = broadcasts.find { |b| b[:target] == "flash-messages" }
    assert_includes flash[:html], "flash-alert"
  end

  private

  # Both helpers copied from test/jobs/decks/import_job_test.rb, where they were written for the
  # job this one deliberately does not reuse.
  def stub_cards_fetcher
    Cards::Fetcher.define_singleton_method(:call) { |url|
      uri = URI.parse(url)
      segments = uri.path.split("/")
      Card.find_or_create_by!(set_name: segments[2], set_number: segments[3]) do |c|
        c.name = "Card #{segments[2]} #{segments[3]}"
        c.card_type = "Trainer"
        c.rarity = "Common"
      end
    }
  end

  def capture_turbo_broadcasts
    broadcasts = []
    original_append = Turbo::StreamsChannel.method(:broadcast_append_to)
    original_replace = Turbo::StreamsChannel.method(:broadcast_replace_to)
    original_remove = Turbo::StreamsChannel.method(:broadcast_remove_to)

    Turbo::StreamsChannel.define_singleton_method(:broadcast_append_to) { |*args, **kwargs|
      broadcasts << { action: :append, **kwargs }
    }
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to) { |*args, **kwargs|
      broadcasts << { action: :replace, **kwargs }
    }
    Turbo::StreamsChannel.define_singleton_method(:broadcast_remove_to) { |*args, **kwargs|
      broadcasts << { action: :remove, **kwargs }
    }

    yield

    broadcasts
  ensure
    Turbo::StreamsChannel.define_singleton_method(:broadcast_append_to, original_append)
    Turbo::StreamsChannel.define_singleton_method(:broadcast_replace_to, original_replace)
    Turbo::StreamsChannel.define_singleton_method(:broadcast_remove_to, original_remove)
  end
end
```

- [ ] **Step 3: Write the failing controller and admin tests**

Append to `test/controllers/tournaments/standings_controller_test.rb`:

```ruby
  test "a decklist on the form opens an import and enqueues the job" do
    assert_difference -> { Import.count }, 1 do
      assert_enqueued_with(job: Tournaments::StandingListImportJob) do
        post tournament_standings_path(@tournament), params: { tournament_standing: {
          player_name: "Brock", division: "masters", archetype_id: archetypes(:ogerpon).id
        }, decklist: "4 Doublade TWM 62" }
      end
    end

    import = Import.order(:id).last
    assert_equal "standing_list", import.kind
    assert_equal @user, import.user
    # The row exists before its list does, which is the point: a failed import must not lose the
    # standing somebody typed.
    assert_equal "Brock", TournamentStanding.order(:id).last.player_name
  end

  test "no decklist enqueues nothing" do
    assert_no_difference -> { Import.count } do
      assert_no_enqueued_jobs(only: Tournaments::StandingListImportJob) do
        post tournament_standings_path(@tournament), params: { tournament_standing: {
          player_name: "Brock", division: "masters", archetype_id: archetypes(:ogerpon).id
        }, decklist: "   " }
      end
    end
  end

  test "a refused save enqueues nothing" do
    assert_no_difference -> { Import.count } do
      post tournament_standings_path(@tournament), params: { tournament_standing: {
        player_name: "", division: "masters", archetype_id: archetypes(:ogerpon).id
      }, decklist: "4 Doublade TWM 62" }
    end

    assert_response :unprocessable_entity
  end

  test "the event page shows the reader's field-list import in flight" do
    @user.imports.create!(kind: "standing_list", label: "Brock's list")

    get tournament_path(@tournament)

    assert_select "#importing-standings .importing-item", text: /Brock's list/
  end
```

Append to `test/controllers/admin/imports_controller_test.rb`:

```ruby
  # The decklist text is not stored anywhere — an Import carries a label, not a payload — so
  # there is nothing to re-run. Refused explicitly rather than left to fall through the case,
  # which destroys the old row and enqueues nothing.
  test "a field-list import cannot be retried" do
    import = users(:one).imports.create!(kind: "standing_list", label: "Ash's list", status: "failed")

    assert_no_difference -> { Import.count } do
      post retry_admin_import_path(import)
    end

    assert_redirected_to admin_imports_path
    assert_match(/cannot be retried/, flash[:alert])
    assert Import.exists?(import.id)
  end
```

- [ ] **Step 4: Run them to verify they fail**

```bash
bin/rails test test/services/decks/fetcher_test.rb test/jobs/tournaments \
  test/controllers/tournaments test/controllers/admin/imports_controller_test.rb
```

Expected: FAIL — `Decks::Fetcher` takes no keywords, `Tournaments::StandingListImportJob` does
not exist, `Import` rejects the `standing_list` kind.

- [ ] **Step 5: Give `Decks::Fetcher` its three keywords**

`app/services/decks/fetcher.rb`:

```ruby
  # shared/format/standard_pool exist for the tournament field list, which is a Deck owned by
  # nobody: it must be shared (the only listing that can show it is /decks/shared) and it is
  # played under the *event's* format, anchored to the *event's* pool. A member's own import
  # passes none of them and behaves exactly as it did.
  def initialize(decklist, user, name, shared: false, format: nil, standard_pool: nil)
    @decklist = decklist
    @user = user
    @name = name
    @shared = shared
    @format = format
    @standard_pool = standard_pool
  end
```

and in `call`, replace the `Deck.create!` line:

```ruby
      # A member's own import never asks for a format, so the deck takes the "standard" column
      # default and is anchored to the current pool rather than left unsavable; the deck form is
      # where the user corrects it. A field list is told both, because the event knows both —
      # and clear_inapplicable_classification drops the pool when the format is not Standard, so
      # a GLC event's list needs no special case here.
      deck = Deck.create!(
        user: @user,
        name: @name,
        shared: @shared,
        format: @format || "standard",
        standard_pool: @standard_pool || StandardPool.current
      )
```

- [ ] **Step 6: Extend `Import`**

`app/models/import.rb`:

```ruby
  KINDS = %w[deck card_set standing_list].freeze
```

and beside the other scopes:

```ruby
  scope :standing_list_imports, -> { where(kind: "standing_list") }
```

- [ ] **Step 7: Write the job**

`app/jobs/tournaments/standing_list_import_job.rb`:

```ruby
module Tournaments
  # Imports the decklist a member typed into a standings row, as a Deck owned by nobody.
  #
  # Deliberately not Decks::ImportJob with a flag: that job broadcasts the finished deck into
  # #decks-grid and replaces #deck-count, which would file a tournament field list in the
  # contributor's own deck list — the one thing an ownerless deck must not be. Decks::Fetcher is
  # what the two legitimately share.
  #
  # Everything is broadcast to the *contributor's* :notifications stream, not the standing's or
  # the event's: they are the one person waiting for it, and they are the only one the layout
  # subscribes for.
  class StandingListImportJob < ApplicationJob
    def perform(standing, decklist, contributor, import)
      tournament = standing.tournament
      deck = ::Decks::Fetcher.call(
        decklist, nil, deck_name(standing, tournament),
        shared: true, format: tournament.format, standard_pool: tournament.standard_pool
      )
      standing.update!(deck: deck)
      import.update!(status: "completed")

      remove_importing_item(contributor, import)
      broadcast_flash(contributor, "flash-notice",
        %(Field list for "#{standing.player_name}" imported (#{deck.deck_cards.count} cards).))
      Turbo::StreamsChannel.broadcast_replace_to(
        contributor, :notifications,
        target: Tournaments::Standings::Row.dom_id(standing),
        # can_edit: the broadcast only ever reaches the contributor, who is signed in and may
        # therefore write any row — wiki governance, so no further question to ask.
        html: Tournaments::Standings::Row.new(
          standing: standing, viewer: contributor, can_edit: true
        ).call
      )
    rescue => e
      import.update!(status: "failed", error_message: e.message)
      remove_importing_item(contributor, import)
      broadcast_flash(contributor, "flash-alert",
        %(Import of the field list for "#{standing.player_name}" failed: #{e.message}))
    end

    private

    # /decks/shared prints no author, so the name is the only thing that can situate the list.
    def deck_name(standing, tournament)
      "#{standing.player_name} — #{tournament.name} (#{tournament.date})"
    end

    def remove_importing_item(contributor, import)
      Turbo::StreamsChannel.broadcast_remove_to(
        contributor, :notifications, target: "importing-#{import.id}"
      )
    end

    def broadcast_flash(contributor, css_class, message)
      Turbo::StreamsChannel.broadcast_append_to(
        contributor, :notifications, target: "flash-messages",
        html: <<~HTML
          <div class="flash #{css_class}" data-controller="flash">
            #{ERB::Util.html_escape(message)}
          </div>
        HTML
      )
    end
  end
end
```

- [ ] **Step 8: Add the decklist field and the enqueue**

In `app/views/components/tournaments/standings/form.rb`, before the form actions:

```ruby
          render Ui::FormGroup.new(hint: decklist_hint) do
            label(class: "form-label", for: "decklist") { "Decklist (optional)" }
            helpers.text_area_tag(:decklist, nil, class: "form-input", id: "decklist", rows: 10,
              placeholder: "4 Doublade TWM 62\n…")
          end
```

with:

```ruby
      # Outside the tournament_standing hash, like tournament_entry_id: the text is not an
      # attribute of the row, it is the payload of a background import. The list it produces
      # belongs to the event and to nobody, and no UI can edit it afterwards.
      def decklist_hint
        return "Paste the list to import it. The row is saved either way." unless @standing.deck

        "This standing already has a field list. Pasting a new one imports a second."
      end
```

(The second branch is honest rather than clever: nothing here deletes the old list, and saying so
is better than a control that silently replaces one.)

In `app/controllers/tournaments/standings_controller.rb`, in `create` and `update`, after the
successful save and before the redirect, call `enqueue_list_import`, and add:

```ruby
    # The standing is saved either way, so its row exists before its list does: a scrape that
    # fails must not lose the row somebody typed. Absent a decklist, nothing is enqueued.
    def enqueue_list_import
      decklist = params[:decklist].to_s
      return if decklist.strip.empty?

      import = current_user.imports.create!(
        kind: "standing_list", label: "#{@standing.player_name} — #{@tournament.name}"
      )
      Tournaments::StandingListImportJob.perform_later(@standing, decklist, current_user, import)
    end
```

- [ ] **Step 9: Refuse the retry**

In `app/controllers/admin/imports_controller.rb#retry`, immediately after the status guard:

```ruby
      # The decklist text is not stored anywhere — an Import carries a label, not a payload — so
      # there is nothing to re-run. Refused here rather than left to fall through the `case`
      # below, which destroys the old row and enqueues nothing. (The "deck" branch has had that
      # bug since it was written: it re-enqueues @import.label as the *decklist*, which is the
      # deck's name. Pre-existing and out of scope — recorded so the new kind is not wired into
      # the same switch and left silently doing nothing.)
      if @import.kind == "standing_list"
        redirect_to admin_imports_path,
          alert: "A tournament field list cannot be retried: its decklist text is not stored."
        return
      end
```

- [ ] **Step 10: Run the tests to verify they pass**

```bash
bin/rails test test/services/decks/fetcher_test.rb test/jobs test/controllers
```

Expected: PASS.

- [ ] **Step 11: Sabotage-verify three tests**

```bash
# 1. Pass StandardPool.current instead of tournament.standard_pool in the job
#    → "anchored to the event's pool" must fail.
# 2. Broadcast to target "decks-grid" as well → "never the contributor's deck grid" must fail.
# 3. Remove the standing_list branch from Admin::ImportsController#retry
#    → "a field-list import cannot be retried" must fail.
bin/rails test test/jobs/tournaments test/controllers/admin/imports_controller_test.rb
```

Expected: one red test each; restore after each.

- [ ] **Step 12: Run the whole suite, lint, commit**

```bash
bin/rails test && bin/rubocop && bin/brakeman --no-pager
git add app/services/decks/fetcher.rb app/models/import.rb app/jobs/tournaments \
  app/controllers/tournaments app/controllers/admin/imports_controller.rb \
  app/views/components/tournaments/standings/form.rb test/services test/jobs test/controllers
git commit -m "Import a standing's field list as a deck owned by nobody"
```

---

### Task 9: System tests, on both viewports

**Files:**
- Create: `test/system/tournament_standings_test.rb`

**Interfaces:**
- Consumes: everything from Tasks 1–8.
- Produces: nothing the app reads.

- [ ] **Step 1: Write the failing system test**

`test/system/tournament_standings_test.rb`:

```ruby
require "application_system_test_case"

class TournamentStandingsTest < ApplicationSystemTestCase
  setup do
    @user = users(:one)
    @tournament = tournaments(:one)
    login_as @user, scope: :user
  end

  test "a member adds a row to an event's sheet" do
    visit dashboard_path
    click_nav_link "Tournaments"
    click_on @tournament.name

    click_on "Add a standing"
    fill_in "Player name", with: "Brock"
    select "Senior", from: "Division"
    find("[data-archetype-picker-target='input']").fill_in with: archetypes(:ogerpon).name
    find(".archetype-search-item", text: archetypes(:ogerpon).name).click
    fill_in "Final placement", with: "4"
    fill_in "Wins", with: "6"
    fill_in "Losses", with: "2"
    fill_in "Ties", with: "1"
    click_on "Create Tournament standing"

    assert_selector "h1", text: @tournament.name
    assert_selector "h3", text: "Senior"
    assert_text "Brock"
    assert_text "6-2-1"
    assert_text "#4"
  end

  # The picker has no deck here, so it has no Suggest button — and the controller must still
  # connect, or searching an archetype does nothing at all.
  test "the standings form's archetype picker works without a deck" do
    visit new_tournament_standing_path(@tournament)

    assert_no_button "Suggest"
    find("[data-archetype-picker-target='input']").fill_in with: archetypes(:ogerpon).name

    assert_selector ".archetype-search-item", text: archetypes(:ogerpon).name
  end

  test "a member publishes their own participation and the row is marked as theirs" do
    visit tournament_path(@tournament)

    click_on "Publish my participation"

    # Prefilled from the participation: name from the profile, division from the profile's
    # division on the event's date, placement from the entry.
    assert_field "Player name", with: tournament_profiles(:ash).player_name
    assert_field "Final placement", with: tournament_entries(:one).placement.to_s
    click_on "Create Tournament standing"

    assert_selector ".data-table-row", text: /#{tournament_profiles(:ash).player_name}/ do
      assert_text "You"
    end
    assert_no_text "Publish my participation"
  end

  test "a member claims a row somebody else typed, then unlinks it" do
    visit tournament_path(@tournament)

    within(".data-table-row", text: "Giovanni") { click_on "This is me" }

    assert_selector ".data-table-row", text: /Giovanni/ do
      assert_text "You"
    end

    within(".data-table-row", text: "Giovanni") { click_on "Unlink" }

    assert_selector ".data-table-row", text: /Giovanni/ do
      assert_no_text "You"
    end
  end

  test "a member imports a field list onto a row" do
    visit new_tournament_standing_path(@tournament)

    fill_in "Player name", with: "Brock"
    select "Masters", from: "Division"
    find("[data-archetype-picker-target='input']").fill_in with: archetypes(:ogerpon).name
    find(".archetype-search-item", text: archetypes(:ogerpon).name).click
    fill_in "Decklist (optional)", with: "4 Doublade TWM 62"
    click_on "Create Tournament standing"

    # The row lands before its list does, which is the point: the import runs in the background
    # and the sheet is not held hostage to a scrape.
    assert_text "Brock"
    assert_selector "#importing-standings .importing-item", text: /Brock/
  end

  test "a visitor reads the sheet and is offered no control on it" do
    Warden.test_reset!

    visit tournament_path(@tournament)

    assert_text "Giovanni"
    assert_no_link "Add a standing"
    assert_no_button "This is me"
    assert_no_link "Edit", exact: true
  end
end
```

- [ ] **Step 2: Run both halves of the sweep to verify they fail, then pass**

```bash
bin/rails test:system TEST=test/system/tournament_standings_test.rb
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system TEST=test/system/tournament_standings_test.rb
```

Expected: FAIL first (the whole file is new against a feature already built, so if it passes on
the first run, read each assertion again and confirm it really exercises what it claims — a
`within` that matches nothing raises, but an `assert_no_*` on a page that failed to load passes
vacuously). Then PASS on both.

Two things to expect if a test fails:

- The `Create Tournament standing` button label comes from Rails' default submit text for the
  model name. Confirm it with `grep -n 'Create Tournament' log/test.log` or read the rendered
  page; adjust the label rather than the form.
- Below the breakpoint, `.data-table-cell`s stack and `within(".data-table-row", text: …)` still
  works, but a button inside a stacked row may need scrolling into view. If Capybara reports an
  element as not clickable, that is a real mobile layout problem — fix the CSS, not the test.

- [ ] **Step 3: Commit**

```bash
bin/rubocop && git add test/system/tournament_standings_test.rb
git commit -m "Drive the standings sheet through a browser, on both viewports"
```

---

### Task 10: Documentation

**Files:**
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: everything.
- Produces: nothing the code reads.

- [ ] **Step 1: Add the standings paragraph**

In `CLAUDE.md`, immediately after the paragraph beginning **"Entry uniqueness is per Play!
Pokémon profile, not per user"**, add:

```markdown
**A `TournamentStanding` is a line of the event's own public sheet; a `TournamentEntry` is a
member's private participation in it.** They are two tables and not one because the players a
sheet records have no account here — a standing therefore hangs off the `Tournament`, carries a
free-text `player_name` plus its normalized mirror, and is governed as a **wiki**: any signed-in
member may add, correct or delete any row (`TournamentStandingPolicy` answers `user.present?` to
every write), with `created_by` the only trace of who typed it. That policy reads no `admin?`,
unlike `TournamentPolicy`, because there is no moderation question a member cannot already
answer. `(tournament_id, player_name_normalized, division)` is UNIQUE and *is* the row's identity
— the model validation exists for the readable error, the index for the guarantee, the same
division of labour as `(set_name, set_number)` on `Card`. `normalize_player_name` runs
`before_validation` **and** `before_save`, for the reason `Tournament#normalize_name` does, and it
**squishes**: a player name arrives copy-pasted off a standings sheet far more often than it
arrives typed. `NameNormalizable` is not included — it normalizes `name`, not `player_name`, and
nothing searches standings by player. The cascades are opposites on purpose:
`Tournament has_many :standings, dependent: :destroy` (the sheet is the event's, so it goes with
it) while `TournamentEntry has_one :standing, dependent: :nullify` (deleting my private record
must not erase a public row other members read). A `before_destroy` takes the field list with the
row, but **only a list nobody owns** — nothing points a standing at an owned deck today, and the
guard is what stops a future caller detonating a member's deck through a standings delete.

**The claim link is the one thing on a standing that is not wiki-writable, and
`standing_params` must never permit `tournament_entry_id`.** Without that omission the ordinary
edit form would let any member attach their own participation to a row naming somebody else, or
detach yours. It is written only by `#claim`/`#unclaim`, from an id resolved through
`current_user.tournament_entries.find_by!(id:, tournament_id:)` — so a stranger's entry is a
`RecordNotFound`, never a policy question, which is why the *model* checks only that the
participation happened at this event and not who owns it. `TournamentStandingPolicy#unclaim?` is
the single owner-scoped rule in the file: anybody may correct the public data, only the claimant
may sever the link. A partial UNIQUE index on `tournament_entry_id WHERE … IS NOT NULL` is what
actually stops a member publishing themselves twice under two spellings of their own name, which
the player-name key cannot see — and it is partial because SQLite treats NULLs as distinct, the
trap `Archetype`'s old index fell into. Values on a standing are **copied** from a participation,
never derived from it: editing the private record must not silently republish, and the row being
wiki-editable is what makes correcting it an ordinary edit rather than a resync mechanism.
`Tournaments::StandingsController` is a third deliberate `PubliclyReachable` exception beside
`Tournaments::EntriesController` and `DeckResultsController`: its routes ride out of
`authenticate :user` by nesting under `tournaments` alone, it keeps `authenticate_user!` as its
only gate, every action calls `authorize`, and nothing enforces that it must — hence a case per
action in `test/controllers/public_access_test.rb`.

**The event carries three field sizes, and `TournamentEntry#participant_count` survives beside
them.** `junior_participant_count`/`senior_participant_count`/`masters_participant_count` are
read through `Tournament#participant_count_for(division)` and cap a standing's `placement` — per
division, because Play! Pokémon ranks a placement against the size of *that player's* age
division. The entry's own column is not a duplicate and is not derivable from them: an entry with
no `tournament_profile` has no division, so there is nothing on the event to read.
`TournamentStanding::DIVISIONS` is `TournamentProfile::DIVISIONS` mapped to Strings rather than a
second list — and `TournamentProfile#division` answers with a **Symbol**, which the enum column
will not take, so the prefill calls `.to_s` and asks about the *event's* date rather than today
(a division is fixed for a whole season).

**A `Deck` may belong to no member, and that made three latent reads into bugs.** An ownerless
deck is a tournament field list: `Deck#ownerless_deck_is_shared_and_virtual` requires it to be
`shared` (`/decks/shared` is the only listing that can show it — it is *not* in anybody's
`/decks`) and forbids it being `physical` (`physical` is what makes a deck consume a collection,
and there is no collection to consume), which is what makes every allocation service unreachable
for it **by construction** rather than by convention: they all read `deck.user` and all sit behind
`DeckPolicy#owner?`, which a nil `user_id` can never satisfy. `TournamentEntry#deck_belongs_to_user`
already refuses a field list as a participation deck, for free. Two reads were live bugs the
moment the column went nullable and are fixed: `DecksController#show` branched on
`@deck.user_id == current_user&.id`, which is `nil == nil` — **true** — for an ownerless deck read
by a visitor, and served them the owner's page; and `Search::Global#shared_deck_scope`'s
`where.not(user: @user)` compiles to `user_id != ?`, which SQL evaluates to NULL rather than true,
so every field list vanished from a signed-in member's spotlight while a visitor still saw them
(hence the explicit `where(user_id: nil).or(…)`). Three more raised `NoMethodError` on
`deck.user.email` — the two admin deck views and the admin dashboard — and now print
`Deck#owner_label`. `Decks::Duplicator` builds from an attribute allowlist and calls
`@deck.user.decks`, so it is unreachable for a field list by both rules at once.

**The field-list import reuses `Decks::Fetcher` and deliberately not `Decks::ImportJob`.** That
job broadcasts the finished deck into `#decks-grid` and replaces `#deck-count`, which would file a
tournament field list in the contributor's own deck list — the one thing an ownerless deck must
not be. `Tournaments::StandingListImportJob` broadcasts the standing's own row instead
(`Tournaments::Standings::Row.dom_id`, which is why that row is its own Phlex component rather
than a block inside `Ui::DataTable`), to the **contributor's** `:notifications` stream. `Decks::Fetcher`
gained `shared:`/`format:`/`standard_pool:` and accepts a nil user: a field list is anchored to
**the event's** pool, not to `StandardPool.current`, because the event has a date and it is the
only thing that knows which pool was legal — and `clear_inapplicable_classification` drops the
pool when the format is not Standard, so a GLC event's list needs no special case. The deck's name
is `"<player> — <event> (<date>)"` because `/decks/shared` prints no author and the name is the
only thing that can situate the list. `Import::KINDS` gained `standing_list`, and
`Admin::ImportsController#retry` **refuses** it explicitly rather than falling through the `case`:
the decklist text is not stored, so there is nothing to re-run. (The `"deck"` branch of that same
`case` has never worked — it re-enqueues `@import.label` as the *decklist*, which is the deck's
name. Pre-existing, out of scope, recorded so the new kind is not wired into the same silence.)
The archetype `Decks::Fetcher` detects stays on the deck and never overwrites the standing's own:
the standing's was declared by a human making a record, detection exists to guess when nobody has,
and a disagreement between the two is information rather than a conflict.

**Out of scope here, and the obvious next issue:** aggregation of any kind — no per-event
metagame breakdown, no cross-event metagame page. The archetype FK and the `division` column are
chosen so that a breakdown is a `group` over one table when it ships. Also out: claiming a row as
a player with no account (claiming *is* a member linking their own participation), importing
standings from RK9 or Limitless, and Championship Points on a standing.
```

- [ ] **Step 2: Update the three existing paragraphs the change touches**

- In the **Controllers** paragraph, add `Tournaments::StandingsController` to the sentence naming
  `Tournaments::EntriesController`, and note that `resources :tournaments` now carries two nested
  resources out of `authenticate :user` by nesting (`entries` and `standings`).
- In the **`PubliclyReachable`** paragraph, add `Tournaments::StandingsController` to the list of
  deliberate exceptions beside `DeckResultsController` and `Tournaments::EntriesController`.
- In the **Key services** list, update the `Decks::Fetcher` bullet with its three new keywords and
  the nil user; in **Jobs**, add `Tournaments::StandingListImportJob`.
- In the **Models** paragraph, add `TournamentStanding` to the association survey and note
  `decks.user_id` is nullable.
- In the paragraph beginning **"`Ui::CardSelect`"**, rename `Decks::ArchetypeField` to
  `Ui::ArchetypePicker` and say the deck is now optional (no Suggest button without a `deck_key`,
  and the Stimulus controller already tolerates the missing String value).

- [ ] **Step 3: Verify the claims**

Every sentence added above must be true of the code as committed. Re-read each and check it
against the file it describes; a `CLAUDE.md` that lies is worse than one that says nothing.

```bash
grep -n "ArchetypeField" app/ -r        # must be empty
grep -n "standing_list" app/models/import.rb app/controllers/admin/imports_controller.rb
bin/rails test && bin/rubocop && bin/brakeman --no-pager
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Document the standings sheet and the ownerless deck"
```

---

## Final verification

```bash
bin/rails db:test:prepare
bin/rails test
bin/rails test:system
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system
bin/rubocop
bin/brakeman --no-pager
bin/importmap audit
```

All six must pass — that is the same set CI runs. Then open a PR against `master`.
