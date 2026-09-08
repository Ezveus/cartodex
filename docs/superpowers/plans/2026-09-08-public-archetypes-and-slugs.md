# Plan — the public archetype analyses, addressed by slug

Design: `docs/superpowers/specs/2026-09-08-public-archetypes-and-slugs-design.md`.
Baseline in this worktree: **1579 runs, 6985 assertions, 0 failures, 0 errors**.

Implemented sequentially, not in parallel lanes. The two halves look disjoint and are not:
`ArchetypesController`, `archetypes_controller_test.rb` and the two architecture docs are edited
by both, and every view-side test needs the migration to exist before it can run at all. Two
agents on those files is the overlap the pipeline names as a red flag, so the agent budget goes
to the plan adversary and the three reviews instead.

Two commits: the slug, then the public surface. Each is independently green.

## Frozen contract

- Column: `archetypes.slug`, `string`, `NOT NULL`, UNIQUE index `index_archetypes_on_slug`.
- Derivation: `self.slug = name_normalized.to_s.parameterize` in `before_validation :assign_slug`,
  declared **after** `before_validation :normalize_name` and after
  `before_validation :auto_generate_name`.
- `Archetype#to_param` returns `slug` (no fallback).
- Lookups: `Archetype.find_by!(slug: params[:id])`.
- Rate limiter constant: `ArchetypesController::INDEX_RATE_LIMIT_TO = 60`,
  `RATE_LIMIT_WITHIN = 1.minute`, `name: "archetypes-index"`.

## Commit 1 — the slug

### 1.1 Migration `AddSlugToArchetypes`

```ruby
def up
  add_column :archetypes, :slug, :string
  execute/select_all loop: for each (id, name), UPDATE with name.squish.downcase.parameterize
  change_column_null :archetypes, :slug, false
  add_index :archetypes, :slug, unique: true
end

def down
  remove_index; remove_column
end
```

No model reference (a migration that calls `Archetype` drifts with the class). Raw SQL through
`quote`, one UPDATE per row — 79 rows in production. A blank or colliding value the measurement
did not see fails at `change_column_null` / `add_index`, which is the point.

### 1.2 `Archetype`

