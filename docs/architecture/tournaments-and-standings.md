# Tournaments, entries and standings

The shared public event, one member's private participation in it, and the event's own wiki-governed sheet of results.

This file carries detail that used to sit inline in `CLAUDE.md`. Everything here is a decision with a measurement behind it — read it before changing the code it covers, because most entries record something that was already tried and rejected.

Design records:

- `docs/superpowers/specs/2026-09-03-public-tournaments-design.md`
- `docs/superpowers/specs/2026-09-04-tournament-standings-design.md`

---

**An event's sheet is paginated** (`TournamentStanding::SHEET_PER_PAGE`, 50). A hand-typed sheet is
a handful of rows; a Worlds field is a thousand, on a page that is public and deliberately carries
no rate limit ("one page load per click"), and that preloads three associations for every row it
renders. Two things had to move for a page boundary to be drawable at all. `as_a_sheet` now orders
the divisions **in SQL** by `TournamentStanding.division_order`, an Arel CASE over `DIVISIONS` — `ORDER BY division` is
alphabetical (junior, masters, senior) while players read junior, senior, masters, and
`Standings::Table` had always regrouped them for display, so with the two orders disagreeing a
boundary drawn in SQL falls where the reader never sees it: page two opening in the middle of a
division page one appeared to finish. And **everything that points at a row now points at the page
it is on**, anchored to it: the redirect after every write that leaves the row standing (a refused
`#claim` included — the row is still there and the alert is about it), the duplicate-name hint on
the form, and Cancel. "Back to the event" is the top of page one, which need not hold what the
member just typed. `Tournaments::Standings::Row.sheet_position` is the one place that answers it,
beside `dom_id` because the anchor *is* the row's identity, and in one place because three copies
of "which page is it on" drift; it reads `TournamentStanding.page_of`, one `pluck` of ids over one
event's field rather than a COUNT predicate that would restate the scope's ordering somewhere else.
`#destroy` reads the page *before* the row goes and clamps it *after*, since deleting the only row
of the last page otherwise leaves a `?page=` that no longer exists in the address bar and in any
link shared from it. `#show` clamps an out-of-range `?page=` to the last page rather than rendering
an empty table under "No standings recorded for this event yet." — which is false, and which a
public URL will be asked for; `#index` got the same clamp for the same reason, having told the same
lie about the catalog since it was written. There is **no Turbo Frame** here,
unlike the three listings that have one: those wrap a debounced filter field where a keystroke
would otherwise pay for the whole surrounding page, nothing on this page fires on its own, and a
frame would capture every link inside the rows — the deck link, Edit, Delete, "This is me" — each
of which would then need `data-turbo-frame="_top"`. `Ui::Pagination` is the markup all four
listings now share; `turbo_action: "replace"` is opt-in on it, because inside a frame it is what
puts `?page=` into the address bar at all while on an ordinary page it would only overwrite the
history entry, so Back from page 2 would skip page 1.

`Tournament.with_standard_pool` is a deliberate twin of `Deck`'s, for the same measured reason — `StandardPool#name` reads both of its bounds, and dropping the scope took the catalog page from 11 queries to 23. A view that reaches the event through `entry.tournament` throws that preload away and lazily re-reads all four rows, which is why `Tournaments::Entries::ShowView` takes `tournament:` as its own keyword rather than deriving it.

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
must not erase a public row other members read). `Archetype has_many :tournament_standings,
dependent: :restrict_with_error` — unlike its own `:nullify` cascades on `decks` and
`deck_results` — because `archetype_id` is `NOT NULL` on a standing, `:destroy` would silently
erase another member's public record, and leaving the association off entirely would raise a bare
`ActiveRecord::InvalidForeignKey` from a reachable admin destroy; `Admin::ArchetypesController#destroy`
branches on the return value and names the count in the alert, the same shape `TournamentsController#destroy`
and `DecksController#destroy` already use for their own `restrict_with_error` cascades.
`User has_many :created_standings, class_name: "TournamentStanding", foreign_key: :created_by_id,
dependent: :nullify` — an authorship trail, not a participation, so it nullifies like
`created_tournaments` rather than cascading like the entries do (see
**`Tournament` is the shared public event** in `CLAUDE.md`). A `before_destroy` takes
the field list with the row, but **only a list nobody owns** — nothing points a standing at an
owned deck today, and the guard is what stops a future caller detonating a member's deck through a
standings delete.

**The event carries three field sizes, and `TournamentEntry#participant_count` survives beside
them.** `junior_participant_count`/`senior_participant_count`/`masters_participant_count` are
read through `Tournament#participant_count_for(division)` and cap a standing's `placement` — per
division, because Play! Pokémon ranks a placement against the size of *that player's* age
division. The entry's own column is not a duplicate and is not derivable from them: an entry with
no `tournament_profile` has no division, so there is nothing on the event to read.
`TournamentStanding::DIVISIONS` is `TournamentProfile::DIVISIONS` mapped to Strings rather than a
second list — and `TournamentProfile#division` answers with a **Symbol**, which the enum column
will not take, so the prefill calls `.to_s` and asks about the *event's* date rather than today
(a division is fixed for a whole season). A participation with no `TournamentProfile` has no
division to copy, so `prefill_attributes` drops the key entirely — which is why
`Tournaments::Standings::Form` passes an explicit `selected:` (`DEFAULT_DIVISION`, `"masters"`)
rather than letting the browser pre-pick the first option and silently publish a Masters player as
a Junior. `placement_hint` reads that same default, or the form would offer "leave blank if nobody
remembers" beside a select already reading Masters at an event whose masters field size is known.

