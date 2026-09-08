# The public archetype analyses, addressed by slug

`/archetypes` and `/archetypes/:id` become reachable without a session, and an archetype's
address stops being its row id and becomes a slug derived from its name.

Two changes ship together because they are one deliverable — a page a visitor can be handed a
link to — and because both of them rewrite the same seven files. They are separable in
principle and are kept separable in the commits.

Supersedes, in `docs/superpowers/specs/2026-09-05-archetype-metagame-stats-design.md`, the two
sentences that argue for the id over a slug (that record stays as written; this one is the newer
decision). The seven-edit list this spec implements was written down in advance, atop
`ArchetypesController` and in `docs/architecture/archetype-metagame.md`, by applying the obvious
three and reading what broke — that list is the reachability half of this design, not a
rediscovery of it.

## Measurements

Everything numeric below is command output, taken against the restored production dump that is
the development database (1238 standings, 79 archetypes).

| Question | Answer | How |
|---|---|---|
| How many archetypes, and do their slugs collide today? | 79 rows, **79 distinct slugs, 0 collisions, 0 blanks** | `Archetype.pluck(:name_normalized).map(&:parameterize)` grouped |
| Can two *card* names produce one slug? | **Yes, 2 groups out of 1806 distinct card names**: `Nidoran♀`/`Nidoran♂` and `Team Rocket's Nidoran♀`/`Team Rocket's Nidoran♂`, both → `nidoran` / `team-rocket-s-nidoran` | `Card.distinct.pluck(:name)` grouped by slug |
| Can a real card name produce a *blank* slug? | **No** — 0 of 1806. `parameterize` transliterates: `Flabébé` → `flabebe`, `Nidoran♀` → `nidoran`, `Heat Factory ♢` → `heat-factory`. It returns `""` only for a name with no Latin-transliterable character at all (`ポケモン` → `""`, `Ω` → `""`) | measured on the catalogue plus those probes |
| What does the report page cost? | **13 queries / 78.3 ms** for the three services on the largest archetype (Dragapult ex, 174 lists) | `ActiveSupport::Notifications` counter + `CLOCK_MONOTONIC` |
| What does the catalog cost? | **5 queries / 10.9 ms** | same |
| Do any archetypes carry a NULL `name_normalized`? | 0 | `Archetype.where(name_normalized: nil).count` |

## The slug

**It is a stored column, not a value computed per request.** `parameterize` is Ruby, so
`find_by!(slug: params[:id])` is the only shape that stays one indexed query; the alternative —
loading the table and matching in Ruby — is a full scan on the app's most expensive page and it
grows with the catalogue. The column is the same kind of denormalised mirror `name_normalized`
already is on this table, and it earns its UNIQUE index for the reason `(set_name, set_number)`
does on `Card`: the address of a page has to name exactly one row.

**It is recomputed from the name on every save, and no history is kept.** `before_validation`,
declared *after* `auto_generate_name`, because that callback is what produces the name when the
admin has not typed one — computing the slug before it would key the URL on the previous
members. Renaming an archetype moves its URL and breaks any link to the old one; that is the
owner's explicit decision, so there is no slug-history table, no redirect, and no numeric-id
fallback.

**`name_normalized`, not `name`.** `parameterize` already folds case and runs of separators, so
the two agree on every name measured — deriving from the mirror is the cheaper claim to keep
true, and it makes the invariant `slug == name_normalized.parameterize` a thing a test can assert
over every row. It needs `normalize_name` to have run, so `Archetype` gains
`before_validation :normalize_name` beside `NameNormalizable`'s own `before_save` — exactly the
addition `Tournament` already carries, for the same reason (a validation has to see the
normalized value before the record is validated, not only once it is saved).

