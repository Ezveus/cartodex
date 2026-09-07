# Implementation plan — venue split on the archetype card report (issue #160)

Design record: `docs/superpowers/specs/2026-09-07-archetype-venue-split-design.md`.

Baseline to beat: **1525 runs, 6746 assertions, 0 failures** (`bin/rails db:test:prepare test`,
master at `2132de8`).

This is revision 2. An adversarial pass against revision 1 — "which of these decisions would the
existing suite fail to notice if they were implemented wrong?" — found fifteen gaps, and **four of
them were false claims in the plan itself**, each of which had a test attached that could never
have gone red. They are recorded in §6 rather than quietly deleted, because a reader who only sees
revision 2 would otherwise re-derive them.

---

## 0. Measurements, re-taken before writing a line

Against the dev database (= `prod-2026-09-07-post-online-bulk.sqlite3`, schema `20260905180000`:
1238 standings, 293 events, 48 archetypes carrying a list):

```
buckets(archetype,pool) = 59 : blended 24 · paper-only 12 · online-only 23
decks with standings under BOTH venues = 0   (and 0 decks carry more than one standing at all)
fold matches single grouped count on 59 of 59 buckets
per-archetype whole == summed over pools on 48/48; grand total decks = 1223
default sample: all-online 23 · blended 24 (of 48)
per pool (paper lists / online lists):
  no pool 13/0 · SVI-DRI 68/0 · SVI-BLK 56/0 · TEF-CRI 22/0 · TEF-PBL 278/786
multi-pool archetypes with a blended pool: 9; cells 38, empty 10
```

Every figure the spec cites reproduces **except one**: a `SMALL_SAMPLE` threshold on a venue half
would remove the control from **17** archetypes, not the 18 the spec says — measured under four
readings (lists `< 10`, lists `<= 10`, standings `< 10`, "any pool" instead of the default pool),
all 17. The decision it supports is unchanged, because *Lillie's Clefairy ex* (paper 9 / online 19)
is among the 17 and is one of the four archetypes whose halves genuinely disagree. **Fix the figure
in the spec in the same commit.**

The four motivating archetypes are confirmed as blended default pools: Alakazam 22/18, Teal Mask
Ogerpon ex / Lillie's Clefairy ex 32/18, Lillie's Clefairy ex 9/19, Mega Excadrill ex 14/19.

**And two notes on the page are already false, on the same 23 archetypes.** Both print a sentence
claiming the figures above them mix online with paper, unconditionally, wherever the sample holds
any online row at all:

| component | sentence | measured false on |
|---|---|---|
| `Archetypes::SampleSelector#online_note` | "The card report below counts online and paper lists together." | 23 of 48 |
| `Archetypes::PerformancePanel#online` | "The counts above do not separate online play from paper." | 23 of 48 |

The two sets are the same 23 (*Froslass / Munkidori*, *Joltik box*, *Dragapult ex / Blaziken ex*,
*Dragapult ex / Dusknoir*, …): an archetype whose whole sample is online. One rule repairs both —
print the sentence only when the sample actually blends — and it covers `venue=online` in the same
line. **Revision 1 repaired only the first, and left its twin one panel below.** Both give a test
that is red on `master` before an implementation line exists, which is the only free proof here
that a test measures something.

---

## 1. The frozen contract

```ruby
Archetypes::MetagameScope.call(archetype:, pool_param: nil, venue_param: nil)

ALL    = "all".freeze                     # unchanged, the pool axis's "no filter" value
VENUES = %w[all paper online].freeze      # the venue parameter's values, in select order

Bucket = Struct.new(:pool_id, :online, :standings, :lists, :last_on, keyword_init: true)

Result = Struct.new(
  :archetype, :standings, :listed_standings, :pool, :options,
  :lists_count, :online_lists_count, :unpooled,
  :venue, :venue_options, :venue_selectable,
  keyword_init: true
)

def venue_selectable? = venue_selectable
```

* `venue` is a **Symbol** (`:all` / `:paper` / `:online`); `venue_param` is the String side. Two
  types on purpose, so a comparison against the raw parameter cannot compile by accident.
* `venue_options` is an Array of the existing `Option` struct, in `VENUES` order: All, Paper,
  Online.
* `online_lists_count` keeps its name and meaning — "how many lists of **this sample** are online".

### What must not change

* `SMALL_SAMPLE`, `ALL`, `Option`'s members, `Performance.call(standings:)`,
  `CardStats.call(standings:, grouping:)`. Neither service is edited.
