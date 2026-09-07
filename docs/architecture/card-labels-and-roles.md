# Card labels and roles

`CardLabel` and `CardLabelAssignment` — a vocabulary plus a fingerprint-keyed join, holding what a card *is* (ACE SPEC) and what it *does* (the role family).

This file carries detail that used to sit inline in `CLAUDE.md`. Everything here is a decision with a measurement behind it — read it before changing the code it covers, because most entries record something that was already tried and rejected.

Design records:

- `docs/superpowers/specs/2026-09-05-card-labels-and-roles-design.md`

---

**The card-label store** (`CardLabel`, `CardLabelAssignment`) is a vocabulary plus a fingerprint-keyed
join, and exists because the ACE SPEC annotation on `/archetypes/:id`
(`docs/architecture/archetype-metagame.md`) needs somewhere to live that is not another
guess dressed up as a column. The two families it holds are governed oppositely on purpose: a
`type` label (ACE SPEC today) is referenced by nothing but its own `source_query`, so an admin
adding one is a row plus a run; stage 2's `role` family is referenced by code — its suggestion
rules are keyed on the slug — so an admin-invented role would be a label no rule can ever propose,
and `Admin::CardLabelsController` refuses to create or delete one for exactly that reason. An
assignment is keyed on **fingerprint**, not on a printing, because a label describes the card and
every printing of Prime Catcher is an ACE SPEC; `card_id` still rides beside it, optional and
nullified rather than cascaded, as the one printing the decision was actually read from — deleting
that printing from the admin panel must not delete what was decided about the card. `source`
(`imported`/`suggested`/`curated`) says who may overwrite whom: the importer writes `imported` rows
and touches nothing else, stage 2's suggester will rewrite only its own `suggested` rows, and a
`curated` row — including one with `rejected` set, a human's refusal rather than an absence of
opinion — outranks both and is kept rather than deleted so the next run cannot quietly undo it.
`CardLabels::Importer` follows the same restraint at the edges: it counts a printing the catalogue
does not hold rather than fetching it (acquiring cards is `CardSets::Importer`'s job, and a known
printing is never re-scraped anyway), and it never deletes an assignment the source stops listing,
because a page truncated by a transport failure looks identical to a card the source genuinely
dropped and only one of those two should depopulate a label. `CardLabels::LimitlessSearch` is what
makes that restraint affordable: `limitlesstcg.com/cards?q=<token>&show=all` answers with the whole
result set in one request rather than a page per printing — measured at `is:ace` 46 of 46, `is:tera`
151 of 151, and the largest plausible label, `is:ex`, 986 of 986 in 234 KB — so there is no
pagination to write and the page's own announced count is free to serve as an integrity check
instead of a stopping condition.

`Import::KINDS` gains `card_labels`, whose `tournament_id` stays nil like `limitless_standings`'s
but for a different reason — a card-label run has no tournament in the picture at all, since it is
Limitless's card search for one label's `is:` token rather than a standings sheet. Unlike either of
the two kinds before it, it leaves no receipt to undo: a re-run writes exactly
the rows the source still lists and deletes nothing on its own, so there is nothing for
`Admin::ImportsController#undo` to act on and it falls through to that action's generic refusal.
`Admin::ImportsController::RETRYABLE_KINDS` does not carry it either — an Import stores only the
label and the query, not a payload, and the query still lives on the `CardLabel` row, so retrying
means running the import again from there rather than from the `Import`; `UNRETRYABLE_REASONS`
says exactly that in the admin's own words instead of falling through to the generic fallback
sentence.

**`CardLabels::RoleSuggester` proposes and never decides**, which is the asymmetry the whole store
was built for. One versioned regex per slug reads `cards.effect` **plus** every attack's and
ability's name and effect — the second half is what makes a role mean anything on a Pokémon at all,
since `effect` is empty on every Pokémon in the catalogue. Measured on the production dump: 714
assignments over 689 of 3023 fingerprints in 1.2 s, which on the 94 fingerprints the recorded lists
actually play is 33 of 51 Trainer/Energy and 13 of 43 Pokémon. The same run hands *Telepathic
Psychic Energy* a `search` role it does not deserve and says nothing about Pokégear 3.0, Explorer's
Guidance, Bug Catching Set or Professor Turo's Scenario — the cards a player names first. Coverage
is not the problem; an error it makes is invisible on the rendered page, which is why a human
decides. It writes and withdraws **only its own `suggested` rows**, never examines a pair carrying
a `curated` decision (a yes *or* a refusal), and **refuses before writing anything** when the
vocabulary has not been seeded, rather than writing four families out of seven and leaving a report
that looks complete. A role label whose rule has gone — reachable only by a code change, since the
seed never deletes and the panel refuses to — keeps its curated decisions and loses its
suggestions, which nothing would ever withdraw again. Two details with measurements behind them:
the rules are **one line each and never `/x`**, because extended mode ignores literal whitespace and
the multi-line form of three of them silently matched nothing (0 rows against 34, 45 and 58) with
the suite green throughout, so a per-rule test now walks real card text through every slug; and the
text of a fingerprint is the **union of its printings'**, a hedge that costs nothing today (193
Trainer/Energy fingerprints hold several printings and 0 of them disagree on `effect`) against a
reprint whose wording is scraped differently withdrawing a role on the next run. The catalogue is
read **before** `serialized_transaction` opens, the discipline `Tournaments::StandingsImporter`
already follows: `BEGIN IMMEDIATE` holds SQLite's single write lock, and the reading half is 0.4 s
of that 1.2 s.