**A collision refuses, with the error on `:name`.** Two archetypes can share a name today —
nothing on the table is unique but the fingerprint pair — so a UNIQUE slug adds a rule: names
must differ by more than punctuation. The measured surface for it is two pairs of cards out of
1806 names, neither of which leads an archetype, and the escape hatch already exists in the
model: the admin form sets `custom_name`, so the second archetype gets typed a name of its own.
The error is attached to `:name` and not to `:slug` because nobody types a slug — a bare
"Slug has already been taken" names a field the form does not have.

**A blank slug refuses too, and that is the one known limit.** A name with no transliterable
character produces `""`, which cannot address a page. Zero rows and zero card names are in that
state, and the way to reach it is #111 (Japanese card sets): a Japanese-named archetype cannot be
created while this validation stands. Recorded here rather than solved, because every solution
(a digest, an id suffix, a transliteration table) is a URL nobody can read for a case nobody can
currently produce, and #111 will have to decide it anyway.

**`to_param` returns the slug, so `/admin/archetypes/:id` becomes a slug too.**
`Admin::ArchetypesController#set_archetype` switches to `find_by!(slug: params[:id])`. This is
`Deck`'s precedent applied unchanged — `Deck#to_param` is its key and `Admin::DecksController`
looks up `find_by!(key: params[:id])` — and the alternative, passing `@archetype.id` at the
eleven admin call sites, is a rule the next call site cannot know about.

**`Api::ArchetypesController` keeps integer ids.** Its `index` and `create` answer JSON whose
`id` feeds a `<select>` and a `deck.archetype_id` write. That is a reference to a row, not the
address of a page — the same split `decks.id` keeps against `decks.key` for the tournament entry
form. Nothing in that controller takes a `params[:id]`.

**An unsaved record must be given a slug by hand.** `to_param` is `slug`, and a callback has not
run on `Archetype.new(...)`, so a component test that renders an unpersisted archetype through
`archetype_path` has to spell the slug out — the rule fixtures already follow for
`name_normalized` and the fingerprint pair. Two files do this today
(`test/components/archetypes/sample_selector_test.rb`, `test/components/ui/archetype_badge_test.rb`).

**The migration backfills, and the UNIQUE index is what proves the backfill was safe.** Add the
column nullable, write `name.squish.downcase.parameterize` into every row with `execute` (no
model reference, so the migration cannot drift with the class), then `change_column_null` and
`add_index unique: true`. A production collision or blank the measurement did not see fails the
migration at index creation rather than shipping an unaddressable row. `bin/docker-entrypoint`
needs no new step: the backfill is inside `db:prepare`, unlike `standard_pools:backfill_anchors`,
whose data the *seeds* had to create first.

## The public surface

Seven edits, in the order the controller's own comment lists them. Three are covered by an
existing test that goes red without them; four are not, and the four are the point of the list.

1. `resources :archetypes` moves out of `authenticate :user` in `config/routes.rb`.
2. `ArchetypesController` includes `PubliclyReachable` with `publicly_reachable :index, :show`,
   and drops its hand-declared `after_action :verify_authorized` (the concern declares it).
3. `ArchetypePolicy#index?`/`#show?` become `true`.
4. A per-IP `rate_limit to: 60, within: 1.minute, unless: -> { user_signed_in? },
   store: RateLimitStore, only: :index`, named `"archetypes-index"`. 60 is
   `tournaments#index`'s and `decks#shared`'s number, for the reason those two share it: the same
   shape — a field debounced at 300 ms driving a paginated listing behind a Turbo Frame — and, at
   5 queries / 10.9 ms, a cheaper one.
5. `nav_link "Archetypes", archetypes_path, "archetypes"` in `Ui::PublicNavbar`. Without it a
   visitor on either page lights **zero** navbar entries, which `NavbarActiveSectionTest` cannot
   see because it names no visitor archetype page.
6. `Search::Global#archetype_scope` drops its `Archetype.none` branch. Its test —
   "a visitor gets no archetypes, and none are queried for" — keeps *passing* while defending a
   rule that has become false, so it is inverted in the same commit rather than watched.