* **`fuller_sample_available?` is untouched.** Revision 1 widened it to
  `(options + venue_options).any?`; that is dead code. `options` always carries an entry equal to
  the selected pool's own total, and `venue_options`' "All" **is** that same total, so the two
  spellings cannot disagree — measured over the **147** reachable `(archetype, pool, venue)`
  states in production, they diverge on **0**. Under `pool=TEF-PBL&venue=paper` on Dragapult ex the
  promise is already true through the pool select ("TEF-PBL — 118 lists" beside a 98-list sample),
  which is what the notice means anyway.
* **The whole pool axis is venue-independent**: `options` and their labels, `selectable?`, and
  `unpooled?`. `unpooled?` is in that list on purpose — it feeds `selectable?`, so scoping it to
  the venue would make the *pool* control vanish when a reader picks Online. The pool note it also
  guards stays true regardless, since it describes how the pool options count and those do not
  move.

---

## 2. Lane A — server

Allowlist:

```
app/services/archetypes/metagame_scope.rb
app/controllers/archetypes_controller.rb
test/services/archetypes/metagame_scope_test.rb
test/controllers/archetypes_controller_test.rb
docs/superpowers/specs/2026-09-07-archetype-venue-split-design.md   (the 18 -> 17 fix only)
```

Do not touch: `app/views/`, `app/assets/`, `test/system/`, `test/components/`,
`app/services/archetypes/{card_stats,performance,index_counts}.rb`.

### A1. `buckets` gains a venue dimension

`group("tournaments.standard_pool_id", "tournaments.online")`, plucking `standard_pool_id`,
`online`, `COUNT(*)`, `COUNT(DISTINCT deck_id)`, `MAX(date)`. Still **one query** — a column added
to a `GROUP BY` on a scan that already runs; 59 buckets become at most 118 rows, folded in Ruby.
The `COUNT(DISTINCT CASE WHEN tournaments.online …)` term disappears: the online list count is now
the `lists` of the online row.

**No boolean normalisation, and no test claiming one.** Revision 1 asserted that `online` arrives
as SQLite's `0`/`1` through an `Arel.sql` pluck, "the same reason `to_date` exists". Measured, that
is wrong: the raw rows are `[0, …]`/`[1, …]`, but SQLite reports a *decltype* for a bare column
reference, so the adapter's `cast_values` hands back `false`/`true` —
`select_all(…).column_types["online"]` is `ActiveModel::Type::Boolean` where
`column_types["MAX(tournaments.date)"]` is the bare `Value` that `to_date` exists for. A
normalisation there would convert nothing and its test could not go red. (An **expression** —
`COALESCE(tournaments.online, 0)`, a `CASE` — would lose the type. So do not write one.)

### A2. The fold, and the honest statement of what it assumes

`pool_rows(pool_id)` returns the at-most-two buckets of one pool; `fold(rows)` sums `standings` and
`lists` and maxes `last_on`. `total` becomes `fold(buckets)`, `pool_buckets` folds per pool
**before** sorting, and `options` reads the folded rows — which is what keeps the pool labels
venue-independent by construction rather than by remembering to.

**The fold over-counts a deck that carries a standing under both venues, and that is a pre-existing
property extended along a second axis, not a new one.** `total.lists` is already
`buckets.sum(&:lists)` today, which double-counts a deck holding standings in two pools. Measured
on production: **0 decks under both venues, and 0 decks carrying more than one standing at all** —
so the sum matches the single grouped count on 59 buckets of 59, and 1223 = 1223 across pools.
Nothing in the schema forbids the shape (`index_tournament_standings_on_deck_id` is not unique, and
two standings legitimately pointing at one deck is documented), so the test names the behaviour
instead of asserting an identity that cannot fail.

Revision 1's "paper + online = the pool's total" test was a **tautology**: both sides come out of
the same fold, so any fold satisfies it. What is testable is the venue-filtered counts themselves,
as literals, and the over-count under the forbidden shape.

### A3. The venue parameter, the clamp, and All formats

```ruby
def initialize(archetype:, pool_param: nil, venue_param: nil)
  @venue_param = venue_param.to_s
end
```

Resolution: a value outside `VENUES` → `:all`; `"all"` → `:all`; `"paper"`/`"online"` → that venue
**if the selected sample holds a standing under it**, else `:all` (the clamp), recorded in the
`Result` and not merely applied to the relation.

