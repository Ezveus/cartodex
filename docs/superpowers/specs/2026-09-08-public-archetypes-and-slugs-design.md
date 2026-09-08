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
| What does the report page cost? | **16 queries / ~31 ms / 85 KB** for a visitor on the largest archetype (Dragapult ex, 174 lists), 17 with a session; the three archetype services are **13** of those 16 | `ActiveSupport::Notifications` + `CLOCK_MONOTONIC` around an `ActionDispatch::Integration::Session` request |
| What does the catalog cost? | **5 queries** for a visitor, now asserted | same |
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

**A third refusal: a slug a route already claims.** `resources :archetypes` in the admin
namespace emits `GET /admin/archetypes/new` *before* `GET /admin/archetypes/:id`, so an archetype
slugged `new` has no reachable admin show page — and `#create`/`#update` both end in
`redirect_to admin_archetype_path`, which lands the admin on a blank "New Archetype" form
carrying the flash "Archetype updated.": a 200 that reads as if the edit had been lost. Reachable
by typing "New" in the one field the form has. `Archetype::RESERVED_SLUGS` is `%w[new]` and the
list is *derived*, not guessed: `edit` needs no entry because it is nested under `:id`
(`/admin/archetypes/edit` matches `show` with id `"edit"`, measured), and the public resource
declares neither, being `only: [:index, :show]`. It grows if either resource gains a collection
route. `Deck#key` cannot collide this way — it is random base64 — so this class of bug is new with
the slug.

**A collision refuses, with the error on `:name`.** Two archetypes can share a name today —
nothing on the table is unique but the fingerprint pair — so a UNIQUE slug adds a rule: names
must differ by more than punctuation. The measured surface for it is two pairs of cards out of
1806 names, neither of which leads an archetype, and the escape hatch is the admin form's
`custom_name`: the second archetype gets typed a name of its own. The error is attached to
`:name` and not to `:slug` because nobody types a slug — a bare "Slug has already been taken"
names a field the form does not have.

**That escape hatch is not on the member's path, and the refusal there is a 422 they cannot act
on.** `Api::ArchetypesController#create` — the picker's "Create & select" — builds the archetype
with *no* name and lets `auto_generate_name` supply one from the two cards, so a member choosing
the second Nidoran gets `{"errors": […]}` over a form with no name field. Left as it is rather
than papered over: the alternative is a disambiguating suffix, which breaks "the name decides the
address" for every archetype in order to serve a case the whole catalogue can produce twice and
currently does not. A test pins the message so it is at least readable, and an admin can create
the row.

**Under a real race the index answers, and the two writers answer it differently — one badly,
one not at all.** Measured: forcing a duplicate slug past the validation raises
`ActiveRecord::RecordNotUnique` (`SQLite3::ConstraintException: UNIQUE constraint failed:
archetypes.slug`). In `Api::ArchetypesController` that is caught by the existing
`rescue ActiveRecord::RecordNotUnique` — so a 422 and not a 500 — but `render_race_winner`
re-reads through `existing(primary, secondary)`, which keys on the **fingerprint pair**, and a
slug collision means the winner has a *different* pair, so the re-read finds nothing and the
client gets the fallback `"Archetype already exists"`. That message is false (no archetype with
that pair exists) and it hides the one actionable thing the model produced. In
`Admin::ArchetypesController` nothing rescues it at all, so there the same race is an unrescued
500 — a door the fingerprint-pair index has had since it existed, and to which this adds a
second.

Both are left as they are, and the reason is the window rather than the shape: the validation is
a non-atomic `exists?` that fires long before the index can, so the readable refusal is what a
real user meets — the same division `Tournaments::StandingsImporter`'s event lookup makes — and
the index covers only an interleaving nobody has produced. Neither case was reproducible without
editing code to stage the interleaving. Widening the rescues is a change to *race handling* on two
controllers, one of them the archetype picker's idempotency contract, and it is written down here
rather than made in passing.

**A blank slug refuses twice: the validation for the message, a `CHECK` for the guarantee.**
Because `assign_slug` is a `before_save`, a validation-skipping write (`save(validate: false)`,
`update_attribute`) still runs the callback and reached the column with the refusal skipped —
and `""` offends neither `NOT NULL` nor the UNIQUE index, which only sees a *second* blank. The
row that shipped was worse than unaddressable: `archetype_path` on it emits `/archetypes/`, the
collection path, so the catalog links it to the listing it sits in, and the model's own refusal
then makes it unsavable from the panel. `CHECK (slug <> '')` is what makes the state unreachable.
No app path skips validations on an `Archetype` today, so this was latent — and it is the hazard
the `before_save` move created in exchange for the one it removed, which is why both are named
here.