- `before_validation :normalize_name` (beside `NameNormalizable`'s `before_save`), declared
  after `auto_generate_name`.
- `before_validation :assign_slug`, declared last.
- `validate :slug_is_addressable_and_unique` — two errors, both on `:name`:
  - blank slug → `"must contain at least one letter or digit that can appear in a URL"`.
  - taken slug (`Archetype.where(slug:).where.not(id:).exists?`) → names the conflicting
    archetype.
- `def to_param = slug`.

### 1.3 Lookups

- `ArchetypesController#show`: `.find_by!(slug: params[:id])`, comment rewritten (it currently
  argues *for* the id).
- `Admin::ArchetypesController#set_archetype`: `find_by!(slug: params[:id])`.

### 1.4 Fixtures and unsaved records

- `test/fixtures/archetypes.yml`: `slug:` on all three (`teal-mask-ogerpon-ex`,
  `budew-teal-mask-ogerpon-ex`, `standings-marker`) + the header note.
- `test/components/archetypes/sample_selector_test.rb:~260` and
  `test/components/ui/archetype_badge_test.rb`: pass `slug:` on the unpersisted archetypes;
  the badge test's hardcoded `/archetypes/7` becomes the slug.

### 1.5 Tests (written first, red before the model change)

`test/models/archetype_test.rb`:

| Test | Sabotage it must survive |
|---|---|
| slug is derived from the name on create | — |
| **renaming moves the slug** | `before_create` instead of `before_validation` |
| an auto-generated name gets the slug of the *generated* name | `assign_slug` before `auto_generate_name` |
| changing the member cards moves the slug | same |
| a second archetype whose name differs only in punctuation is refused, with the error on `:name` | no uniqueness check |
| a name with no transliterable character is refused, with the error on `:name` | no presence check |
| `to_param` is the slug | — |
| every fixture's slug equals `name_normalized.parameterize` | a hand-written fixture drifting |
| the UNIQUE index refuses a callback-bypassing duplicate (`update_column`) | validation without an index |

`test/controllers/archetypes_controller_test.rb`: show resolves a slug; show 404s on an unknown
slug; **the URL the page emits is the slug** (assert on the rendered href, not on the helper).
`test/controllers/admin/archetypes_controller_test.rb`: an admin URL carries the slug and
resolves; a rename redirects to the *new* slug.

## Commit 2 — the public surface

Edits 1-7 of the spec, plus:

- `ArchetypesController`: drop the hand-declared `after_action :verify_authorized` (the concern
  declares it), add the two rate-limit constants and the `rate_limit`, rewrite the 43-line
  header comment — it is a to-do list that will have been done.
- `Search::Global#archetype_scope`: `Archetype.search(@query)` unconditionally; its comment
  rewritten.
- `Ui::ArchetypeBadge`'s comment ("`/archetypes` requires a session") rewritten; `href:` stays
  opt-in (three callers, `Decks::ClassificationBadges` still gates on `linked:` for the
  nested-anchor reason, which is unrelated to sessions).

### Tests

| File | Change |
|---|---|
| `public_access_test.rb` | the two archetype rows move `owner_only_gets` → `public_gets`; the comment above them rewritten |
| `archetypes_controller_test.rb` | "a visitor is sent to sign in for both pages" → "a visitor reads both pages"; add a body assertion on the static 404 for an unknown slug |
| `archetype_policy_test.rb` | the two nil-user assertions **and** the third inside "admin status makes no difference" turn round |
| `search/global_test.rb` | "a visitor gets no archetypes, and none are queried for" → inverted: rows come back and the group's query ran |
| `navbar_active_section_test.rb` | new: "a visitor's archetype pages light the archetype entry alone", both paths |
| **new** `test/controllers/archetypes_rate_limit_test.rb` | throttles an anonymous client past 60 on `#index`, never a signed-in one; **an archetype page is not rationed** (mirrors `tournaments_rate_limit_test.rb`) |
| `test/system/archetype_metagame_test.rb` | new: a visitor navigates from the public navbar to the catalog to a report, and the standings-sheet badge links |
| `test/components/tournaments/standings/row_test.rb`, `decks/public_badges_test.rb` (if they exist) | the badge now carries an href for a visitor |

## Docs

`CLAUDE.md` (routes/policy paragraph + the archetype identity paragraph gains the slug),
`docs/architecture/public-surface.md` (three enumerations: the includers, the `true` policies,
"**Six** rate_limits" → seven), `docs/architecture/archetype-metagame.md` (the "Member-only"
paragraph becomes the record of what shipped, keeping the seven-edit history).

## Verification

`bin/rails test` (> 1579 runs), `bin/rails test:system`,
`SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system`, `bin/rubocop` on the written files,
`bin/brakeman --no-pager`, `bin/importmap audit`. Sabotage every new test. Open both pages as a
visitor in a real browser at 1400 and at 390.

## What this plan got wrong, found by attacking it before it existed in code

The adversarial pass over the plan (mandate: "which of these decisions would the existing suite
fail to notice if they were implemented wrong?") returned twelve items. Two were live defects the
plan walked straight into, four were real coverage holes, four were errors about this codebase,
and two were already covered by tests the plan had.

**Two defects, both reproduced before being fixed:**

1. `Decks::PublicBadges` is rendered inside an anchor at **two of its three** call sites
   (`Decks::DeckCard`'s `a.deck-item-link`, `Home::DashboardView`'s showcase tile), so the
   unconditional `href:` the plan prescribed nested an `<a>` in an `<a>` — measured: the
   description, the card count and the whole badge row fell outside the deck's own link. The
   existing `Nokogiri::HTML5` guard covers `/decks`, which renders `ClassificationBadges`, and
   stayed green. Fixed with a `linked:` keyword; two new guards, both asserting containment
   before emptiness (the parser makes the escaped anchor a *sibling*, so the emptiness half alone
   passes over broken markup — my first draft of the showcase test did exactly that, and also
   picked the first tile on the page, which carries no badge).
2. `to_param` reading the in-memory slug made a refused admin rename re-render a form posting to
   **another archetype's** URL, where `find_by!` resolved it and renamed the wrong row — 200, no
   error. Fixed with `slug_in_database || slug`.

**Four coverage holes the plan did not name:** the migration's backfill is unreachable by CI
(`db:test:prepare` loads the schema, never a migration) and carries its own copy of the slug
rule, so it is now called by name from `ArchetypeTest`; both flat-cost tests on `#index`/`#show`
are *relative*, so a constant added query is invisible to them and an absolute, signed-out one
was added; `Api::ArchetypesController#create` has no name field, so a slug collision there is a
422 nothing could act on (documented, pinned); and the visitor system test needed
`Warden.test_reset!`, without which it would have passed as a member and defended edit 5 without
exercising it.

**Four errors about the codebase, all noisy rather than silent:** §1.4 named
`archetype_badge_test.rb` as building an unpersisted archetype (it does not — it hardcodes a
numeric href instead, which is the line that went red), missed
`name_group_row_test.rb`'s unpersisted record, missed `Styleguide::PageView`'s five, and missed
three `Archetype.insert_all` calls in `ArchetypeTest` against a NOT NULL column. All four
surfaced as red on the first full run.