`to_s` is kept for symmetry with `pool_param` but its **justification is different and the comment
must say so**: `pool_param` needs it because `.to_i` raises on an Array, while resolution here is
`VENUES.include?`, which answers `false` for `nil`, `["online"]` and `{ a: 1 }` without raising.
So the guard fails closed with or without `to_s`; what `to_s` actually does is *widen* the input to
accept a Symbol (`VENUES.include?(:online.to_s)`), which is wanted for an internal caller and is
the only behaviour a test can pin.

**"The selected sample" means the whole archetype under All formats.** `pool_id` is overloaded —
`nil` means "every pool" as a selection and "the non-Standard bucket" as data — and revision 1 did
not say which one the venue axis reads. It is the **selection**: under All formats,
`venue_options` and `venue_selectable?` are computed over **all** buckets, so they carry the grand
totals. Read as the nil-pool bucket instead, the Venue control would vanish for the 40 archetypes
with no non-Standard event and would read "13 GLC lists" for the other 8 — a reader choosing All
formats would lose the control with no way back but editing the URL. This is the majority state:
**24 of 48 archetypes have a blended All-formats sample.**

The clamp is not rare: every pool other than TEF-PBL holds zero online lists, so 10 of the 38 cells
belonging to the 9 multi-pool archetypes with a blended pool are empty, and
`?pool=<SVI-BLK>&venue=online` is what clicking a pool label under Online produces.

"Holds a standing", not "holds a list", following the pool axis — `options` already renders
`TEF-PBL — 0 lists` for a pool with placements and no typed decklist, and must, because
`Performance` counts placements the card report cannot see.

### A4. `standings_scope(pool, venue)`

Early-return today's exact relation when `pool.nil? && venue == :all`, so the unfiltered page
cannot regress; otherwise `joins(:tournament)` plus a `where` per axis. Rails collapses a repeated
`joins(:tournament)` to **one** `INNER JOIN` — measured — so it cannot duplicate against
`CardStats`' and `Performance`' own joins. Measured cost of those two services on the blended
Dragapult ex / TEF-PBL sample: **9 queries in each of the three venue states.**

### A5. `venue_options` and `venue_selectable?`

Both computed within the current **selection** (a pool, or every pool under All formats), which is
the symmetry: pool labels are venue-independent, venue labels are selection-dependent.

`venue_selectable?` is "the selection holds standings under both venues" — **not**
`venue_options.size > 1`, which is always three. Absent from 35 of the 59 buckets (12 paper-only +
23 online-only), which is the majority shape.

No threshold of its own: a half is an option from one standing. A `SMALL_SAMPLE` threshold would
remove the control from 17 of 48 archetypes including *Lillie's Clefairy ex*, one of the four the
issue was reopened for.

### A6. `online_lists_count`

`venue == :paper ? 0 : online_rows_of(selection).sum(&:lists)`.

**Its test asserts literals, not an equality.** Revision 1's "`lists_count` under `:online`" is a
tautology — both sides are the same sum over the same rows, so it holds for any value, including a
wrong one.

### A7. Controller

One line: `venue_param: params[:venue]`. No `where`, no second service — `MetagameScope`'s opening
comment promises it is "the only place that answers which standings count", and the page's four
printed "N lists" agree *because* one object computes them.

### A8. Lane A tests

Fixtures: **no `tournaments.yml` fixture is `online: true`, and none may become one** — that file's
note and `TournamentStanding`'s `restrict_with_error` cascade make those rows load-bearing
elsewhere. Both test files already build their own online rows (`metagame_scope_test.rb`'s
`online_event`, `archetypes_controller_test.rb`'s `record_standing_for`, whose `online:` already
varies per row). Reuse them.

| test | the wrong implementation it must catch |
|---|---|
| a blended pool's options read the pool total **in absolute terms**, and the identical literal under `venue=online` | `pool_buckets` not folding — two `Option`s for one pool, "TEF-PBL — 98 lists" beside "TEF-PBL — 20 lists". A test comparing two venue states passes with the duplicate in both |
| the three venues' `lists_count` on a blended pool are `[28, 8, 20]` as literals | any mis-scoped filter, in either direction |
| one deck under both venues: the pool total reads 2 where the distinct count is 1, and this is the documented over-count | a claimed identity the fold cannot violate |
| **All formats** on a multi-pool blended archetype: `venue_selectable?` true, and `venue_options` carry the **grand** totals | reading `pool_rows(nil)` as the non-Standard bucket |
| `venue_selectable?` false on a paper-only selection and on an online-only one | `venue_options.size > 1` |
| a clamped venue leaves `Result#venue` `:all` **and** `standings` unfiltered | keeping the parameter in the `Result` and filtering only the relation, or the reverse |
| `?venue=` junk / `""` / `[ "online" ]` / `{ a: 1 }` / `nil` / `:online` → `:all`, `:all`, `:all`, `:all`, `:all`, `:online`, none raising | a `to_sym`/`fetch` resolution; the last case pins what `to_s` actually buys |
| `online_lists_count` is `[20, 0, 20]` across the three venues, as literals | — |
| a venue half below `SMALL_SAMPLE` sets `small_sample?` (paper 8 / online 20) | reading `small_sample?` off the pool total (28) |
| a venue filter narrows `standings` **and** `listed_standings` | filtering only one |
| an archetype with no standing: `venue` `:all`, `venue_selectable?` false | — |

