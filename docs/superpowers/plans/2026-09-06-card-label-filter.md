# Filtering the card catalogue by label (issue #164)

`/cards` filters on five things — a name query, `card_type`, `energy`, `rarity` and
`regulation_mark` — and every one of them is a column on `cards`. Since #154 the catalogue also
knows something no column carries: whether a card holds a label. The only way to see the 29 ACE SPEC
assignments today is to open an archetype's deck report and read the badges one row at a time.

## Why no design spec

No table, no column, no external source. The ticket body is the design record and it already
carries the measurements; what this adds is one parameter shape to a page that is already public.
The decisions that outlive the diff are recorded in the controller's own comment and in `CLAUDE.md`,
the way #156's were.

## The decision the ticket left open, and the answer

`CardLabel` holds two families. `type` is what a card *is* (`ace-spec` today); `role` is what a card
*does* (`draw`, `search`, `gust`, `switch`, `recovery`, `disruption`, `energy-acceleration`). The
ticket asked whether `/cards` filters on `type` only, on both as one list, or on both as two
controls, and the answer is **two controls**, because it is the only shape that lets a reader ask
*Item **and** gust* — and because the two families are governed oppositely everywhere else in the
app (an admin may create and delete a `type` label; a `role` is a constant that code reads).

Two consequences it is worth being explicit about:

- **The role control ships returning nothing.** Production holds 8 labels and 29 assignments, all
  `type`/`ace-spec`; `CardLabels::RoleSuggester` has never been run there. Every one of the seven
  roles answers with zero cards until an admin runs it and curates. That is a true statement about
  the catalogue rather than a broken control, and it is the same state `/admin/card_roles` exists to
  change.
- **A family with no labels renders no control.** `MetagameScope::Result#selectable?`'s instinct:
  a `<select>` whose only option is "All labels" is not a choice. Both families are non-empty today
  (1 and 7), so this is a guard rather than a behaviour anybody will see — and it is what stops the
  page growing a dead control the day a family is emptied.

## What the filter is, mechanically

```ruby
scope.where(fingerprint: CardLabelAssignment.active.where(card_label_id: id).select(:fingerprint))
```

A subquery, not a join, and the first draft of this paragraph got the reason wrong twice — both
caught by the adversarial review, both recorded rather than quietly replaced, because the second
one is the mistake a future reader would repeat.

It said a join would inflate `scope.count`. It would not: `(card_label_id, fingerprint)` is UNIQUE,
so a hand-written join on `fingerprint` is 1:1 and answers 33, exactly as the subquery does. But it
then said "both forms", and **the join Rails can actually express is not that one**.
`Card.joins(:card_label_assignments)` rides the association, which is on `card_id` — the single
printing a decision was read from — and answers **29**, losing precisely the four reprints the
fingerprint key exists to reach (Maximum Belt, Prime Catcher, Scoop Up Cyclone, Sparkling Crystal).
Measured: 33 / 29 / 33 for subquery, association join, hand-written join. A comment claiming
equivalence would have invited the next reader to "simplify" into the one form that silently drops
the point of the feature.

(It also read a row count off `EXPLAIN QUERY PLAN`'s third column — "the 62-row assignment index".
That column is `notused`; the table holds 743 rows and the value varies per query. There is no row
count in an EQP.)

The two real reasons are:

- **`.merge` collapses two `where`s on one column, and `merge` is the idiom three lines away.**
  `CardSearchable#apply_card_name_filter` does `scope.merge(Card.name_matching(name))`, so it is
  what a reader reaches for — and measured, `Card.with_label(a).merge(Card.with_label(b))` emits
  `WHERE fingerprint IN (…b…)` alone: the first filter is silently gone. Chained `where`s AND, which
  is what makes *Item and gust* answerable at all.
- **Rails cannot alias two `joins(:card_label_assignments)` apart**, so the join form cannot express
  two labels in one relation without hand-written SQL.

The keys are indexed on both sides: `(card_label_id, fingerprint)` UNIQUE on the assignments
(leading column `card_label_id`) and `index_cards_on_fingerprint` on the outer side. No table scan
in either form; measured at 0.29 ms for the count and 0.36 ms for the page over 4723 cards. **No
migration.**

`CardLabelAssignment.active` — `rejected: false` — is what every other reader of that table uses. A
curated refusal is a row, not an absence, and a filter that forgot the scope would list the cards a
human has explicitly said the label does **not** apply to.

**The keying is on the fingerprint, which over-applies to Trainers, and that is inherited rather
than introduced.** `Card#compute_fingerprint` is `SHA256(name)` alone for anything that is not a
Pokémon, so a label written on one Trainer printing reaches every printing sharing its *name*.
Measured (§9 of `docs/superpowers/specs/2026-09-05-card-labels-and-roles-design.md`): 0 of 400
Trainer/Energy fingerprints span cards with different effect text, and 0 of the 29 labelled
fingerprints reach a card `is:ace` did not list — exact today, and the same key the deck report
already runs on. Issue #111's Japanese sets are what would change it.

