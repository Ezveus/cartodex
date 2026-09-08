# The archetype catalog and one archetype's metagame report

`/archetypes` and `/archetypes/:id` — which standings count, what the deck report says, and the three things the page deliberately refuses to say.

This file carries detail that used to sit inline in `CLAUDE.md`. Everything here is a decision with a measurement behind it — read it before changing the code it covers, because most entries record something that was already tried and rejected.

Design records:

- `docs/superpowers/specs/2026-09-05-archetype-metagame-stats-design.md`

---

**The archetype catalog and one archetype's metagame report** (`/archetypes`, `/archetypes/:id`)
are the aggregation the two import sections deferred
(`docs/architecture/limitless-imports.md`), and they add **no column** — everything they
read already exists. Four services, all two levels deep: `Archetypes::MetagameScope` (which
standings count), `CardStats` (the deck report), `Performance` (the record), `IndexCounts` (the
listing's numbers, in one grouped query). The design record is
`docs/superpowers/specs/2026-09-05-archetype-metagame-stats-design.md`; what is not obvious from
the code:

**Three things the page refuses to say, each measured rather than assumed**, because each is
something a later reader will be tempted to add. There is **no metagame share**: a sheet imported
from one archetype's Limitless page holds only that archetype's rows, so the database never sees
the field and cannot produce a fraction of it — every figure is worded *recorded in Cartodex*, and
the index's ordering is "most recorded", a statement about who has run an import. (Both of those
sentences describe what *this database* can compute, and they stayed true when a second source
arrived: `play.limitlesstcg.com/decks` publishes a `Count / Share / Score / Win %` per archetype
over its own online field, and none of it is imported — republishing somebody else's aggregate
under a heading reading "recorded in Cartodex" is a different claim, and a different decision.)
There is **no win rate**, and the reason moved rather than went away: the paper source publishes
no record at all, so on the production data exactly **1 of 94** standings carried a W-L-T, the one
somebody typed — while `play.limitlesstcg.com` publishes one on every row, and the online importer
writes all three. So the columns are now *filled on part of a blended sample and empty on the
rest*, and a rate computed over that would describe the online rows alone under a heading covering
both. And there
is **still no ACE SPEC category**: the label introduced in
`docs/architecture/card-labels-and-roles.md` is an annotation on the name line,
not a section, and the type-mode categories stay a partition of the list whether or not a row in
it carries one. A **functional** grouping (Gust, Switch, Recovery) is a different answer and now
exists — as a second mode of the same report, `?group=role`, whose sections deliberately overlap
and are therefore not a partition of anything; see the role paragraphs in
`docs/architecture/card-labels-and-roles.md`. What changed is the flag itself, not
the report — nothing here could have derived it: every ACE SPEC carries rarity `"Ultra"` and so do
93 ordinary Trainers, the string "ACE SPEC" appears in `effect` on **0 of 4720** cards, the
individual card page carries it no better than the search does, and what a card *does* is not
scraped at all. The categories are exactly what
`card_type` plus the scraped `subtype` know — Pokémon, Supporter, Item, **Tool, Stadium**, Special
Energy, Basic Energy — plus an **`other` bucket that is rendered, not dropped**: it is unreachable
on today's catalogue and exists so a Trainer subtype the scraper learns tomorrow surfaces as a
labelled bucket instead of vanishing from a report that still sums to a plausible-looking 60. Tool
before Stadium, because that is the order `Decks::ShowView::TRAINER_SUBTYPE_LABELS` prints a
decklist in and a member reading both pages should not have to re-find the sections. Both
spellings of the tool bucket are mapped (`Cards::Fetcher#parse_subtype` can emit `"Pokémon Tool"`;
all 76 tools in the catalogue carry `"Tool"`) — a pair `TRAINER_SUBTYPE_LABELS` did **not** carry
until this feature. It knew `"Pokémon Tool"` alone, so all 76 of them fell under "Other" on every
deck page; the fix (both keys, and grouping on the label rather than on the raw subtype so one
deck holding both spellings gets one section instead of two identically titled ones) is a
pre-existing bug closed in passing here. `Decks::PublicShowView#trainer_section` still iterates
the raw pairs and would print two "Tool" headings for such a deck — the visitor's half of the same
fix, outstanding.