`archetypes_controller_test.rb`:

| test | the wrong implementation |
|---|---|
| `?venue=paper` / `?venue=online` change the denominator and a percentage, on a **blended** archetype | ignoring the parameter |
| `assert_equal 17, capture_queries{…}.size` for `venue=paper` and `venue=online` on a **blended** archetype, each with `assert_select ".archetype-card-row", minimum: 1` | a real extra query. The `minimum: 1` is what stops a silent clamp making the count flat for the wrong reason. Note a duplicated join is **invisible** to a query counter — do not claim otherwise |
| a clamped `?venue=online`: rows render **and** no mode link carries `venue=` | either half alone passes the opposite bug |
| `?venue[]=junk` does not 500 and renders the blended sample | — |
| the venue select renders with `option[selected]` matching the chosen venue | omitting `selected:` — the browser then pre-selects "All" over an Online report, the `AGE_DIVISIONS`/`"open"` trap |
| **`?venue=online` does not print "do not separate online play from paper"** | leaving `PerformancePanel`'s sentence unconditional. **Red on master** for an all-online archetype |
| a Performance figure under `?venue=paper` is the paper count as a literal, and no "Open" division row appears | `Performance` not narrowing with the scope |

**Note on the clamp and the select.** They are mutually exclusive: the clamp fires only when the
chosen venue has no standing in the selection, which is exactly when `venue_selectable?` is false
and no venue select renders. So revision 1's "renders the blended report **and** a select reading
All" names an unreachable state. What is observable is the pair above — rows plus the mode links'
hrefs.

---

## 3. Lane B — view

Allowlist:

```
app/views/components/archetypes/sample_selector.rb
app/views/components/archetypes/performance_panel.rb
app/views/components/archetypes/card_report.rb
app/views/components/styleguide/page_view.rb
test/components/archetypes/sample_selector_test.rb
test/controllers/styleguide_controller_test.rb
test/system/archetype_metagame_test.rb
```

Do not touch: `app/services/`, `app/controllers/`, `app/assets/stylesheets/`, `test/services/`,
`test/controllers/archetypes_controller_test.rb`.

**`test/components/archetypes/sample_selector_test.rb` exists, has 14 tests, and revision 1 never
mentioned it.** Its helper builds `MetagameScope::Result` by keyword, and a `Struct` with
`keyword_init: true` **does not raise on a missing keyword** — it stores `nil` (only an *extra*
keyword raises `ArgumentError`). Measured. So leaving the stub alone silently gives
`venue_selectable` `nil`, every venue branch stays falsy, and no venue regression is observable in
any of the 14. The stub gains the three members.

**No CSS.** `.deck-filters` is already `display: flex; flex-wrap: wrap; gap: .5rem` and
`.archetype-sample-label` is already the flex item carrying a label and its select, so two of them
sit side by side above the breakpoint and wrap below it. The system test asserts it at both sweep
widths anyway — `.archetype-category-header` and `/archetypes`'s row note each cost this repository
one bug already.

### B1. The two selects

Both inside the one existing `<form>`, Sample then Venue, each in its own
`label.archetype-sample-label`, submitted by the same `card-filter` controller. The hidden `group`
field is unchanged.

Three guards, and they are **separate**:

* the form renders when `selectable? || venue_selectable?` — **or** and not **and**: an archetype
  with one pool and both venues (15 of the 24 blended ones) would otherwise lose the form
  entirely;
* the Sample select renders when `selectable?` — widening it to the form's guard renders a
  `<select name="pool">` of one option, the thing `Result#selectable?` exists to prevent;
* the Venue select renders when `venue_selectable?` — widening it to `selectable?` renders
  "Online — 0 lists" on a paper-only archetype.