7. The two archetype links a public page withholds today start being emitted:
   `Tournaments::Standings::Row#archetype_badge` drops its `if @viewer.present?` guard, and
   `Decks::PublicBadges` passes `href: archetype_path(@deck.archetype)`.

**`#show` gets no rate limiter, and that is the precedent rather than an omission.** Its two
`<select>`s auto-submit (`card-filter`), so a click is a full page load of 13 queries / 78.3 ms —
the most expensive public page in the app. It still matches the rule the other limiters were
sized by: one request per deliberate click, not one per keystroke, which is why
`tournaments#show` and `decks#show` carry none either while their listings do. A test pins the
absence, the way `tournaments_rate_limit_test.rb` pins it for an event page.

**Nothing about the two pages is member-specific, and that was checked rather than assumed.**
No component under `app/views/components/archetypes/` reads `current_user`, `user_signed_in?`, a
viewer or a policy, and every link either of them emits points at `/archetypes`, `/cards/:id` or
the card image proxy — all three already public. There is no second, visitor-only view of these
pages for that reason: unlike `Decks::PublicShowView`, there is nothing to withhold.

**The pages ship `noindex`, like everything else.** `XRobotsTagMiddleware` and the layout's meta
tag cover them for free. Discovery and SEO are deferred to #142 for the whole app; opening a page
to visitors is not the same decision as inviting a crawler to it.

## What would stay green if this were implemented wrong

The four silent edits above are that list, plus:

- **The slug never being recomputed on a rename.** Nothing today reads a stale slug, so a
  `before_create`-shaped mistake keeps every page working — and the URL of a renamed archetype
  silently keeps naming the old name. A model test renames and asserts the slug moved.
- **The slug being computed before `auto_generate_name`.** Same shape: an archetype created with
  no typed name would key on the *previous* members' names, or on nothing at all. A test creates
  through the API-shaped path (no `name`, no `custom_name`) and asserts the slug matches the
  generated name.
- **The invariant drifting on the fixtures.** They skip callbacks, so a hand-written `slug` can
  disagree with the hand-written `name_normalized`. `ArchetypeTest` already asserts `name` and
  `name_normalized` stay in step over every fixture; the slug joins that assertion.
- **The admin panel 404ing.** `Archetype.find(params[:id])` with a slug casts to `0` in SQLite
  and raises — a 404 on every admin show/edit/update/destroy. Nothing in
  `Admin::ArchetypesControllerTest` passes a raw id, so the existing tests would catch it only
  because they route through `to_param`; the test that would not is the one that hardcodes a
  numeric URL, and none does.
- **The 404 shape changing under `PubliclyReachable`.** An unknown archetype stops being Rails'
  default `RecordNotFound` 404 and becomes the static `public/404.html`. Both are `:not_found`,
  so `"show 404s on an unknown archetype"` stays green either way — the concern is what makes an
  unknown *slug* answer the same as an unknown id, and a test asserts the body, not only the
  status.
- **A visitor's spotlight now querying archetypes.** Dropping the `Archetype.none` branch adds
  one `SELECT DISTINCT "archetypes".*` with two LEFT JOINs per visitor keystroke, inside
  `SearchController`'s existing 120/min. The inverted test asserts the rows come back *and* that
  the query ran, which is the same assertion turned round.

## Deliberately out of scope

- Indexability, sitemap, canonical tags and Open Graph — #142, for the whole app at once.
- Any slug history, redirect from an old slug, or numeric-id fallback.
- A slug on anything else. `Tournament` has the closer case (`name_normalized` is already half of
  its UNIQUE key) and it is not this change.
- A cache on `#show`. 13 queries / 78.3 ms, and the honest version key is a `MAX(updated_at)`
  aggregate over the archetype's standings — the kind `Card.filter_values` had to be corrected
  away from. `docs/architecture/archetype-metagame.md` carries the threshold.
- A visitor-facing "add this archetype to my decks" affordance, or anything else that would make
  these pages a write surface.