**The field-list import reuses `Decks::Fetcher` and deliberately not `Decks::ImportJob`.** That
job broadcasts the finished deck into `#decks-grid` and replaces `#deck-count`, which would file a
tournament field list in the contributor's own deck list — the one thing an ownerless deck must
not be. `Tournaments::StandingListImportJob` broadcasts the standing's own row instead
(`Tournaments::Standings::Row.dom_id`, which is why that row is its own Phlex component rather
than a block inside `Ui::DataTable`), to the **contributor's** `:notifications` stream, rendered
through `ApplicationController.renderer.render(component, layout: false)` rather than a direct
`.call`: `Phlex::Rails::Helpers::Routes` overrides `url_options`/`default_url_options` to delegate
to `view_context`, and Rails' `url_for` consults those **even for `_path` helpers** — so a
component using `link_to`/`button_to` cannot render outside a request. `Decks::ImportJob` gets
away with the direct call for two independent reasons: `Decks::DeckCard` calls
`Rails.application.routes.url_helpers.deck_path` as a **module method**, bypassing the override,
*and* it is rendered with `with_actions: false` so `link_to`/`button_to` never run. The broadcast
row's own `button_to` (claim/unclaim, delete) carries no CSRF token and works only because Turbo
attaches `X-CSRF-Token` from the *live page's* own meta tag before submitting — a plain form
submit or a client that skipped Turbo would 422; this is now exercised by a system test that
clicks a button on a row a live broadcast delivered, not merely asserted in a comment. The
broadcast passes `claimable_entries` rather than leaving `Row`'s `[]` default: it replaces the row
wholesale, so a contributor with an unrecorded participation at this event watched their own "This
is me" button disappear until the next reload. A failed
broadcast must not rewrite a successful import: the job's broadcast has its own `rescue` that only
logs, and the outer `rescue` reports failure only for an error raised before the deck lands — the
import's work is the deck, the broadcast is a notification about it. **The job is enqueued with
ids, not records**, unlike `Decks::ImportJob` and `CardSets::ImportJob`, and the reason is
governance: those two are handed a user and an import, neither of which can vanish mid-flight,
while any member may delete this standing — or the event, which cascades onto it. Handed records,
GlobalID raises `ActiveJob::DeserializationError` **before** `#perform` is entered, where the
method's own `rescue` cannot see it: the `Import` would sit at `"pending"` forever, with
`Admin::ImportsController#retry` refusing this kind and no other way to clear it. As ids the
deletion is an ordinary lookup miss, raised as `StandingDeleted` and reported down the same path as
a bad decklist. The `rescue` also **destroys the deck it just created** when the `update!` attaching
it fails: `Decks::Fetcher` commits its own transaction, so the list lands first, and what is left
otherwise is exactly the orphan the re-import path guards against — ownerless, `shared: true`,
referenced by nothing, unreachable. It re-reads `deck_id` from the database rather than off the
record, because `update!` assigns the association *before* it validates, so a failed attach leaves
the in-memory `standing` pointing at the new deck while nothing was written. The pending state renders as
a `Ui::ImportingList` beside the standings table, not as a spinner inside the row: a per-row
spinner would cost a `tournament_standing_id` on `imports` for a state every contributor already
sees listed beside the table — a decision, not an oversight. `imports` does carry a nullable
`tournament_id`, which is a different column answering a different question: *which page* is
waiting. Without it `TournamentsController#show` listed every pending `standing_list` import the
reader had anywhere, so an import started at one event appeared under another event's
"Importing…" heading — and since the item's DOM id is `importing-<import id>`, the first event's
completion broadcast then removed a row from a page it had nothing to do with. `Tournament has_many
:imports, dependent: :nullify`, like `created_tournaments`: an `Import` is the member's own record
of work they asked for and outlives its subject, the way a deck import already outlives the deck. `Ui::ImportingList` gained a `list_id:` keyword (defaulting
to `"importing-decks"`, so its two pre-existing callers are unchanged), because two lists on one
page must not share a DOM id. `Decks::Fetcher` gained
`shared:`/`format:`/`standard_pool:`/`other_format_name:` keywords and accepts a `nil` user: a
field list is anchored to **the event's** pool, not to `StandardPool.current`, because the event
has a date and it is the only thing that knows which pool was legal — and
`clear_inapplicable_classification` drops the pool when the format is not Standard and the custom
name when it is not Other, so neither a GLC event's list nor a Standard one needs a special case. The deck's name is
`"<player> — <event> (<date>)"` because `/decks/shared` prints no author and the name is the only
thing that can situate the list. `Import::KINDS` gained `standing_list`, and
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
standings from RK9, and Championship Points on a standing. (Importing them from Limitless is no
longer out — see `docs/architecture/limitless-imports.md`.)