The block's outer guard becomes
`selectable? || venue_selectable? || small_sample? || online_lists?`.

`selected:` for the venue select is `@scope.venue.to_s`. Omitted, `Ui::FilterSelect` renders no
`selected` option and the browser pre-selects the first — "All", over an Online report. That is the
`AGE_DIVISIONS`/`"open"` precedent, and it is what the assertion pins; the clamp is *not* the
reason, since the two values can only differ in states where no select renders.

### B2. Both false notes, one rule

`SampleSelector#online_note` prints its second sentence only when `online_lists_count <
lists_count`. `PerformancePanel#online` prints "The counts above do not separate online play from
paper." only when `online_standings_count < standings_count`. Same rule, same 23 archetypes, both
red on `master`.

Under `venue=paper` both withhold themselves through their existing `online_lists?` / `online?`
guards, which is right: the selects already read "Paper — 98 lists".

### B3. The mode links carry the venue

`CardReport#path_for` re-emits `venue` beside `pool` and `group`, read off `@scope.venue` and never
off `params` — and it emits **nothing** when the venue is `:all`, so a default does not enter every
copied URL. This is the assertion that distinguishes a clamp recorded in the `Result` from one
applied to the relation alone.

### B4. Styleguide

`sg_metagame_scope` gains `venue: :all`, `venue_selectable: true` and three `venue_options`.
Because a missing keyword does **not** raise (above), `/styleguide` would otherwise render one
select with all nine of its tests green — `StyleguideControllerTest` asserts no `select` in the
archetype section today. So it gains one: `assert_select "select[name=venue]"`.

### B5. Lane B tests

| test | the wrong implementation |
|---|---|
| component: one pool + both venues renders `select[name=venue]` **and no** `select[name=pool]` | the form guard as `&&` (first line), and a Sample select of one option (second) |
| component: an all-online sample does not print "counts online and paper lists together" | the unconditional sentence. **Red on master** |
| system: choosing Online changes the denominator and a percentage, and the select comes back reading Online | omitting `selected:` |
| system: changing the venue **keeps the pool** (`?pool=all` survives) | the form not re-emitting `pool` — the `label`/`role` asymmetry, one param tested and not its twin |
| system: switching venue keeps the grouping mode | dropping the hidden `group` field |
| system: the two labels are **adjacent** above 768 px and **stacked** below it, on bounding boxes | a wrapper element, or losing `flex-wrap` |

---

## 4. Integration and verification (mine, not a lane's)

Both lanes are **write-only** — they run no tests; I run the suite serialised, because one
worktree has one `storage/test.sqlite3` and two agents in it cascade into `SQLite3::BusyException`.

```bash
bin/rails test                                     # > 1525 runs
bin/rails test:system
SYSTEM_TEST_VIEWPORT=mobile bin/rails test:system
bin/rubocop <only the files written>
bin/brakeman --no-pager
bin/importmap audit
```

Then: read the **17** off `capture_queries` for unfiltered / `venue=paper` / `venue=online` in both
grouping modes; sabotage every new test and record red-then-green; and open the browser on
**Alakazam** (22 paper / 18 online, whose blended report prints `Dunsparce` near 50 % and describes
neither half), reading the two selects by geometry at 1400 px and 390 px.

---

## 5. Out of scope

A tier control (the paper half spans three tiers, one of which is the value the importer forces on
every online event, so tier files a national with the weeklies). Any win rate. `/archetypes`, which
names the blend already and offers no controls. A venue axis anywhere but this page.

---

## 6. What revision 1 got wrong, so it is not re-derived

Four claims, each with a test attached that could not have gone red:

1. **`Bucket#online` needs normalising from `0`/`1`.** It does not; `pluck` casts through the
   column's decltype and returns `false`/`true`. §A1.
2. **`fuller_sample_available?` must consider `venue_options`.** Dead code — 0 divergence over 147
   reachable states, because `venue_options`' "All" is the pool total that `options` already
   carries. §1.
3. **`venue_param.to_s` is what stops a non-String raising.** Nothing raises; `VENUES.include?`
   fails closed on its own. What `to_s` buys is Symbol acceptance. §A3.
4. **"paper + online = the pool's total" is a testable identity.** Both sides come out of the fold.
   The testable statements are the literal counts and the documented over-count. §A2.

Plus three things it named and did not carry through: `PerformancePanel`'s twin of the false note
(§0, §B2), the All-formats × venue state (§A3), and
`test/components/archetypes/sample_selector_test.rb` existing at all (§3).