A name with no transliterable character produces `""`, which cannot address a page. Zero rows and zero card names are in that
state, and the way to reach it is #111 (Japanese card sets): a Japanese-named archetype cannot be
created while this validation stands. Recorded here rather than solved, because every solution
(a digest, an id suffix, a transliteration table) is a URL nobody can read for a case nobody can
currently produce, and #111 will have to decide it anyway.

**The name decides the address, and the name is regenerated on any save that does not set the
non-persisted `custom_name`.** Measured: a hand-named archetype, *read fresh from the database*
and saved, comes back named after its member cards, and its public URL moves with it — the
accessor lives on the instance that was handed the typed name, so only a reloaded record loses
it. Not live: the only savers are `Admin::ArchetypesController` (which sets `custom_name` whenever
the submitted name is present, and whose blank-name path is a deliberate "regenerate from the
cards") and `Api::ArchetypesController#create` (new records); `Archetypes::FingerprintSync` writes
with `update_columns` and `dependent: :nullify` with `update_all`. But the address of a public,
shareable page is now a function of an in-memory accessor, so the day anything saves an archetype
for an unrelated reason, every hand-named one loses its name *and* every link shared to it.
Fixing it means persisting `custom_name`, which is a decision about how archetypes are named
rather than about publishing pages. `ArchetypeTest` states the behaviour instead, so the next
reader meets it as a pinned fact rather than discovering it.

**`assign_slug` is a `before_save`, and that is what makes `to_param` safe to write plainly.**
The first version ran it `before_validation`, so a *refused* update left the new name's slug on
the in-memory record — and in the one case the uniqueness validation exists for, that slug belongs
to another archetype. `Admin::ArchetypesController#update`'s `render :edit` then emitted a form
posting to `/admin/archetypes/<the other archetype>`, and the admin's corrected resubmission
renamed the wrong row, with a 200 and no error anywhere. Reproduced as a request test before the
fix. The first fix was `to_param = slug_in_database || slug`; the one that shipped moves the
callback instead, so a rejected save never touches the column and the hazard is unreachable rather
than handled. Both the validation and the callback read one `derived_slug` — two readers computing
the rule separately is how a check and a write come to disagree.

**`to_param` returns the slug, so `/admin/archetypes/:id` becomes a slug too.**
`Admin::ArchetypesController#set_archetype` switches to `find_by!(slug: params[:id])`. This is
`Deck`'s precedent applied unchanged — `Deck#to_param` is its key and `Admin::DecksController`
looks up `find_by!(key: params[:id])` — and the alternative, passing `@archetype.id` at the
eleven admin call sites, is a rule the next call site cannot know about.

**`Api::ArchetypesController` keeps integer ids.** Its `index` and `create` answer JSON whose
`id` feeds a `<select>` and a `deck.archetype_id` write. That is a reference to a row, not the
address of a page — the same split `decks.id` keeps against `decks.key` for the tournament entry
form. Nothing in that controller takes a `params[:id]`.

**An unsaved record must be given a slug by hand.** `to_param` is `slug`, and no callback has
run on `Archetype.new(...)`, so anything that renders an unpersisted archetype through
`archetype_path` has to spell the slug out — the rule fixtures already follow for
`name_normalized` and the fingerprint pair. Three files do:
`test/components/archetypes/sample_selector_test.rb`,
`test/components/archetypes/name_group_row_test.rb` (whose scope reaches `Archetypes::CardReport`,
which builds the path) and, in `app/` rather than `test/`, `Styleguide::PageView`'s four
stand-ins. `test/components/ui/archetype_badge_test.rb` is *not* one of them — it renders a
fixture, and what it needed was the numeric href in its assertion replaced by the real slug.

**The migration backfills, and the UNIQUE index is what proves the backfill was safe.** Add the
column nullable, write `name.squish.downcase.parameterize` into every row with `update_all` —
through the model class, as `AddKeyToDecks` does, but never through a validation or a callback,
because re-validating history is not a backfill's job and one pre-existing offender would abort
the run halfway — then `change_column_null` and `add_index unique: true`. The *rule* is spelled
out in the migration rather than read off `Archetype`, so the file survives the model moving on.

**And the backfill is called by name, because CI never runs a migration.** `db:test:prepare`
loads `db/schema.rb`, so an inline loop is code the suite cannot reach — and a rule that diverged
from `assign_slug` would ship slugs that are *wrong while being unique and non-blank*, which
neither the NOT NULL nor the index can see. `AddSlugToArchetypes.slug_for` and `#backfill_slugs`
are public for the reason `AddFingerprintsToArchetypes`' three checks are, and `ArchetypeTest`
asserts the migration and the callback agree over four awkward names as well as that the loop
writes. A production collision or blank the measurement did not see fails the
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

**The fourth visitor nav entry wraps one label between 769 px and about 840 px, and that is the
design's existing behaviour rather than a regression this introduced.** Measured in the browser:
at 769 px the visitor row is one 56 px band with no overlap and no horizontal overflow, but
"Shared decks" takes two text lines inside its own box (`.navbar-link` is `white-space: normal`,
`flex-shrink: 1`, nothing is clipped — `scrollWidth == clientWidth` on all four). It did not
before the fourth link: without it that label is 111 px on one line. What settles it is the
**member** navbar, which has nine links and, measured under the same CSS at the same width,
already wraps two of them ("Shared decks", "My tournaments") on `master`. So this is a navbar the
row cannot fit behaving the way this navbar already behaves — changing it (`nowrap` plus an
overflow rule, or shorter labels) is one decision about all three navbars and not part of
opening two pages. Below the breakpoint the menu is a stacked dropdown: four 38 px rows, no
overlap, no overflow.
6. `Search::Global#archetype_scope` drops its `Archetype.none` branch. Its test —
   "a visitor gets no archetypes, and none are queried for" — keeps *passing* while defending a
   rule that has become false, so it is inverted in the same commit rather than watched.
7. The two archetype links a public page withholds today start being emitted:
   `Tournaments::Standings::Row#archetype_badge` drops its `if @viewer.present?` guard, and
   `Decks::PublicBadges` grows a `linked:` keyword — **not** an unconditional `href`.

**`Decks::PublicBadges` takes `linked:`, defaulting to false, and that is the same nested-anchor
rule `Decks::ClassificationBadges` already carries rather than a separate one.** An earlier draft
of this design said that rule "only concerns `ClassificationBadges`", and it was wrong: of the
three surfaces rendering `PublicBadges`, two put it inside an anchor of their own —
`Decks::DeckCard`'s `a.deck-item-link` (the shared-decks grid) and `Home::DashboardView`'s
showcase tile — and an `<a>` within an `<a>` makes an HTML5 parser close the outer one at the
second start tag. Measured on the shared grid with the unconditional href in place: the
description, the card count **and** the whole badge row fell outside the deck's own link.
`Decks::PublicShowView` is the one caller that opts in.

The two guards are controller tests reading `Nokogiri::HTML5`, because `assert_select` parses
HTML4 and nests anchors happily — and the emptiness half of such a test cannot stand alone: the
parser makes the escaped anchor a *sibling* of the link, so `assert_empty link.css("a")` passes
over broken markup. Both tests assert containment first, and the showcase one has to pick the
tile of the *tagged* deck: `at_css` took the first tile on the page, which carries no badge and
could not exhibit the bug. The pre-existing guard of this kind covers `/decks`, which renders
`ClassificationBadges`, so it could not have seen either of these two.

**The 5-query figure the limiter was sized on is now an assertion, and for a visitor.**
`"index issues a constant number of queries regardless of how many archetypes"` is *relative*
(`assert_equal small, large`), so a constant query added to the action lands in both measurements
and is invisible to it — and it signs a member in. `"the catalog costs a visitor five queries"`
is the absolute, signed-out counterpart.

**`#show` gets no rate limiter, and that is the precedent rather than an omission.** Its two
`<select>`s auto-submit (`card-filter`), so a click is a full page load of 16 queries / ~31 ms /
85 KB — the app's largest uncapped anonymous response. It still matches the rule the other
limiters were sized by: one request per deliberate click, not one per keystroke, which is why
`tournaments#show` and `decks#show` carry none either while their listings do. A test pins the
absence, the way `tournaments_rate_limit_test.rb` pins it for an event page.

The counter-argument, recorded rather than omitted: `decks#export` is also one deliberate click
and *is* capped, at 30/min and a third of the cost. What settles it is `tournaments#show` — the
same shape, uncapped, measured at 55 req/s against this page's 23.
`docs/architecture/public-surface.md` carries both numbers and names 120/min as the option if the
trade is ever revisited.

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