**A selector of one option is not a choice — and neither is one offering two labels for one
sample.** `MetagameScope::Result#selectable?` is what drops the control entirely
(`Archetypes::SampleSelector` renders no form when it is false), and it is deliberately **not**
`options.size > 1`: an archetype with standings in exactly one pool and nowhere else gets
"TEF-PBL — 4 lists" beside "All formats — 4 lists", two labels for the same four lists, and on the
production data that is the common shape rather than a corner case. It is
`pool_options > 1 || (pool_options == 1 && unpooled?)` — one pool *plus* a GLC or Expanded event
is a genuine choice, while an archetype whose every standing sits outside Standard has
"All formats" as its **only** option however many events that spans, so `unpooled?` cannot answer
on its own without rendering a `<select>` of one. `fuller_sample_available?` is the other half of
the same honesty: the notice under the selector promises a fuller sample one click away, and that
promise is false on the sample that is already the largest. `Result` carries no `standings_count`:
it had one, nothing but the styleguide's stub ever read it, and the rule is the one
`DeckPolicy::Scope` was removed under — the relation is there for a caller who wants the number.

**The report is keyed on `cards.fingerprint`, and one measurement shows both halves of why.**
Across those 93 lists there are **81 distinct card ids, 72 fingerprints and 70 names**: 81→72 is
the key folding nine reprints into the card they are, and 72→70 is the key *refusing* to fold —
**Hoothoot** is three genuinely different cards there (TEF 126 at 70 HP, PRE 77 at 80 HP, SCR 114
at 70 HP with other attacks) that a player picks between, and keying on the name would have read
"Hoothoot 100 %, 1-2 copies" and hidden the choice, the same conflation `Decks::ArchetypeDetector`
was moved off names to avoid. The key in the SQL is not the bare column but
`CardStats::GROUPING_KEY`, `COALESCE(cards.fingerprint, 'card:' || cards.id)`, and the difference
is not cosmetic: SQL gathers **every** NULL into one group, so `GROUP BY cards.fingerprint` folds
two unfingerprinted cards in one list into a single row whose copies are their sum and whose name
is whichever `MIN()` picked — a Supporter reported at 6 copies, the other card gone from a report
that still sums to a plausible 60, and nothing raised. `compute_fingerprint` is a `before_save`,
so only `update_column`, `insert_all` or a fixture can produce such a card; keeping it visible
under its own id is deliberate, since dropping it is the same silent disappearance in a different
costume — the state `Decks::ArchetypeDetector` refuses to match on and `Archetypes::FingerprintSync`
reports rather than writes. That grouping scatters Hoothoot's three rows in a table sorted by
inclusion, so rows are grouped by **name** inside a category and ordered by the share of lists
playing *any* version — and that share is a **distinct count of lists, never the sum of the
printings'**, computed as the **union of the entries' own list sets** rather than by looking a
name up in a second index: Hoothoot's three versions total 111.9 % across a name played by
73.1 %, because a list may play two of them. Taken from the entries the group holds, the number
above a set of sub-rows is a fact about those sub-rows by construction; keyed on a name the query
chose and read back by the name of the printing the report chose, the two halves could disagree,
and an unfingerprinted card showed a group at 0 % sitting above its own 100 % sub-row. The
printings inside a group are ordered by `set_number.to_i` before `.to_s`, because `set_number` is
a String holding a number most of the time and `"SV107"` the rest — sorted lexically, "114" comes
before "77". The page says so in words; presenting the sub-rows as an additive
decomposition is the one mistake this layout invites. Copies stay on the printing and never on the
name for the same reason — a "1-4" merged from two versions describes no list — and a split name
is never marked *fixed*, since which printing is still a choice. That is not contradicted by the
section heading's own range below: merging two cards' ranges invents an interval, while a range
taken over per-list *totals* is a fact about lists that were actually played. Quantities are summed per
`(deck, fingerprint)` **before** the histogram: two printings of one card in one list are two
legal `DeckCard` rows (`(deck_id, card_id)` is UNIQUE) and one card in that list; counted
separately the card appears in more lists than exist, each at a fraction of its copies, and
nothing raises. Measured occurrences in production: zero, because Limitless normalises what it
publishes — the step stays for the hand-typed lists, which are under no such discipline. A mode
tie is reported as a tie, never resolved in silence.

