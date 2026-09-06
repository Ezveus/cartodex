# Card labels, stage 2: the `role` family — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Record what a card *does*, and let `/archetypes/:id` group its card report by that —
closing #155. Stage 1 built the store; this stage seeds the `role` vocabulary, proposes
assignments from the card text, gives a human the screen that decides them, and adds the report's
second grouping mode.

**Architecture:** Seven seeded `card_labels` rows in the `role` family, a versioned rule per slug
in `CardLabels::RoleSuggester` writing `suggested` assignments, an admin curation screen at
`/admin/card_roles` that turns a suggestion into a `curated` decision (or a `curated` refusal),
and a `grouping:` keyword on `Archetypes::CardStats` that regroups the *same* entries by role.
No new table, no new column, no new query on the report.

**Tech Stack:** Rails 8.1, Ruby 3.4.1, SQLite, Minitest + fixtures, Phlex components, Hotwire.

**Spec:** `docs/superpowers/specs/2026-09-05-card-labels-and-roles-design.md`
**Stage 1 plan (shipped, PR #162):** `docs/superpowers/plans/2026-09-05-card-labels-stage-1.md`

**Baseline on `worktree-card-labels-stage-2` @ `f769f73`:** `bin/rails test` → **1421 runs, 5968
assertions, 0 failures, 0 errors**, measured five times.

---

## Global Constraints

- **Roles are a property of the card, never of the archetype playing it.** No per-archetype
  override, anywhere, however tempting. "Attacker" is not a role.
- **`CardLabel::ROLES` is the single source of the vocabulary.** The seed walks it; the suggester's
  rules are keyed on the same slugs; a rule with no matching row, or a row with no rule, is a bug
  a test names.
- **Provenance decides who overwrites whom.** The suggester writes and withdraws **only its own
  `suggested` rows**. A pair carrying a `curated` row is never examined. Ticking writes `curated`
  present; unticking writes `curated` **rejected**, never a deletion.
- **The report gains a mode, not a second report.** `Entry`, `NameGroup`, `fixed_core`, every
  percentage and every count are computed identically in both modes. Only the grouping of entries
  into sections changes.
- **Role mode says three things out loud**: the sections overlap and do not add up to the list; a
  card with no role falls into a rendered, counted "No role recorded" section; a `type` badge
  (ACE SPEC) renders in both modes and opens no section.
- **No extra query on `/archetypes/:id`.** `CardStats#labels_by_fingerprint` already loads every
  active assignment of every family in one `eager_load`; role mode reads what is already there.
  The page stays at its pinned 17.
- **Roles appear nowhere but `/archetypes/:id` and the admin screen.** Not on a deck page, not in
  the JSON API, not in an MCP tool.
- Comments explain **why**, in the register of the surrounding code. English code, English
  comments, English docs.
- `bin/rubocop` on the files written (never repo-wide — `mise` resolves Ruby 4.0.1 here and reports
  ~159 pre-existing offences CI does not), `bin/brakeman --no-pager`, `bin/importmap audit`, and
  the system suite at **both** viewports.
- Every new test is **sabotage-verified**: break the mechanism, watch that test go red, restore,
  watch it go green, report both.

---

## The frozen contract

Both implementation lanes consume this. Nothing in it is negotiable inside a lane.

```ruby
# app/models/card_label.rb
CardLabel::ROLES = [
  { slug: "draw",                name: "Draw",                position: 10, description: "…" },
  { slug: "search",              name: "Search",              position: 20, description: "…" },
  { slug: "gust",                name: "Gust",                position: 30, description: "…" },
  { slug: "switch",              name: "Switch",              position: 40, description: "…" },
  { slug: "recovery",            name: "Recovery",            position: 50, description: "…" },
  { slug: "disruption",          name: "Disruption",          position: 60, description: "…" },
  { slug: "energy_acceleration", name: "Energy acceleration", position: 70, description: "…" }
].freeze
```

Slug format is `/\A[a-z0-9]+(?:-[a-z0-9]+)*\z/` (stage 1's validation) — **so the seventh slug is
`energy-acceleration`, with a dash**, and every reference to it in Ruby, in a test and in a URL
uses the dash. (Recorded because `energy_acceleration` reads more naturally in Ruby and would fail
validation silently at seed time on a fresh database.)

```ruby
CardLabelAssignment.suggested   # scope, source: "suggested"
CardLabelAssignment.curated     # scope, source: "curated"

CardLabels::RoleSuggester.call            # => Result
CardLabels::RoleSuggester::Result         # :created, :kept, :withdrawn, :decided, :unfingerprinted,
                                          #    :fingerprints_examined

Archetypes::CardStats.call(standings:, grouping: :type)   # :type (default) | :role
Archetypes::CardStats::NO_ROLE = :no_role                 # the final section's key
Archetypes::CardStats::NO_ROLE_LABEL = "No role recorded"
```

- `CategoryGroup#key` is a Symbol in both modes: a category key in `type` mode, the role's slug
  `.to_sym` (dashes and all: `:"energy-acceleration"`) or `NO_ROLE` in `role` mode.
- `ArchetypesController#show` reads `params[:group]`, and **anything other than the string `"role"`
  is `:type`** — the clamp `#index` already makes for `?page=`, and the reason
  `test/controllers/archetypes_controller_test.rb:306` exists for `?pool[]=`.
- The mode control's links re-emit **the sample the page is showing** (`@scope.all_formats? ?
  MetagameScope::ALL : @scope.pool&.id`), never `params[:pool]` — a malformed parameter must not
  travel into a link the page renders.
- Admin curation writes go to `PATCH /admin/card_roles/:id`, where `:id` is the **fingerprint**
  (16 hex characters, URL-safe by construction).

---

### Task 0: Measure what the existing suite would not catch

Same reflex as stage 1's Task 0, and not optional: two blockers in #153 survived a fully green
suite. This runs **before** any code, and its output is the list of tests the later tasks own.

**Files:**
- Create: `tmp/155-stage-2-ce-qui-ne-rougirait-pas.md` (unversioned handoff, French)

- [ ] **Step 1: Sabotage-measure the decisions below and record what stays green**

For each, apply the sabotage, run the named suite, record the exact result, restore:

1. `CardStats` in `role` mode putting an entry in only its *first* role rather than in all of
   them (the overlap is the whole point);
2. an unlabelled entry silently dropped in `role` mode rather than landing in "No role recorded"
   (the report then sums to less than the list and still looks plausible);
3. `?group=role` leaking into `type` mode's category order or counts;
4. the suggester overwriting a `curated` row, or deleting one;
5. the curation screen unticking by **deleting** the row instead of writing `rejected`;
6. a role slug present in `ROLES` and absent from the seeded rows (or the reverse).

- [ ] **Step 2: Write the file and stop**

Each line is *couvert par …* or *rien ne rougirait*. Every "rien ne rougirait" must be matched by a
test in Tasks 1–5; Task 6 verifies this file against what was written.

---

### Task 1: The vocabulary — `CardLabel::ROLES` and its seed

**Files:**
- Modify: `app/models/card_label.rb`, `db/seeds/card_labels.rb`, `app/models/card_label_assignment.rb`
- Modify: `test/models/card_label_test.rb`, `test/models/card_label_seed_test.rb`

**Interfaces:**
- Produces: `CardLabel::ROLES`, seven seeded `role` rows, `CardLabelAssignment.suggested` /
  `.curated`.
- Consumes: nothing.

- [ ] **Step 1: Failing tests first**

In `card_label_test.rb`:
- `"every seeded role slug passes the slug format"` — iterate `CardLabel::ROLES`, build, assert
  valid. This is the test that catches `energy_acceleration` vs `energy-acceleration`.
- `"the role vocabulary is ordered and has no duplicate slug or position"`.

In `card_label_seed_test.rb`:
- `"it seeds one row per role in ROLES"` — load the seed, assert
  `CardLabel.roles.pluck(:slug) == CardLabel::ROLES.map { _1[:slug] }`.
- `"an admin's correction to a role's name survives a re-seed"` — rename a seeded role, load the
  seed again, assert the rename stands (the `standard_pools.rb` guarantee, on the family that is
  *not* admin-creatable but *is* admin-editable).

In `card_label_assignment_test.rb`:
- `"the source scopes select their own rows and nothing else"`.

- [ ] **Step 2: Watch them fail** (`NameError: uninitialized constant CardLabel::ROLES`).

- [ ] **Step 3: Implement**

`ROLES` as in the contract, each with a one-sentence `description` that says what the role *is* in
game terms — the description is what the admin screen shows as a title and what the report's badge
carries, so it is user-facing text, not a code comment. Suggested wording:

| slug | name | description |
|---|---|---|
| `draw` | Draw | Puts cards from the deck into the hand without naming what it takes. |
| `search` | Search | Searches the deck for named cards and puts them into the hand or into play. |
| `gust` | Gust | Brings one of the opponent's Benched Pokémon to the Active Spot. |
| `switch` | Switch | Moves the player's own Active Pokémon out of the Active Spot. |
| `recovery` | Recovery | Returns cards from the discard pile to the hand or the deck. |
| `disruption` | Disruption | Acts on the opponent's hand, deck or board rather than on your own. |
| `energy-acceleration` | Energy acceleration | Attaches Energy from somewhere other than the turn's own attachment. |

The seed grows a second loop over `ROLES` beside the existing `type_labels` loop, with the same
`next if CardLabel.exists?(slug:)` guard and the same `puts`. Keep the local-variable convention
(`db/seeds/card_labels.rb` is loaded twice in one test process).

Add `scope :suggested` and `scope :curated` to `CardLabelAssignment`.

- [ ] **Step 4: Sabotage-verify** — change one `ROLES` slug to `energy_acceleration` (underscore)
  and watch the format test go red; drop one loop iteration and watch the seed test go red.

- [ ] **Step 5: Commit** — `"Seed the seven roles a card can play"`.

---

### Task 2: `CardLabels::RoleSuggester` — rules propose, and withdraw their own

**Lane A.** Depends on Task 1.

**Files:**
- Create: `app/services/card_labels/role_suggester.rb`, `test/services/card_labels/role_suggester_test.rb`
- Modify: `lib/tasks/card_labels.rake`, `test/lib/tasks/card_labels_rake_test.rb`

**Interfaces:**
- Consumes: `CardLabel::ROLES`, `Card` + `attacks` + `abilities`, `CardLabelAssignment`.
- Produces: `CardLabels::RoleSuggester.call` → `Result(created:, kept:, withdrawn:, decided:,
  unfingerprinted:, fingerprints_examined:)`; `bin/rails card_labels:suggest_roles`.

**Measured before writing (2026-09-06, production dump, 4723 cards / 3023 fingerprints):**

| | |
|---|---|
| played Trainer/Energy fingerprints carrying ≥1 suggested role | **33 of 51** |
| played Pokémon fingerprints carrying ≥1 suggested role | **13 of 43** |
| whole catalogue: fingerprints with ≥1 role | **689 of 3023**, 714 assignments |
| pass duration (read + match, no writes) | **0.5 s** |
| known false positive | *Telepathic Psychic Energy* → `search` |
| known misses | Pokégear 3.0, Explorer's Guidance, Bug Catching Set, Professor Turo's Scenario |

Those four misses are the whole argument of the design: **coverage is not the problem, invisible
errors are.** The suggester's job is to save the human typing, never to decide.

- [ ] **Step 1: Failing tests first**

- `"it suggests a role from the card's own effect text"`
- `"it reads a Pokémon's attacks and abilities, not only its effect"` — a Basic whose attack
  searches the deck is `search`.
- `"one suggestion per fingerprint, however many printings carry it"`
- `"it never examines a pair a human has decided"` — a `curated` row (present **and** rejected,
  two cases) is untouched and is not counted as created.
- `"it never touches an imported row"` — the ACE SPEC assignment of a card whose text matches a
  role rule keeps `source: "imported"`.
- `"a suggestion whose rule no longer matches is withdrawn"` — a `suggested` row for a card that
  no longer matches is deleted, and counted in `withdrawn`.
- `"a card with no fingerprint is skipped and counted"`
- `"a second run creates nothing"` — idempotence, the §9.6 question asked of this service.

- [ ] **Step 2: Watch them fail.**

- [ ] **Step 3: Implement**

```ruby
RULES = {
  "draw" => /…/, "search" => /…/, "gust" => /…/, "switch" => /…/,
  "recovery" => /…/, "disruption" => /…/, "energy-acceleration" => /…/
}.freeze
```

The regexes measured above, verbatim (they are in
`tmp/155-stage-2-mesures.md` and reproduced in the service with the counts they produced):

```ruby
"draw"                => /\bdraws?\b[^.]{0,60}\bcards?\b|\bdraw a card\b/i
"search"              => /search your deck/i
"gust"                => /(switch(?: in)? \d+ of your opponent's benched|your opponent's benched pok[eé]mon (?:with their active|to the active spot))/i
"switch"              => /switch your active pok[eé]mon with \d+ of your benched/i
"recovery"            => /from your discard pile (?:into your hand|in ?to your hand)|from your discard pile into your deck|shuffle[^.]{0,40}from your discard pile/i
"disruption"          => /your opponent (?:shuffles|discards)|each player shuffles their hand|opponent's hand/i
"energy-acceleration" => /attach[^.]{0,80}energy[^.]{0,40}from your (?:discard pile|deck)|attach[^.]{0,40}from your discard pile to/i
```

Three decisions to encode with a comment each:

1. **The text of a fingerprint is the union of its printings' text.** A Trainer's fingerprint is a
   SHA of its name alone, so two printings can carry differently worded text; taking the union
   means a reprint that clarifies wording adds a role rather than a re-run silently losing one.
2. **A rule is versioned by being read only here.** No rule reads the card's *name*: a rule that
   named Iono would be curation wearing a rule's clothes, and would not survive the next set.
3. **`withdrawn` deletes**, and it is the one deletion in the whole feature: a `suggested` row is
   the machine's own opinion, and leaving a stale one behind would make the screen show a
   suggestion no rule stands behind. `curated` and `imported` rows are never deleted by anything.

Write inside `serialized_transaction`. Representative printing for `card_id`: the same choice the
report makes is not available here (it is per-sample), so use the newest printing by
`(set_name, set_number)` deterministic order and say so.

- [ ] **Step 4: The rake task** — `card_labels:suggest_roles`, printing the receipt
  (`created / kept / withdrawn / decided / skipped`). It does **not** abort: unlike
  `resync_fingerprints`, nothing here is ambiguous and nothing fails a boot on it. A test asserts
  the receipt names each number, and asserts the task does **not** exit non-zero.

- [ ] **Step 5: Sabotage-verify** — remove the `curated` guard (the two "never examines" tests go
  red); make the union a single-printing read (the one-per-fingerprint test goes red); drop the
  withdrawal (its test goes red).

- [ ] **Step 6: Commit** — `"Propose a card's roles from the text it already carries"`.

---

### Task 3: `/admin/card_roles` — the screen where a human decides

**Lane A.** Depends on Tasks 1 and 2.

**Files:**
- Create: `app/controllers/admin/card_roles_controller.rb`,
  `app/views/admin/card_roles/index.html.erb`,
  `app/views/components/admin/card_roles/index_view.rb`,
  `app/views/components/admin/card_roles/row.rb`,
  `app/views/admin/card_roles/update.turbo_stream.erb`,
  `test/controllers/admin/card_roles_controller_test.rb`,
  `test/system/admin_card_roles_test.rb`
- Modify: `config/routes.rb`, `app/views/components/ui/admin_navbar.rb`,
  `app/assets/stylesheets/application.css`

**Interfaces:**
- Consumes: `CardLabel.roles`, `CardLabelAssignment`, `Card`, `Ui::DataTable`, `Ui::Pagination`,
  `Ui::PageHeader`, the `card-filter` Stimulus controller.
- Produces: `GET /admin/card_roles`, `PATCH /admin/card_roles/:id` (`:id` = fingerprint),
  `POST /admin/card_roles/suggest`.

- [ ] **Step 1: Failing controller tests first**

- `"the screen lists one row per fingerprint, not one per printing"`
- `"it defaults to the cards a recorded list actually plays"` — and says so on the page; the
  filter is what turns 3023 into 94.
- `"ticking a role writes a curated decision"`
- `"unticking a role writes a curated refusal and deletes nothing"` — `assert_no_difference
  "CardLabelAssignment.count"`, then assert `rejected` is true and `source` is `"curated"`.
- `"ticking a role a suggestion already proposed promotes that row rather than adding one"`
- `"an unknown fingerprint is a 404, not a new row"`
- `"a non-admin cannot reach the screen"`
- `"the screen costs a constant number of queries however many rows it lists"` — the flat-cost
  reflex; the assignments and the representative printings are two grouped reads, not one per row.

- [ ] **Step 2: Watch them fail.**

- [ ] **Step 3: Implement the controller**

`Admin::CardRolesController < BaseController`, `require_admin!` as the only gate (no Pundit — the
stage-1 convention for `Admin::`).

`#index`:
- `@roles = CardLabel.roles`
- the population: distinct fingerprints, built from `Card` — filtered by `params[:played]`
  (default **on**), `params[:card_type]`, `params[:q]` (name `LIKE`), ordered by name, paginated
  at `PER_PAGE = 50` with the same `requested_page` clamp `ArchetypesController#index` uses.
- one representative `Card` per fingerprint (the newest printing, the same rule the suggester
  uses), one grouped read of the assignments for the page's fingerprints.
- cards with a blank fingerprint are listed too, on page 1, in a row whose checkboxes are
  **disabled** and which says why. (Zero such cards today; the row exists so a click that could
  not be written is never offered.)

`#update`: `PATCH /admin/card_roles/:id` where `:id` is a fingerprint that must match a card
(`Card.exists?(fingerprint:)` or 404 — never create a row for a fingerprint nothing carries, the
stage-1 rule about assignments nothing can ever join). For each role slug, present in
`params[:roles]` → `curated` present; absent → `curated` rejected. Both go through
`find_or_initialize_by(card_label:, fingerprint:)` + `update!(source: "curated", rejected:, card:)`
inside `serialized_transaction`. **Never `destroy`.** Answers with a Turbo Stream replacing that
row, so what the page shows is the database's answer and not the browser's optimism.

`#suggest`: `POST`, runs `::CardLabels::RoleSuggester.call` (leading `::` — `Admin::CardLabels`
and `Admin::CardRoles` are Phlex namespaces and plain `CardLabels::…` resolves there; the stage-1
trap, already commented in `Admin::CardLabelsController`), redirects back with the receipt as a
flash notice. Inline rather than a job: measured at 0.5 s for the read over the whole catalogue,
and it makes no HTTP request — unlike the label import, there is nothing to wait for.

- [ ] **Step 4: The components**

`Admin::CardRoles::IndexView` renders `Ui::PageHeader`, the filter form (`data: { controller:
"card-filter" }`, the shape `/cards` already uses), a "Suggest roles" `button_to`, the
`Ui::DataTable` (columns: Card, Type, then one per role), and `Ui::Pagination`.

`Admin::CardRoles::Row` is its own component **because a Turbo Stream re-renders exactly it** —
the same reason `Tournaments::Standings::Row` is one. Its DOM id is
`"card-role-#{fingerprint}"`. Each row is one `form_with(url: admin_card_role_path(fingerprint),
method: :patch, data: { controller: "card-filter", action: "change->card-filter#submit" })`
holding one checkbox per role, checked when an active assignment exists, and carrying a
`suggested` styling class when that assignment's source is `"suggested"` — a suggestion and a
decision must not look identical, which is the whole point of the screen.

- [ ] **Step 5: Route, navbar, CSS**

`namespace :admin` → `resources :card_roles, only: %i[index update] do post :suggest, on:
:collection end`. Add **two** entries to `Ui::AdminNavbar`: "Card Labels" (stage 1 shipped the
screen without a link — a pre-existing gap this task closes in passing) and "Card Roles".

CSS: one block beside the admin table rules, single-class specificity, in the layer the file's own
comment prescribes. A suggested checkbox is distinguished by a token, never by colour alone.

- [ ] **Step 6: System test, both viewports**

`test/system/admin_card_roles_test.rb`: an admin filters to the played cards, ticks a role, and
the row comes back from the server with the box checked and the "suggested" styling gone. Below
768 px the row must not overflow: assert the geometry (bounding boxes), not the text — the §9.9
lesson, where a text assertion saw nothing because the element rendered fine in the wrong place.

- [ ] **Step 7: Sabotage-verify** — make `#update` `destroy` the row on untick (the refusal test
  goes red); drop the `Card.exists?` guard (the 404 test goes red); render the row inline instead
  of as its own component (the Turbo Stream test goes red).

- [ ] **Step 8: Commit** — `"Give a human the screen that decides a card's roles"`.

---

### Task 4: The report's role mode

**Lane B.** Depends on Task 1 only (the vocabulary), not on Tasks 2–3 — it reads assignments,
whoever wrote them.

**Files:**
- Modify: `app/services/archetypes/card_stats.rb`, `app/controllers/archetypes_controller.rb`,
  `app/views/components/archetypes/card_report.rb`,
  `app/views/components/archetypes/method_note.rb`,
  `app/assets/stylesheets/application.css`
- Modify: `test/services/archetypes/card_stats_test.rb`,
  `test/controllers/archetypes_controller_test.rb`,
  `test/components/archetypes/card_report_test.rb` (new file),
  `test/system/archetype_metagame_test.rb`

**Interfaces:**
- Consumes: `Entry#labels` (already loaded by stage 1's `labels_by_fingerprint`, all families).
- Produces: `CardStats.call(standings:, grouping:)`, `NO_ROLE`, `NO_ROLE_LABEL`, the `?group=`
  control.

- [ ] **Step 1: Failing tests first**

Service (`card_stats_test.rb`):
- `"role mode groups an entry under every role it carries"` — a card with two roles appears in
  two sections, and the two sections' `cards_count` therefore over-count on purpose.
- `"a card with no role lands in No role recorded rather than vanishing"` — and the sum of all
  sections' entries ≥ the number of entries, with every entry present at least once. **This is
  the partition test the type mode never had**, written as its complement: in `type` mode, every
  entry appears exactly once (`assert_equal entries.size, categories.sum(&:cards_count)`).
- `"role sections come in the vocabulary's own order and empty ones are dropped"`
- `"a rejected decision is not a role"`
- `"a type label never opens a section in either mode"` — ACE SPEC does not become a section.
- `"the two modes report the same lists_count and the same fixed core"` — the sentence the spec
  demands: the two views cannot tell two stories about one sample.
- `"an unknown grouping is the type grouping"`.

Controller (`archetypes_controller_test.rb`):
- `"show groups the card report by role when asked"`
- `"show survives a malformed group parameter"` (the `?group[]=` shape, mirroring `:306`)
- `"show still issues a constant number of queries in role mode"` — role mode must not add a
  query; assert the count equals the `type` mode count for the same archetype.

Component (`card_report_test.rb`, new):
- `"role mode says the sections overlap"`
- `"type mode says nothing about overlap"`
- `"the mode links re-emit the sample the page is showing"` — including the case where
  `params[:pool]` was malformed and the scope fell back.

System (`archetype_metagame_test.rb`):
- a member switches the card report to roles and back; the URL carries `group=role`; the pool
  survives the switch. At 390 px the two mode links must not overlap the heading — geometry.

- [ ] **Step 2: Watch them fail.**

- [ ] **Step 3: Implement `CardStats`**

`initialize(standings:, grouping: :type)`; `@grouping = grouping == :role ? :role : :type`.

`categories` branches to `type_categories` (today's method, unchanged) or `role_categories`:

```ruby
def role_categories
  grouped = Hash.new { |hash, key| hash[key] = [] }

  entries.each do |entry|
    roles = entry.labels.select(&:role?)
    roles.any? ? roles.each { |role| grouped[role] << entry } : grouped[NO_ROLE] << entry
  end
  # …ordered by (position, slug), NO_ROLE last, each mapped through name_groups_for
end
```

The comment that has to be there: **an entry deliberately appears under several keys, and
`CategoryGroup#cards_count` therefore counts it several times across the report** — which is why
role mode prints the overlap sentence and why no aggregate is printed beside a role heading
(#156's question, left unanswered on purpose).

- [ ] **Step 4: The controller and the control**

`ArchetypesController#show` computes `@grouping` from `params[:group]` and passes it to both
`CardStats.call` and `Archetypes::CardReport.new`. `CardReport` renders the two links in its own
header — **not** in `Archetypes::SampleSelector`, which is dropped entirely when `selectable?` is
false — as `link_to` with `archetype_path(archetype, pool: current_pool_param, group: …)`, where
`current_pool_param` comes from the scope, not from `params`.

- [ ] **Step 5: Correct what has become false**

- `Archetypes::MethodNote` paragraph 2 currently says "There are no functional categories either
  (Gust, Switch, Recovery): what a card does is not recorded anywhere." It must now say what is
  true: roles are recorded, they are a property of the card and not of this deck, they are
  curated by hand from a suggestion, and a card with no role says so.
- The comment above `CardStats#category_of` says the same and gets the same treatment.
- `docs/superpowers/specs/2026-09-05-archetype-metagame-stats-design.md`'s "No functional
  categories" paragraph: keep the measurement, record that #155 answered it, and how.

- [ ] **Step 6: Sabotage-verify** — assign an entry to only its first role (overlap test red);
  drop the `NO_ROLE` bucket (its test red); read `params[:pool]` in the link builder (the
  malformed-parameter component test red).

- [ ] **Step 7: Commit** — `"Group the deck report by what a card does"`.

---

### Task 5: Documentation and the whole-branch verification

**Files:** `CLAUDE.md`, and every command below.

- [ ] **Step 1: `CLAUDE.md`** — extend the card-label paragraph stage 1 wrote (do not duplicate
  it) with: the seven roles and why the vocabulary is a constant while the `type` family is data;
  rules propose and a human decides, with the 33-of-51 measurement; the report's second mode, the
  overlap that is not a corner case, and the "No role recorded" section as visible curation debt;
  and the fact that roles appear nowhere else. Verify **each sentence against the file it
  describes** before committing it.

- [ ] **Step 2: Run everything**

```bash
bin/rails db:test:prepare test                      # > 1421 runs, 0 failures
bin/rails test:system
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system
bin/rubocop <files written>
bin/brakeman --no-pager
bin/importmap audit
```

- [ ] **Step 3: Run it for real** — on the development dump:

```bash
bin/rails card_labels:suggest_roles
```

Expected, from the measurement above: ~714 assignments created over 689 fingerprints, 0 withdrawn,
0 decided. Then open `/archetypes/:id?group=role` in a browser at **both** widths and read it: the
"No role recorded" section should hold roughly 48 of the 94 played fingerprints, and the overlap
sentence must be there. A review reads code and cannot see rendering.

- [ ] **Step 4: Check Task 0's list** — every *rien ne rougirait* line names a test that now
  exists, or moves to the PR body as a known blind spot.

- [ ] **Step 5: Commit and open the PR** — `"Say what a card does, and let the report group by
  it"`, base `worktree-card-labels-and-roles` (stage 1's branch, PR #162) so the diff reviewed is
  stage 2's alone.

---

## Lane split for parallel implementation

| Lane | Tasks | Files it owns |
|---|---|---|
| **A — roles engine and curation** | 2, 3 | `app/services/card_labels/`, `lib/tasks/card_labels.rake`, `app/controllers/admin/card_roles_controller.rb`, `app/views/**/admin/card_roles/`, `config/routes.rb`, `app/views/components/ui/admin_navbar.rb`, their tests, the **admin** CSS block |
| **B — report role mode** | 4 | `app/services/archetypes/`, `app/controllers/archetypes_controller.rb`, `app/views/components/archetypes/`, their tests, the **archetype** CSS block |

Task 1 is done **before** the lanes start (both consume `ROLES`). Task 5 is done after they land.
`app/assets/stylesheets/application.css` is the only file both touch; they touch different blocks
of it and integration resolves it. Each lane runs in its own worktree so that two `bin/rails test`
runs never share one `storage/test.sqlite3`.