**`/admin/card_roles` is where a human decides, one row per fingerprint.** Ticking writes `curated`
present, unticking writes `curated` **rejected** — never a deletion, because a deletion reads as
"nobody has looked at this yet", which is the one thing that stops being true the moment somebody
has. A save is a statement about the **whole card**: every role left unticked becomes a recorded
refusal, which is what makes the suggester leave that card alone afterwards. The "played in a
recorded list" filter is **on by default** and the page says so in words — the catalogue holds 3023
fingerprints and the recorded lists play 94 of them, so curating everything is a month of work no
reader of the report would ever see. Three things are not what they look like: the `<form>` **is**
the `.data-table-row` rather than a form inside one (that class is a flex container of
`.data-table-cell` children, so a form wrapped around the cells becomes the row's single flex child
and takes the mobile card layout with it); the row is its own Phlex component because a write
re-renders exactly it through a Turbo Stream, for the reason `Tournaments::Standings::Row` is one —
a tick, a promotion of a suggestion and a refusal are indistinguishable in the DOM until the server
answers; and a fingerprint no card carries is a **404**, never a create, since such an assignment
could never be joined by the report. A card with no fingerprint is listed anyway with its boxes
disabled, its note inside a wrapper `div` so the two stack rather than becoming flex siblings — the
`/archetypes` lesson, measured again here. Zero such cards exist today, and the row is what stops
that becoming an assumption. "Suggest roles" runs inline rather than through a job: unlike the label
import beside it, it makes no HTTP request. **Save and Clear are two different acts.** Save is what
says "I agree with what is ticked" — without it the row submitted on `change` alone, so confirming
a suggestion meant ticking a role that is wrong, publishing it, and unticking it again. Clear
deletes every `curated` row for that fingerprint and is **the only deletion the app offers on an
assignment**: a save decides all seven roles at once, so one misclick otherwise removes a card from
the suggester's reach for good. Deleting *on request* is not the act unticking would be — that
would erase a refusal, which is the one thing the store exists to keep — and the button lives in
the row while the form it submits is a hidden sibling, because forms cannot nest. A `curated`
refusal also renders differently from a box nobody has looked at (`--decided` beside
`--suggested`), or the screen cannot show its own progress over 3023 rows. The rows sit in a Turbo
Frame the filter bar targets, like the app's three other filtered listings: without one the 300 ms
debounce navigates the whole page and the caret is gone after every keystroke, on the control whose
whole job is turning 3023 fingerprints into 94.

**A role label's slug cannot be renamed from the admin panel either**, which is the third guard
beside refusing `create` and `destroy` on that family: a rename is both at once. Measured — an
admin renaming `search` to `deck-search` kept the human's decisions on the orphaned row, had the
next `db:seed` recreate `search` empty, had the suggester re-propose what the human had already
decided, and left `/archetypes/:id` rendering two sections both titled "Search".

**The report shows a rule's guess beside a human's decision, and says how many of each.**
`CardStats` reads `CardLabelAssignment.active`, which is `rejected: false` and nothing about
provenance, so a `suggested` row and a `curated` one open the same section — which is the spec's
decision, and was a lie on the page until the count went with it: on the production data the day
this shipped, 714 of 714 assignments were proposals and the method note underneath still read
"a person decides". `Result#proposed_roles`/`#decided_roles` count the pairs the sections were
built from (off assignments already loaded, so still no extra query, and scoped to the entries the
reader is actually looking at), role mode prints one sentence when any of them is unconfirmed, and
the method note now says a rule proposes and a person confirms. **A role never renders as a badge**
— `NameGroupRow` badges the `type` family alone — and that is what keeps the *default* view from
asserting a guess: type mode says what a card is, which the scraper knows, and says nothing about
what it does. Whether the report should show unconfirmed proposals at all is a product question
this leaves open; what it may not do is show them without saying so.