**A section heading says how many copies of it a list plays, and that number could not be derived
from the per-card ones** (#156). Summing the entries' minima and maxima counts cards no single
list plays together: measured, all-formats Pokémon reads 39-57 that way against a true 16-23, a
floor above the true ceiling, and TEF-CRI Item reads 24-28 against 11-17. The honest figure sums a
category **within each list first** and then takes the range across lists, which is a fold over
`rows` — `(deck, card-key, copies)` — that `CardStats` already holds, so it costs no query and
`/archetypes/:id` stays at seventeen. `Archetypes::CopiesText` is the module both grains print
through (`Entry` and `CategoryGroup` carry `min_copies`/`max_copies`/`modes`/`single_quantity?`/
`tied_mode?` under the same names for exactly that reason), and `CardStats.modes_of` is one
definition of "every value that ties for most frequent" rather than two.

Three decisions, each of which a later reader would otherwise undo. **Zeros are counted, unlike
`Entry`**: an entry's range is the range *when played*, which is right for a row printing its
inclusion percentage beside it, while a heading carries no such figure — and Tool is played by 1
list of 22, 12 of 68 and 13 of 106, so "1 copy" over those samples is true of the card and false
of the sample. Making the two rules agree is undoing this, not tidying it. **Both grouping modes
get the figure**, even though role sections overlap and their copies therefore add past 60 (+1 to
+8, from three to seven dual-role cards per sample): each section's own total is still true of
that section, and the functional grouping is the half the reference reports print first. **And the
page says the figures do not add up**, in both modes, suppressed at one list where there is no
range to disclaim. That sentence says *figures* and not *ranges* deliberately: the column inviting
the addition is the **mode**, which sums to 60 or 61 across all eight production samples and on
the three largest describes a 60-card profile no list played. It also names the zeros rule,
because the page shows both rules a line apart — TEF-CRI renders `Stadium · 1 card · 0-4 copies`
directly above that section's only card at `95.5 % of lists · 3-4 copies` — and it separates the
card count, which is over the whole sample, since all-formats reads `Pokémon · 32 cards · 16-23
copies`. What it deliberately does **not** flatten: "most often" is a weaker claim on a heading
than on a card row (median share 92.1 % for a row, 32-87 % for the six headings beside it) and is
worded identically, because dropping it would lose the one figure saying Tool is usually not
played at all.

**The heading's two figures live in a wrapper, and it is load-bearing** —
`.archetype-category-header` is `display: flex; justify-content: space-between`, so a third child
is not placed beside the second but spread to the far end with the card count parked in the
middle. It is a *cousin* of the `/archetypes` index bug rather than the same one, and the
difference decides where to test it: that container did not wrap, so the note overflowed and grew
the row, which 390px catches; this one wraps, so nothing overflows and the damage is worst at full
width where there is room to spread into — at the narrow end the items may wrap onto separate
lines and a stacking assertion would pass with the bug still there. The system test therefore
claims **adjacency**, at both sweep widths. `.archetype-range-note + .archetype-overlap-note` is
the one selector in the archetype CSS block that buys weight rather than scope, and that block's
preamble names it: an unconditional negative `margin-top` on the overlap note would pull it under
the summary in the one-list case, where the range note above it is withheld.

**Every card row names a printing and links to it, and the fold is what made that need a
sentence.** `Buddy-Buddy Poffin (TEF 144)` is `Card#printing_label`, the printing
`representative_ids` picks — more lists than any other, lowest card id breaking a tie so the page
does not change between two loads. The anchor is a plain `a` over
`Rails.application.routes.url_helpers`, not `link_to card_path`, for the reason
`CardReport#path_for` is: this component tree is unit-tested through a bare Phlex `.call`, where
`Phlex::Rails`' `LinkTo` and `Routes` delegate to a nil `view_context` and raise. It carries **no**
`data-turbo-frame="_top"`, unlike `Ui::ArchetypeBadge`'s anchor — measured rather than assumed,
since the page does render one frame (`search_results`, the layout's spotlight) and it holds
neither the report nor any row, so `closest("turbo-frame")` on one of these anchors is null. That
also gives this file's nested-anchor lesson (below, `Decks::ClassificationBadges`) a second
instance: `assert_select` parses HTML4 and nests anchors happily, so a future clickable wrapper
around a card row would leave the controller test green — only
`archetype_metagame_test.rb`'s click test tells the two outcomes apart. Opening the pages to
visitors costs nothing extra here: `/cards/:id` is already public.

**A split name line carries neither a code nor a link, and a folded row carries both plus a
sentence.** The first is the third application of the rule that already withholds the *fixed* flag
and the type labels from a split name: it covers two or more genuinely different cards (`Applin`
and `Charcadet` reach four), so one printing's code would name one member as if it were the group.
Its sub-rows are the card rows and carry both. The second is the case that rule does *not* cover
and that the code made visible — `GROUPING_KEY` is printing-independent, so a **non-split** row can
name one printing while its share, its copies and its *fixed* flag count every reprint of that
card. Measured on the dump: **16 distinct card keys** fold two printings a list actually played (53
split name groups over 36 distinct names sit beside them), worst `Ultra Ball (MEG 131)` reading
"100 % of lists (154)" where 56 of those lists played SVI 196 — a 36-point gap between the line and
the code on it; and two such rows carry *fixed*, whose title says "played by every list, always in
the same number", true of Fezandipiti ex and false of the SFA 38 beside it. So
`CardStats::Result#reprinted_cards` counts the **distinct cards** in that state — over `entries`,
not over rendered rows, or role mode reports one card twice — and `CardReport#reprint_note` says it,
**only where the sample holds an instance**: 242 of the 246 reachable samples hold none, and the
pool note's rule is that a disclaimer with no instance is one nobody reads. It costs no query:
`printings_played_by_key` is the size of the group `representative_ids` already picks from, so
`CardStats` stays at five and the page at seventeen. Two things about its wording are decisions.
It says *more lists than any other* and not *most*, because the pick is a **plurality**: no fold in
the dump has three printings, but 371 catalogue fingerprints do, and one import reaches it. And it
names the *fixed* flag beside the share and the copies, because that flag is the one of the three
that is not itself a number — `Entry#fixed?` is derived from both — so a sentence covering only the
two figures left a reader to guess which of them a "fixed" badge came from, on the two rows where
its title is false of the printing printed beside it.

**The links have no affordance but `:hover`, and that is the one thing here no test can see.**
`.archetype-card-link` is `color: inherit; text-decoration: none` with a hover underline — two of
`.deck-compare-card-link`'s five declarations, which is `/decks/compare`'s existing answer for a
list of linked card names. Its `display: flex`/`align-items`/`gap` are **inert** on an anchor
holding one run of text (measured: identical boxes with and without them at 1400px and at 344px),
so copying them would assert a layout this element does not have. Nothing in `test/` reads a
computed style, so reverting the rule to a bare anchor is a mutation the whole suite survives —
recorded here rather than annotated as covered. Two consequences are open rather than settled:
126 links on one page are indistinguishable from body text until hovered, and there is no hover on
the touch side of the breakpoint; and the anchors are 19-20px tall against WCAG 2.5.8's 24px, in
rows that are themselves 88-113px. Both are properties `/decks/compare` already has, so changing
them is one decision about two pages.

**The performance panel counts all standings; the card report counts only the listed ones**, which
is why `MetagameScope` exposes two relations rather than letting one number stand for both — a
placement is a result whether or not anybody typed the decklist. `unlisted_count` and
`unplaced_count` are the two gaps that follow, named on the page rather than left as subtractions:
`by_placement` has no band for "unknown", so its column sums to `placed_count` and not to
`standings_count`. Its placement bands are fixed
(1st, 2-4, 5-8, …) and deliberately **not** `Tournament::TOP_CUT_BANDS`, which maps an *attendance*
to a cut size for `TournamentEntry#top_cut_size`: telling whether a placement made the cut needs
the event's field size, and the importer writes none — all three `*_participant_count` columns are
nil on every imported event. `by_division` walks `TournamentStanding::DIVISIONS` because
`group(:division)` comes back alphabetical (junior, masters, senior) while players read junior,
senior, masters — the correction the standings sheet had to make in SQL for its page boundaries.

**Public, and it took seven edits and not three** — the list lived in the comment atop
`ArchetypesController` as a to-do before it shipped, produced by applying the obvious three and
reading what broke *and what did not*, and it is kept there now as the record of what it cost.
Three make the route reachable and are each covered by a test that goes red without them: the
resource sits outside `authenticate :user`, `include PubliclyReachable` with
`publicly_reachable :index, :show`, `ArchetypePolicy#index?`/`#show?` answer `true`.
**Four more decide what a visitor then sees, and no test would have reported any of them
missing**: the per-IP `rate_limit … unless: -> { user_signed_in? }` at
`tournaments#index`'s 60/min (absent before, because no anonymous request could reach the route,
and a limiter nobody can exercise is a limiter nobody knows works); `nav_link "Archetypes"` in
`Ui::PublicNavbar`, without which a visitor on those pages lights **zero** navbar entries, a hole
`NavbarActiveSectionTest` could not see because it named no visitor archetype page;
`Search::Global#archetype_scope`'s `Archetype.none` branch, whose trap is the opposite kind — its
test kept *passing* while defending a rule that had become false, so it was inverted in the same
commit; and the two archetype links a public page used to withhold, `Tournaments::Standings::Row`'s
`if @viewer.present?` guard and `Decks::PublicBadges` (which passed no `href:` at all) — the
standings sheet and a shared deck are both public, and a link to a sign-in wall is worse than no
link, right up until the wall is gone. `Ui::ArchetypeBadge`'s optional `href:` stays opt-in, and
its anchor carries `data-turbo-frame="_top"` — the breakout belongs to the component and not to a
call site, because every surface that passes an href renders it inside a Turbo Frame, and
frame-scoped the click swaps that frame for Turbo's missing-frame error instead of navigating;
only a system test tells those two outcomes apart, since the markup is identical and a request
test sees a 200 for a page nobody reaches. **`Decks::PublicBadges` needed a `linked:` keyword and
not an href**, for `Decks::ClassificationBadges`' own reason reaching a second component: two of
its three callers render it inside an anchor (`Decks::DeckCard`'s `a.deck-item-link`,
`Home::DashboardView`'s showcase tile), and measured with an unconditional href the description,
the card count and the whole badge row fell outside the deck's link — see
`docs/architecture/public-surface.md`. `assert_select` parses HTML4 and nests anchors happily, so
the guards read `Nokogiri::HTML5`, and they assert containment *before* emptiness because the
parser makes the escaped anchor a sibling. `Search::Global`'s fifth group prefixes its option ids
`spotlight-option-archetype-` for the reason `shared_decks` had to. The two archetype rows in
`public_access_test.rb` moved from `owner_only_gets` to `public_gets`, and three tests asserting
the old refusal turned round with them — what the move gives up is the signed-in half, which is
what exercises `verify_authorized`; a missing `authorize` is still caught, because a public
request halts no `before_action` and so reaches the concern's `after_action`.

**The address is a slug of the name, and the name is the member cards' unless somebody typed
one.** `/archetypes/dragapult-ex`, from `archetypes.slug` — `name_normalized`, parameterized; a
stored, NOT NULL, UNIQUE column recomputed `before_validation` on every save, so a rename moves
the URL and nothing records the old one. It is stored rather than computed per request because
`parameterize` is Ruby: `find_by!(slug:)` stays the one indexed query `find` was, and the page's
17 are unmoved. `assign_slug` is declared **after** `auto_generate_name`, which is load-bearing —
that callback is what supplies the name when nobody typed one, so a slug computed first would be
blank, and blank is refused, which would 422 every `Api::ArchetypesController` create. Two
refusals, both reported on `:name` because that is the only field the admin form has: a collision
(measured, two pairs of the catalogue's 1806 card names parameterize alike, both Nidoran
gender-symbol pairs, and neither leads an archetype) and a blank (zero instances; #111 is what
reaches it). `to_param` returns `slug_in_database || slug` and **not** the in-memory value: a
refused rename leaves the rejected name's slug on the record, which in the one case the
uniqueness validation exists for is *another archetype's*, and the re-rendered admin form then
posted to that archetype's URL and renamed the wrong row. Full record in
`docs/superpowers/specs/2026-09-08-public-archetypes-and-slugs-design.md`.

**No cache, and the threshold was written before the measurement.** On a synthetic 1500-list
archetype (39 000 `deck_cards` rows): `MetagameScope` 4 queries / 15.6 ms, `CardStats` 3 / 137.3 ms,
`Performance` 4 / 6.1 ms, `IndexCounts` 1 / 2.0 ms — ≈161 ms, and the count does
not move with the sample. `CardStats` is **5** queries — rows, deck ids, representative printings,
those printings' cards, and the label join — so the total is fourteen; the fifth arrived when
`lists_count` stopped being derived from the rows already fetched, it reads one archetype's
standings through `index_tournament_standings_on_archetype_id`, and the timings above predate it.
(This paragraph said "4" and "thirteen" from the day it was written; the count was five even
then.) The honest version key for a cache entry would be a `MAX(updated_at)`
over the archetype's standings, the kind of unindexed aggregate `Card.filter_values` had to be
corrected away from. `CardStats` is 85 % of the cost and is where a cache would go if the
collection grows past roughly twice that size.

**The sample also splits by venue, and that axis is the pool axis's argument on a second
dimension** (#160). `MetagameScope.call(archetype:, pool_param:, venue_param:)` — a second
`<select>` labelled **Venue** (All / Paper / Online, each carrying its list count) in the same
`<form>` as the pool one. It is the pool scoping's own reasoning applied again: `buckets` grouped
on `standard_pool_id` alone, so an online weekly and a Regional anchored to the same pool land in
one bucket. Measured on Alakazam (TEF-PBL, 22 paper / 18 online), **12 cards of its blended report
print between 40 % and 60 % and every one describes neither half** — Dunsparce reads 50.0 %
blended against 86.4 % paper and 5.6 % online, an 80.8-point gap. Nine archetypes now hold ≥8
lists on both sides.

**The axis is venue and deliberately not tier**, which looked like a proxy for it and is not: the
paper half spans **three** tiers and one of them is `other`, exactly the value
`Tournaments::StandingsImportPlan` forces onto every online event — so a tier control files *Japan
Championships 2026* with the weeklies and splits the sample six ways where the measured problem is
already that one side falls under `SMALL_SAMPLE`. Tier is a refinement *within* the paper half, and
its own issue.

`buckets` gains `tournaments.online` as a second `GROUP BY` column — still **one query**, the row
count at most doubling (59 buckets, ≤118 rows) — and the old
`COUNT(DISTINCT CASE WHEN tournaments.online …)` term disappears, since the online list count is
now the `lists` of the online row. **`online` needs no cast and must not be given one**: SQLite
reports a decltype for a bare column reference, so `pluck` hands back `true`/`false` (measured:
`select_all(…).column_types["online"]` is `ActiveModel::Type::Boolean` where
`column_types["MAX(tournaments.date)"]` is the bare `Value` that `to_date` exists for) — wrapping
it in a `COALESCE` or a `CASE` is what would lose that and return a `0` that is truthy in Ruby.

**Three things on the page are scoped to the venue and three deliberately are not**, and the split
is per *reader* rather than per word. `unpooled?` is venue-independent because `selectable?` reads
it; `unpooled_in_sample?` is the venue-scoped twin that only the pool note reads, since an
archetype whose one non-Standard event is paper printed "their lists are counted under All formats
only" under Online about a list that venue does not hold — 21 such states over 7 archetypes.
`all_formats_lists_count` is the same shape for the card report's empty state, whose "try All
formats" has to be true *of this venue* because the one form carries the venue along with the
click; it also names the venue as the other direction worth trying, which `options` cannot see at
all.

**The pool axis is entirely venue-independent, and `unpooled?` is inside that rule.** Pool labels
do not move when a venue is chosen (`SVI-BLK — 56 lists` reads 56 under Online), which is honest
only *because of* the clamp: clicking it resets the venue and shows 56. Venue labels, symmetrically,
count within the current selection. `unpooled?` stays unscoped because it feeds `selectable?`, so
scoping it would make the *pool* control vanish as a side effect of picking a venue — and the note
it guards describes how the pool options count, which does not move. `pool_buckets` **folds** its
at-most-two rows per pool, which is what makes that hold by construction: unfolded, a blended pool
offers "TEF-PBL — 98 lists" beside "TEF-PBL — 20 lists" in one `<select>`.

**The fold over-counts a deck holding standings under both venues, and that is a pre-existing
property extended along a second axis rather than a new one** — `total.lists` has always been
`buckets.sum(&:lists)`, which double-counts a deck across two pools. Measured: **0 decks under
both venues, and 0 decks carrying more than one standing at all**, so the fold matches the single
grouped count on 59 buckets of 59 and 1223 = 1223 across pools. Nothing in the schema forbids the
shape, so a test **names the behaviour** rather than asserting an identity the fold cannot violate
— both sides of "paper + online = the pool total" come out of the fold, so any fold satisfies it.
The venue-filtered counts the page prints are exact either way, each being a single cell. What the
second axis changed is the *reach* and not the existence: before it a selected pool was one bucket
and only "All formats" folded, so the default view was exact; now a selected pool folds two cells,
so that shape would break the four counters on the default view too.

**The clamp is recorded in the `Result`, not merely applied to the relation**, and it is not rare:
every pool other than TEF-PBL holds zero online lists, so 10 of the 38 cells belonging to the 9
multi-pool archetypes with a blended pool are empty, and `?pool=<SVI-BLK>&venue=online` is what
clicking a pool label under Online produces. **The clamp and `venue_selectable?` are mutually
exclusive** — a clamp fires exactly when one venue holds nothing, which is when the control is
dropped — so "an Online select over a blended report" is unreachable and what a test can actually
observe is the pair: rows render, and no mode link carries `venue=`. `CardReport#path_for`
re-emits the venue off the **scope** and emits nothing at `:all`, so a default never enters a
copied URL. `venue_selectable?` is "the selection holds both venues", never `venue_options.size >
1` (always three) and never "more than one non-empty cell" — the two agree for a single pool, whose
cells *are* its venues, and diverge under "All formats", where the cells span pools. That was a
live defect: one archetype with two paper-only cells was offered "All — 2 lists / Paper — 2 lists /
Online — 0 lists", two labels for one sample plus a dead option that clamps back when clicked.
`venue_present?` is now the one definition both the clamp and the predicate call. Absent from 35 of
the 59 buckets. **No threshold on a half**: `SMALL_SAMPLE`
would remove the control from 17 of 48 archetypes *including Lillie's Clefairy ex* (paper 9 /
online 19), one of the four the issue was reopened for. `fuller_sample_available?` is **unchanged**
— widening it to consider `venue_options` is dead code, since `venue_options`' "All" is the pool
total `options` already carries; measured over the 147 reachable `(archetype, pool, venue)` states,
they diverge on 0.

**"All formats" reads `pool_id: nil` as a selection, never as the non-Standard bucket**, which is
the one place that overload matters: read the other way, the Venue control answers over the GLC
bucket alone — vanishing for the 40 archetypes with no non-Standard event and reading "13 GLC
lists" for the other 8 — so a reader choosing All formats loses the control with no way back but
the URL. 24 of the 48 archetypes have a blended All-formats sample, so it is the majority state.

**The placement breakdown is a leaderboard on the online side, and that is the one thing the venue
axis had to start saying out loud.** `play.limitlesstcg.com/decks/<slug>` publishes *best finishes*
and the importer de-duplicates per player keeping the best result, while the paper source is an
event's whole results page — so measured over the placed standings, **online is 20.2 % firsts and
42.9 % top-4 (799 rows) against paper's 0.9 % and 4.3 % (439 rows)**, and the rows are genuine wins
rather than an import bug. Left unsaid, "By placement: 1st 18 of 20" reads as a win rate on a page
that refuses to print one. `PerformancePanel#leaderboard_note` says it whenever the sample holds an
online row at all, blended or not — a blend is the same distortion in smaller proportion, and the
sentence above it already gives the proportion. This is **not** a consequence of the venue axis (23
of 48 archetypes open on an all-online sample, so the column already read this way) but the axis is
what removed its last cover: the sentence beside it had to stop claiming the counts blend, which
left that state qualified by nothing until this note.

**The Sample select's own label asserts a sample size it stops delivering under a venue, so the
page says so.** The pool options are venue-independent by design, so the number beside the pool is
the pool's whole size while the report covers one half of it — and **the clamp does not rescue
that**, which is what an earlier version of this paragraph claimed: it fires only where the target
cell is empty, so it covers exactly the options that cannot lie. Measured, 78 of the 171 rendered
pool options do not deliver their own label on a click, and "All formats" is structurally on the
wrong side of it (it always holds a standing in the current venue, or the reader would not be in
that venue); worst gap, Dragapult ex at `pool=all&venue=online`, "All formats — 174 lists" selected
above a 20-list report. `SampleSelector#venue_note` names the real figure instead. The alternative
that makes the label literally true — giving the Sample select its own form so a pool change resets
the venue — is a different decision about what a click does and is left open.

**Two notes on this page were already false, on the same 23 of 48 archetypes**, and one rule
repairs both: print the "these figures mix the two" sentence only when the sample really holds
both. `blended?` lives on **both** `Result`s rather than in the two components, beside every
predicate like it, because two components computing one rule over two populations is how the halves
of a page come to disagree. `SampleSelector#online_note`'s *"The card report below counts online and paper lists
together."* and `PerformancePanel#online`'s *"The counts above do not separate online play from
paper."* were unconditional inside their `online?` branches, so every archetype whose whole sample
is online — 23 of them — was told the figures blended paper lists that do not exist, the panel's
sitting directly under "every event counted above" and contradicting it. Both tests are red on
`master` before an implementation line exists, which is the only free proof in the feature that a
test measures something. `Archetypes::Performance` needs no other change: it reads
`@scope.standings`, so it narrows with the venue for free, and its `division` breakdown is what
proves it did — an online row carries `division: "open"` and a paper one an age division.

**Cost: 17 queries, unchanged, measured and not asserted** — the three services are **13 queries
in each of the six `(venue, grouping)` states** on Alakazam's real sample, and `standings_scope`'s
`joins(:tournament)` cannot duplicate against `CardStats`' and `Performance`' own (Rails collapses
a repeated association join to one `INNER JOIN`, so a query counter could never see it either way).
**No CSS**: `.deck-filters` is already `flex-wrap: wrap` with `.archetype-sample-label` as its flex
item, so two labels sit side by side above the breakpoint and stack below it — asserted on bounding
boxes at both sweep widths anyway, since `.archetype-category-header` and `/archetypes`'s row note
each cost this repository one bug of that kind. **No migration.** Still out: a tier control, any
win rate, `/archetypes` (which names the blend already and has no controls), and a venue axis
anywhere but this page.

**Out of scope, deliberately:** cross-archetype comparison and any page spanning archetypes (it
would need a complete field, which no import produces), per-division card statistics (junior and
senior hold 3 and 2 of the 94 measured standings), matchup data, and exporting the report.
