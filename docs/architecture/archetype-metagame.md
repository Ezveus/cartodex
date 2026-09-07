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

**Member-only, and opening the pages to visitors is seven edits, not three** — the list lives in
the comment atop `ArchetypesController` and was produced by applying the obvious three and reading
what broke *and what did not*. Three make the route reachable and are each covered by a test that
goes red without them: move the resource out of `authenticate :user`, `include PubliclyReachable`
with `publicly_reachable :index, :show`, flip `ArchetypePolicy` from `user.present?` to `true`.
**Four more decide what a visitor then sees, and no test would report any of them missing**: the
per-IP `rate_limit … unless: -> { user_signed_in? }` sized like `tournaments#index`'s 60/min
(deliberately absent now — no anonymous request can reach the route, so nothing could exercise it,
and a limiter nobody can exercise is a limiter nobody knows works); `nav_link "Archetypes"` in
`Ui::PublicNavbar`, without which a visitor on those pages lights **zero** navbar entries, a hole
`NavbarActiveSectionTest` cannot see because it names no visitor archetype page; dropping
`Search::Global#archetype_scope`'s `Archetype.none` branch, whose trap is the opposite kind — its
test keeps *passing* while defending a rule that has become false, so it has to be inverted in the
same commit; and the two archetype links a public page withholds today, `Tournaments::Standings::Row`'s
`if @viewer.present?` guard and `Decks::PublicBadges` (which passes no `href:` at all) — the
standings sheet and a shared deck are both public, and a link to a sign-in wall is worse than no
link, right up until the wall is gone. `Ui::ArchetypeBadge` gained the optional `href:` that all
three sites pass or withhold, and its anchor carries `data-turbo-frame="_top"` — the breakout
belongs to the component and not to a call site, because every surface that passes an href renders
it inside a Turbo Frame, and frame-scoped the click swaps that frame for Turbo's missing-frame
error instead of navigating; only a system test tells those two outcomes apart, since the markup is
identical and a request test sees a 200 for a page nobody reaches. `Decks::ClassificationBadges`
takes `linked:` rather than linking unconditionally, because its two callers have opposite
constraints: `Decks::HeaderFrame` renders the row in a plain div, while `Decks::DeckCard` renders
it inside `a.deck-item-link` and an `<a>` within an `<a>` makes an HTML5 parser close the outer one
at the second start tag — the deck's own link ended after its `<h2>`, and the description and card
count fell outside any link. `assert_select` parses HTML4 and nests anchors happily, so the guard
is a controller test reading `Nokogiri::HTML5`. `Search::Global`'s fifth group prefixes its option ids
`spotlight-option-archetype-` for the reason `shared_decks` had to. The two archetype rows in
`public_access_test.rb` move from `owner_only_gets` to `public_gets` that day, and three tests
asserting today's refusal turn round with them.

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

**Out of scope, deliberately:** cross-archetype comparison and any page spanning archetypes (it
would need a complete field, which no import produces), per-division card statistics (junior and
senior hold 3 and 2 of the 94 measured standings), matchup data, and exporting the report.
