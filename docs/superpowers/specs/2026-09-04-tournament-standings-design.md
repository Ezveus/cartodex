# A tournament records its field — public standings for players without an account — Design

**Status**: approved design, not yet implemented
**Issue**: follows #148 (public tournament catalog)

## Goal

Let any member catalogue what the field played at an event: one row per player,
naming the archetype they brought and, when it is known, the decklist itself.
The players being recorded have no account here, so the row cannot hang off a
`User` the way `TournamentEntry` does.

## Scope

In: a public, wiki-editable standings table on an event's page; an archetype per
row plus an optional imported decklist owned by nobody; per-division field sizes
on the event; an explicit link between a member's own private participation and
the public row that names them.

Out: aggregation of any kind — no per-event metagame breakdown, no cross-event
metagame page (both are the obvious next issue, and neither is designed here);
claiming a row as a player who has no account; importing standings from RK9 or
Limitless; Championship Points on a standing.

## Confirmed decisions (from the brainstorming interview)

1. The purpose is a **public metagame record**, not private tracking of the
   member's family or friends.
2. A row carries **archetype (required) plus an optional full decklist**. The
   decklist belongs to the event, not to whoever typed it in.
3. Governance is **wiki**: any signed-in member may add, correct or delete any
   row. A `created_by` is recorded anyway — it costs one nullable column and it
   is the only trace of who typed what.
4. A row carries **player name, division, placement and a W-L-T record**.
5. Uniqueness is **`(tournament, normalized player name, division)`** — one
   player, one row per division. Placement stays optional, so a player whose
   final standing nobody remembers can still be recorded.