**The report gains a mode, not a second report.** `Archetypes::CardStats.call(standings:,
grouping:)` regroups the *same* entries: `Entry`, `NameGroup`, `fixed_core` and every percentage are
computed identically, so the two views cannot tell two stories about one sample, and role mode adds
**no query** — `labels_by_fingerprint` already loads every family's assignments in one `eager_load`,
so `/archetypes/:id` stays at 17, now pinned by a literal rather than by a small-vs-large comparison
(a fixture with one role section made an added query per section invisible: 17 → 18 there, 17 → 25
in production, green either way). Three things role mode says out loud: the sections **overlap** and
add up to more than 60, because a card is filed under every role it carries; a card with no role
falls into a rendered, counted **"No role recorded"** section, last whatever its neighbours are
numbered, which shows the curation debt instead of hiding it; and a `type` badge (ACE SPEC) renders
in **both** modes and opens no section, so the type-mode categories stay a partition of the list.
The control is two links in the card report's own header — not in `Archetypes::SampleSelector`,
which is dropped entirely when `selectable?` is false, leaving no way back out of role mode — built
from `Rails.application.routes.url_helpers` rather than `link_to`, since the component is rendered
by a bare `.call` in its own tests. They re-emit **the sample the page is showing**, read off the
scope and never off `params[:pool]`: a malformed `?pool[]=junk` is exactly the case where the two
differ, and the component is handed no parameters at all, which makes that structural rather than a
convention. `CardStats::Result` carries the `grouping` that produced it for the same reason — the
links cannot name a mode other than the one the sections below them were built with.

**`test/controllers/admin_gate_test.rb` is the other half of `public_access_test.rb`**, and it
exists because a new admin screen inherits **nothing**: a controller declared
`< ApplicationController` instead of `< Admin::BaseController`, routed under `/admin` and reachable
by any signed-in member, left the whole suite green. It walks the routing table rather than naming
paths, so a screen added tomorrow is covered the day it is routed — and on its first run it found
`GET /admin/card_labels/:id`, routed with no action behind it, which answered without passing the
gate because Rails refuses a missing action before any callback runs. That route is gone, like
`standard_pools`' `show` beside it.

**Out of scope for the roles, deliberately:** variants (#157), per-archetype role overrides (a role
is a property of the card; an override would be a second store, not a migration of this one), and
roles anywhere but `/archetypes/:id`, the admin screen and `/cards`'s filter bar (#164) — not on a
deck page, not in the JSON API, not in an MCP tool.

**The label filter (#164) is measured against that same rule and passes it.** `?label=` and
`?role=` add a flat **+2 queries, unconditionally** — `CardLabel.types` and `CardLabel.roles`,
two index seeks on an eight-row table, 0.8 ms of a 10.5 ms page — and nothing that grows with
anything a visitor controls. They are deliberately **not** folded into `Card.filter_values`: those
two are unindexed scans behind an hour-long cache while these are always-correct indexed reads, and
sharing that entry would tie them to `Card.forget_filter_values`, called by the set importer and
the rescrape job, so an admin's new label would be invisible for up to an hour. They are loaded
with `to_a`, because the view asks `empty?` before iterating and on a relation that is a second
query **per family** — invisible to any relative query-count comparison, since both lists are one
and seven rows whatever the catalogue holds, which is why the cost is pinned by a literal. The
filter itself is the **only indexed filter on the endpoint**: every pre-existing one (`card_type`,
`type_symbol`, `rarity`, `regulation_mark`, the `LIKE`) is a full scan, while
`Card.with_label` is an index seek on both sides and, measured against a synthetic label carrying
the whole catalogue, cheaper than the unfiltered page. Unlike `decks#index`/`#shared`, `#index`
still has no `return if …frame_request?` short-circuit, so a debounced keystroke re-pays the
sidebar, the grouped count, `filter_values` and now these two — pre-existing, and the two added are
the cheapest things on the page.

**`Card.with_label` is the one definition of "the cards carrying this label", and it is a subquery
that `joins(:card_label_assignments)` must never replace.** That association is on `card_id`, the
single printing a decision was read from, so it answers **29** where the subquery answers **33** on
the production catalogue — losing exactly the four reprints the fingerprint key exists to reach. A
hand-written join on `fingerprint` *would* agree (33), and is still not chosen, for two reasons
that also decide the shape of the whole filter: chained `where`s AND while `merge` — the idiom
`CardSearchable` uses three lines from the only caller — keeps only the last of two conditions on
one column, and Rails cannot alias two joins onto one association apart. Two labels have to narrow
each other, or "Item **and** gust" is unaskable, which is the question the two-control shape exists
for. A nil label (an unresolvable slug) compiles to `card_label_id IS NULL` and matches nothing, so
the filter **fails closed**; both params are read through `to_s`, so a Hash- or Array-shaped one
can never reach `cards_path` and raise `UnfilteredParameters` on a public page. And **a role filter
says that it is showing proposals**: `active` is `rejected: false` and says nothing about
provenance, `Archetypes::CardReport` already answers that for the member-only report, and this
surface is anonymous — on production, 709 of 850 assignments are a rule's guess and **no role is
yet fully curated**, so the sentence renders for all seven. It carries no number, because the counts
available are of assignments while the grid shows printings.