## The three places a sixth filter has to be added, two of which are silent

1. **`filtered_scope`** — the filter itself.
2. **`@searching`** — the condition deciding whether the page queries at all. A label param absent
   from it renders "Select a set or search to browse cards." while claiming to filter.
3. **`search_query_params`** — what the pager re-emits. Absent from it, page 2 silently drops the
   filter and shows the unfiltered catalogue under the same heading.

Both params are read as `params[:label].to_s`, for the reason `page` two lines above carries a
`to_s`: the action is reachable with no session, and a Hash- or Array-shaped param would otherwise
travel as far as `cards_path`, where `ActionController::Parameters` raises `UnfilteredParameters` —
a 500 on a public, rate-limited page. Measured, it cannot get there today, because an unresolvable
slug empties the result and no pager renders; that is a coincidence between two rules rather than a
guarantee, and one word makes it structural.

Only the first is visible in a casual read of the diff; the other two fail quietly.

## The option lists are not `Card.filter_values`, and that is deliberate

`filter_values` caches `rarity` and `regulation_mark` for an hour because neither column is indexed
and computing those lists scans `cards` twice (the third scan `CLAUDE.md` remembers was the
sidebar's `includes(:cards)`, removed before the cache existed). The label options are `CardLabel.types` and
`CardLabel.roles` — two indexed reads of an eight-row table. Folding them into that cached pair
would tie a cheap, always-correct list to an invalidation path (`Card.forget_filter_values`, called
by `CardSets::Importer` and `CardSets::RescrapeJob`) that has nothing to do with labels, and would
make an admin's new label invisible for up to an hour. It would also change the shape of a value two
call sites and a test destructure as a pair.

**And they must not touch `cards`.** `CardsControllerTest`'s "does not instantiate the catalog to
count it" asserts **zero** `Card` objects instantiated on a bare `GET /cards`; the filter bar
renders on every request, so an option list built with a `Card.joins(…)` would turn it red. Reading
`CardLabel` is invisible to that guard, which is why the query cost is pinned separately.

**They are loaded, not handed over as relations**, and that is the one place this change can add an
N+1 to a rate-limited public page. The "render no control for an empty family" guard asks `empty?`
before `each`, and on an unloaded relation that is a second query per family — two extra on every
`/cards` request. The identical pattern is already live one line away: `Cards::IndexView`'s
`search_results` asks `@cards.any?`, which is where the `SELECT 1 AS one` in the measured trace
comes from. A small-versus-large query comparison could never see it, since both lists are one and
seven rows whatever the catalogue holds; only a literal can.

**The literal has to be measured in the test environment, which is not the development one.**
`config/environments/test.rb` sets `:null_store`, so `Card.filter_values` is never cached there and
its two scans run on every request: `/cards` costs 4 queries under test against 2 in a warm dev
process. And with no label fixtures in the repository, today's tests render **neither** select, so a
literal pinned on the default fixture set pins the empty case — it has to be measured inside a test
that creates the labels.

## Shape of the change

- `app/controllers/cards_controller.rb` — `@label` / `@role` params, both in `@searching`, two
  clauses in `filtered_scope`, and the two option lists passed to the view.
- `app/models/card.rb` — a `with_label` scope, so the subquery has one definition and the controller
  stays a controller.
- `app/views/components/cards/index_view.rb` — two `<select>`s. `filter_select` builds options
  where the value *is* the text, and a label needs the slug as value and the name as text, so it
  gains the pair form rather than acquiring a sibling: a private `label_select` shipped first and
  the review named it what it was, a **fourth** spelling of one component
  (`filter_select`, `set_select`, `Ui::FilterSelect`, this). `set_select` stays bespoke — optgroups
  are a different structure. The `return if options.empty?` guard moved onto the shared method with
  it, so it reaches the four pre-existing controls too, where it is unreachable with any catalogue
  holding a card.
- **A role filter says that it is showing proposals.** `CardLabelAssignment.active` is
  `rejected: false` and says nothing about who wrote the row, so a rule's guess and a human's
  decision open the same page — and after one suggester run on the production dump, 714 of 743
  assignments are guesses. `Archetypes::CardReport#provenance_note` answers that for the
  member-only report, and `CLAUDE.md` states the rule about the *store* rather than about one
  screen: a page may leave a proposal on display, but not without saying so. This surface is
  anonymous, so it needs the sentence more. It carries **no number** — the counts available are of
  assignments (fingerprints) while the grid shows printings, and 29 beside a page of 33 is the
  second denominator this repository keeps having to remove — and costs one indexed `EXISTS`, only
  while a role is selected.
- `search_query_params` gains both keys.
- `app/assets/stylesheets/application.css` — nothing, and the reason is not the one it looks like.
  `.cards-search-select` is `flex: 0 0 auto`, i.e. `flex-shrink: 0`: wrapping is **not** what
  prevents overflow, being narrower than the line is, and a single select wider than the content box
  would overflow with no `overflow-x` guard anywhere near it. What makes the addition safe is that
  both new controls are strictly narrower than one that already ships — the longest new option is
  "Energy acceleration" (19 characters) against `set_select`'s "Scarlet & Violet Energy" (23) plus
  its optgroup labels. **The system test cannot see that comparison**: `card_sets.yml`'s longest
  name is "Twilight Masquerade", also 19, so the bar it measures is about four characters narrower
  than the real one. It equals the widest new control and is therefore a valid guard for what this
  change adds, and it is a guard rather than a discriminator for the widest control overall. The real cost of going from six controls to eight is **vertical**: roughly
  three rows becomes four or five at 500px and six at 344px. **Verified by geometry, not by
  assumption** — the `/archetypes` lesson, and no system test drives this bar at all today.

## Tests — the "would stay green" list

Produced by an adversarial pass over this plan, which measured what the existing suite notices. Two
failure modes below were absent from the first draft, and two of its proposed assertions could not
have discriminated anything.

**`p.cards-empty` carries both empty states** — "Select a set or search to browse cards." and "No
cards match your search." — so every assertion here is on the **text**, never on the class. Both
existing empty-state tests are class-only and cannot tell the two apart.

| # | What could be implemented wrong | Why today's suite stays green | The fixture |
|---|---|---|---|
| 1 | the param is not in `@searching` (browse prompt while the URL claims a filter) | no test filters by anything but `q` alone | `get cards_path(label:)` → assert a labelled card's name **and** `count: 0` for an unlabelled one — the second half is what kills the *other* wrong implementation, which renders 48 unfiltered cards and no empty state at all |
| 2 | **`set` + label**, the branch the first draft missed entirely | `set` is deliberately outside `@searching`, so `?set=POR&label=…` renders the whole set today — and `"index without a search shows the selected set grid"` asserts exactly that output as correct | label one card in POR, `get cards_path(set:, label:)` → `h2` reads "Results", one grid item |
| 3 | `search_query_params` drops the param, so page 2 is unfiltered | the pager is untested for any filter, and **a controller test is not constructible**: `Ui::Pagination` renders nothing under two pages, `PER_PAGE` is 48, the fixtures hold 14 cards and production's largest label is 33 | a **component** test rendering `Cards::IndexView` with `pages: 2` (precedent: `sample_selector_test.rb`), asserting the pager href carries `label=`/`role=`. It also catches what no controller test can: `@label` holding a `CardLabel` **record** emits `?label=1`, which page 2 then resolves to nil and drops |
| 4 | the two filters ORed rather than ANDed — **`.merge` is the trap**, and `merge` is the idiom used three lines away in `CardSearchable` | nothing passes two filters touching one column | one card carrying both labels, one carrying only the first → `count: 2` (two printings share a fingerprint) and the second card absent |
| 5 | `.active` forgotten, so the page lists exactly the cards a human refused | `card_label_assignment_test.rb`'s "active excludes rejected rows" guards the **scope**, never its use, and stays green whatever the controller calls | a `rejected: true` assignment → that card absent |
| 6 | keyed on `card_id` rather than `fingerprint` | the labelled fixtures hold one printing per name | `budew_pre` and `budew_asc` already share `budew_shared`; one assignment naming `budew_pre` must return **both** |
| 7 | an unknown slug rendering the browse prompt (or the catalogue) | both outcomes are `p.cards-empty` | `get cards_path(label: "nope")` → `p.cards-empty` **text** "No cards match your search." |
| 8 | the option list unloaded, adding two queries per request to a rate-limited public page | both lists are 1 and 7 rows whatever happens, so no relative comparison moves | a literal query count, measured **with labels created**, under the test environment's `:null_store` |
| 9 | the select filters correctly but never shows what is selected | the frame re-renders the grid and **never the filter bar**, so only a shared link exercises it; no test in the suite asserts on any `/cards` `<select>` | `assert_select "select[name=label] option[selected][value=?]", "ace-spec"` |
| 10 | a one-option select for an empty family | there are no label fixtures, so the default state already renders none — "delete the labels and assert absence" passes against an implementation that never renders it | assert absence with no labels **and** presence once one exists |
| 11 | eight controls overflowing | no system test drives this bar; `flex-shrink: 0` means wrapping does not save it | geometry at 344px (`drive_at`, precedent `deck_row_narrow_test.rb`): every control's right edge inside the bar, and no horizontal document overflow |

**Fixture gap, recorded rather than worked around:** the fixtures do not model the Trainer
over-application case at all — `special_prism_energy_asc`/`_blk` share a name and carry no
`fingerprint`, and `trainer_card` has none while `bosss_orders_meg` does. Row 6 uses the Pokémon
pair instead, which exercises the same key.