6. The optional decklist is a **`Deck` with no owner**: `decks.user_id` becomes
   nullable. Such a deck is **not** listed in `/decks` (nobody's index) but
   **is** listed in `/decks/shared`, and no UI can edit it.
7. Importing that decklist **reuses `Decks::Fetcher`** through a background job,
   as a member's own deck import does.
8. The event page shows **the table alone**. Aggregation is a later issue.
9. The per-division field size lives **on the `Tournament`**, not on each row.
10. A member's own participation and the public row that names them are joined
    by an **optional link on the standing**, not merged into one record and not
    left as two unrelated rows.

## Facts established before designing (measured, not assumed)

- `decks.user_id` is read in eleven places, and they split four ways.
  **Five are unreachable** for an ownerless deck, because each sits behind an
  owner-only policy that a nil `user_id` can never satisfy
  (`Decks::Duplicator`, `Decks::CardAdder`, `Decks::OwnedCopiesSetter`,
  `Decks::PrintingSwapper`, and `DeckPolicy#owner?`, which is what makes the
  other four unreachable). **One keeps working and gains a property worth
  naming**: `TournamentEntry#deck_belongs_to_user` compares
  `deck.user_id != user_id`, so a field list can never be used as a member's
  own participation deck — the guard is already there, for free. **Two are live
  bugs the moment the column goes nullable, and three raise**:
  - `DecksController#show` branches on `@deck.user_id == current_user&.id`.
    With both sides nil — an ownerless deck viewed by a visitor — this is
    **true**, and the visitor is served `owner_show`.
  - `Search::Global#shared_deck_scope` does `where.not(user: @user)`, which
    compiles to `user_id != ?` and therefore **excludes NULL rows**: every
    field decklist would vanish from the spotlight of any signed-in member.
  - `Admin::Decks::IndexView`, `Admin::Decks::ShowView` and
    `Admin::Dashboard::IndexView` each print `deck.user.email` →
    `NoMethodError`.
- `Decks::ImportJob` broadcasts a `Decks::DeckCard` into `#decks-grid` and
  replaces `#deck-count`. Reusing it for a field list would make that list
  appear in the contributor's own deck grid, which is precisely what decision 6
  rules out. `Decks::Fetcher` itself is reusable; the job is not.
- `Decks::Fetcher` anchors every imported deck to `StandardPool.current`.
  A field list must be anchored to **the event's** pool instead: the event has a
  date, and it is the only thing here that knows which pool was legal.
- `Admin::ImportsController#retry` re-enqueues a deck import with
  `@import.label` as the decklist — the deck's *name*. That retry has therefore
  never worked. Pre-existing, out of scope, recorded here so the new kind is not
  wired into the same switch and left silently doing nothing.
- `Decks::ArchetypeField` is soldered to a deck: it reads `@deck.key` for the
  "Suggest" button and `@deck.archetype&.name` for the input's value. The
  standings form needs the same picker without a deck.
- `Decks::DeckCard.new(public_listing: true)` prints no author, so an ownerless
  deck already renders correctly in `/decks/shared` with no change.

## Data model

### `tournament_standings` — one player's line in the field

| column | notes |
| --- | --- |
| `tournament_id` | `NOT NULL`, FK |
| `player_name` | `NOT NULL`, free text |
| `player_name_normalized` | `NOT NULL`, via `NameNormalizable` |
| `division` | `NOT NULL`, one of `junior`/`senior`/`masters` |
| `placement` | nullable integer, `> 0` |
| `wins`, `losses`, `ties` | nullable integers, `>= 0` |
| `archetype_id` | `NOT NULL`, FK — the point of the record |
| `deck_id` | nullable FK — the ownerless decklist |
| `tournament_entry_id` | nullable FK — the "this is me" link |
| `created_by_id` | nullable FK to `users`, `nullify` on user destroy |

Indexes:

- `(tournament_id, player_name_normalized, division)` UNIQUE — one player, one
  row per division. The model validation exists for the readable error, the
  index is the guarantee: the same division of labour as `(set_name,
  set_number)` on `Card` and `(name_normalized, date)` on `Tournament`.
- `(tournament_id, division, placement)` — the table's own sort.
- `tournament_entry_id` UNIQUE `WHERE tournament_entry_id IS NOT NULL` — a
  participation is published at most once. This is the index that actually stops
  a member publishing themselves twice under two spellings of their own name,
  which the name key cannot see.

`division` reuses `TournamentProfile::DIVISIONS` as its value list rather than
declaring a second one, and is a validated enum.

`NameNormalizable` normalizes `name`, not `player_name`, so the concern cannot
be included as-is. The standing gets its own `before_validation` +
`before_save :normalize_player_name` pair, spelled for the same reason
`Tournament` runs `normalize_name` twice:

```ruby
# before_validation as well as before_save, for the reason Tournament does it: the
# uniqueness validation has to compare the normalized value before the record is saved,
# not once it already is. It squishes as well as downcasing — a player name arrives
# copy-pasted off a standings sheet, with a trailing space or a double space where a
# column wrapped, far more often than it arrives typed.
```

Validations:

- `player_name`, `division`, `archetype` present; `placement`, `wins`, `losses`
  and `ties` numeric and optional.
- uniqueness of `(tournament, player_name_normalized, division)`, error added to
  `:player_name` — a column the user has heard of — with the controller re-finding
  the offending row so the form can link to it and offer `claim`.
- `placement` must not exceed the event's participant count **for this row's
  division**, when both are known.
- `tournament_entry` must belong to the same tournament. Whether it belongs to
  the reader is *not* a model concern — the model does not know who is asking;
  the controller looks the entry up through `current_user.tournament_entries`,
  so a stranger's entry is a `RecordNotFound`, never a policy question.

### `tournaments` — three field sizes

`junior_participant_count`, `senior_participant_count`,
`masters_participant_count`: nullable integers, `> 0`, edited on the event form,
read through `Tournament#participant_count_for(division)`.

`TournamentEntry#participant_count` stays where it is and is **not** derived from
them. The reason goes in the model:

```ruby
# The event now carries a field size per division, and this column looks like a duplicate of
# it. It is not derivable: an entry with no tournament_profile has no division, so there is
# nothing on the event to read. Play! Pokémon ranks a placement against the size of *that
# player's* age division, which is why the number is here at all — see CLAUDE.md.
```

### Associations and cascades

```ruby
# On Tournament
has_many :standings, class_name: "TournamentStanding", dependent: :destroy
```

`:destroy`, unlike `:entries`' `restrict_with_error`, and the difference is the
whole point of the split: an entry is somebody's private record of having been
there, a standing is a line of the event's own public sheet. Deleting the event
takes the sheet with it and refuses while any participation survives.

```ruby
# On TournamentEntry
has_one :standing, class_name: "TournamentStanding", dependent: :nullify
```

`:nullify`: deleting my private participation must not erase a public row other
members read — only unlink it.

`TournamentStanding belongs_to :deck, optional: true` plus a `before_destroy`
that destroys the deck **only when it has no owner**. Nothing else points at a
field list today, but the guard is what keeps a future caller from detonating a
member's own deck through a standings delete.

The reverse direction needs saying too: `Deck has_one :tournament_standing,
dependent: :nullify`. `Admin::DecksController#destroy` is unscoped by design, so
an admin can delete an ownerless deck from the panel; without this the standing
keeps a dangling `deck_id` and its row's list link 404s.

An ownerless deck's own constraint lives on `Deck`:

```ruby
# An ownerless deck is a tournament field list: it belongs to an event, not to a member. It
# must be shared, because /decks/shared is the only listing that can show it, and it must not
# be physical, because `physical` is what makes a deck consume a collection and there is no
# collection to consume. This is why the allocation services, which all read deck.user, are
# unreachable for it by construction rather than by convention.
validate :ownerless_deck_is_shared_and_virtual
```

## Migration

One migration, three parts, all reversible:

1. `create_table :tournament_standings` with the columns and indexes above.
2. `add_column :tournaments, :<division>_participant_count, :integer` ×3.
3. `change_column_null :decks, :user_id, true`.

No data backfill: every existing deck keeps its owner, and there are no
standings yet. The three audit fixes ship in the same commit as part 3, because
part 3 is what turns them from dead code into bugs.

## Authorization

`TournamentStandingPolicy`:

| query | rule |
| --- | --- |
| `create?`, `update?`, `destroy?` | `user.present?` — wiki, decision 3 |
| `claim?` | `user.present?`; which entry is claimable is enforced by the scoped lookup, not here |
| `unclaim?` | `user.present? && record.tournament_entry&.user_id == user.id` |

`unclaim?` is the one owner-scoped rule: anybody may correct the public data on
a row, but only the member whose participation is linked may sever the link.

**`standing_params` must not permit `tournament_entry_id`.** Without that, the
wiki edit form would let any member attach their own participation to a row
naming somebody else, or detach yours. The link is written only by `claim` and
`unclaim`.

This policy grants an admin nothing beyond a member, unlike `TournamentPolicy`:
there is no moderation question here that a member cannot already answer, since
every member can already edit every row.

## Routing

```ruby
resources :tournaments do
  resources :standings, only: %i[new create edit update destroy],
            controller: "tournaments/standings" do
    post :claim, on: :member
    delete :unclaim, on: :member
  end
end
```

No `show` and no `index`: the table lives inside `tournaments#show`, and a row
is six fields — the same call `Admin::StandardPoolsController` makes.

These routes leave the app-wide `authenticate :user` block **by nesting alone**,
exactly as `entries` does. `Tournaments::StandingsController` therefore does
**not** include `PubliclyReachable`, keeps `authenticate_user!` as its only gate,
and calls `authorize` in every action — the same deliberate exception
`Tournaments::EntriesController` and `DeckResultsController` are, with the same
consequence: nothing enforces that the `authorize` call is present, so
`test/controllers/public_access_test.rb` gains a case per action.

## Controllers

### `Tournaments::StandingsController`

`set_tournament` looks the event up unscoped — it is public. `set_standing`
scopes by `@tournament`, so a row belonging to another event 404s rather than
rendering under the wrong header, the reason `Tournaments::EntriesController`
scopes its entry by both.

- `new` accepts an optional `tournament_entry_id` and prefills from it: player
  name from the profile, division from `profile.division(on: tournament.date)`,
  placement from the entry, archetype from `entry.deck.archetype`. The entry is
  fetched through `current_user.tournament_entries`.
- `create` writes `created_by: current_user`, and sets `tournament_entry` from
  the same scoped lookup when the prefill carried one. On the uniqueness error
  it re-finds the clashing row and renders the form with a link to it plus a
  `claim` button, mirroring what `TournamentsController#create` does when an
  event is already catalogued.
- `update`, `destroy`: wiki.
- `claim` takes a `tournament_entry_id`, looked up through
  `current_user.tournament_entries` and checked against `@tournament`; it writes
  the link and nothing else. `unclaim` clears it.
- The optional decklist is a `decklist` text field on the form. When present,
  `create`/`update` opens an `Import` for `current_user` and enqueues the job
  below. Absent, nothing is enqueued. The standing is saved either way, so its
  row exists before its list does: the table renders a pending state on that row
  (`Ui::ImportingList`'s vocabulary) until the job replaces it.

### `TournamentsController#show`

Loads the standings for the table with the preload the table actually reads:

```ruby
@standings = @tournament.standings
  .includes(:deck, :tournament_entry, archetype: %i[primary_card secondary_card parent])
```

`Ui::ArchetypeBadge` reads the archetype's cards, and the "this is me" badge
reads the linked entry's `user_id`, so both belong in the `includes`. A flat-cost
test guards it, like the four that already guard `with_standard_pool`.

### `Admin::ImportsController#retry`

Gains an explicit refusal for the new kind — the decklist text is not stored, so
there is nothing to retry — rather than falling through the `case` and silently
enqueueing nothing after destroying the old row.

## The import

`Decks::Fetcher` gains three keywords and accepts a nil user:

```ruby
def initialize(decklist, user, name, shared: false, format: nil, standard_pool: nil)
```

They are passed straight to `Deck.create!`; `clear_inapplicable_classification`
clears the pool when the format is not Standard, so a GLC event's list needs no
special case here.

`Tournaments::StandingListImportJob(standing, decklist, contributor, import)`:

1. `Decks::Fetcher.call(decklist, nil, deck_name, shared: true, format: tournament.format, standard_pool: tournament.standard_pool)`.
2. `standing.update!(deck: deck)`.
3. Broadcasts to the **contributor's** `:notifications` stream: remove the
   importing indicator, append a flash, replace the standing's table row.

`deck_name` is `"<player name> — <event name> (<date>)"`: `/decks/shared` prints
no author, so the name is the only thing that can situate the list.

`Import::KINDS` gains `standing_list`.

`Decks::Fetcher` also tags the deck with a detected archetype. That tag stays on
the deck and does **not** overwrite the standing's own: the standing's archetype
was declared by a human making a record, and detection exists to guess when
nobody has. A disagreement between the two is information, not a conflict.

## Views

- `Tournaments::Standings::Table`, rendered by `Tournaments::ShowView`, grouped
  by division and sorted by placement with the unplaced last. Columns:
  placement, player, archetype (`Ui::ArchetypeBadge`), record, list (a link to
  the deck when there is one). Edit and delete controls only for a signed-in
  reader; the "this is your participation" badge only for the member whose entry
  is linked.
- `Tournaments::Standings::Form`, shared by `new` and `edit`.
- `Tournaments::ShowView` gains a "Publish my participation" action per entry
  the reader owns that has no standing yet, pointing at
  `new_tournament_standing_path(t, tournament_entry_id: entry.id)`. It is
  guarded by the same `can_record` the existing entry actions use, for the same
  reason: a visitor's list is empty by construction and a primary-styled link to
  the sign-in page is the navbar's job.
- **Extraction**: `Decks::ArchetypeField` becomes
  `Ui::ArchetypePicker.new(form:, selected:, deck_key: nil)`, rendering the
  "Suggest" button only when a `deck_key` is given. The deck form becomes a
  caller. This is the alternative to a degraded copy of the picker in the
  standings form. `archetype_picker_controller.js` must be checked to tolerate a
  missing `deckKey` value — the Suggest handler is unreachable without the
  button, but the controller must still connect.

## Testing plan

Every test below is written to fail first, and the implementation is sabotaged
once per test to prove it can go red.

- **Models**: standing validations; uniqueness on the normalized name, including
  a name differing only by case or double space; `placement` against the
  division's field size; `tournament_entry` from another event refused;
  `Tournament#participant_count_for`; an ownerless deck must be shared and
  non-physical; `TournamentEntry has_one :standing, dependent: :nullify`.
- **Audit regressions**: a visitor on an ownerless shared deck is served
  `public_show`, not `owner_show`; an ownerless shared deck appears in a
  signed-in member's spotlight results; the three admin views render with a
  nil user.
- **Controller**: a member may edit another member's row; a signed-out request
  is redirected; `claim` with another member's entry 404s; `tournament_entry_id`
  is not mass-assignable through `update`; the uniqueness error renders a link
  to the clashing row; `tournaments#show` costs a flat number of queries as the
  standings grow.
- **Policy**: `TournamentStandingPolicyTest`, including `unclaim?` refusing a
  member who does not own the linked entry, and an admin gaining nothing.
- **Job**: the imported deck is ownerless, shared, non-physical, anchored to the
  event's pool (not `StandardPool.current`), and attached to the standing.
- **`public_access_test.rb`**: a visitor reads the table; every write action of
  the standings controller refuses them, asserted per action.
- **System**, on both viewports: add a row, import a list, publish my own
  participation, claim a row somebody else typed. Navigation through
  `click_nav_link`.
- **Fixtures**: `tournament_standings.yml`, plus an ownerless shared deck.
  Fixtures skip callbacks, so `player_name_normalized` is spelled by hand and a
  test asserts it stays in step with `player_name`, as each `NameNormalizable`
  model already has.

## Documentation

`CLAUDE.md` gains: the standing-versus-entry split and why it is two tables; the
ownerless-deck rule and the two bugs the nullable column exposed; the
`tournament_entry_id` mass-assignment trap; the three division counters and why
`TournamentEntry#participant_count` survives beside them.

## Notes

- No aggregation ships here. The archetype FK and the division column are chosen
  so that a per-event breakdown is a `group` over one table when it does.
- Values on a standing are **copied** from a participation, never derived from
  it: editing a private participation must not silently republish. The row is
  wiki-editable, so correcting it is an ordinary edit. No resync mechanism.
- A player with no account cannot claim their row, since claiming is the act of
  a member linking their own participation. That is the whole reason the feature
  exists and is not a gap.
