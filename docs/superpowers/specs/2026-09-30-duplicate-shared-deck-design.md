# Duplicate a shared deck into one's own decks — design

## Request

A signed-in member reading a deck somebody else shared (another member's, or a tournament field
list) can copy it into their own decks, private, to play and edit it. The copy takes the **name**,
the **format**, the **archetype** and the **list, printings included**.

## Decisions (owner, 2026-09-30)

1. **Archetype of a field list = its standing's**, falling back to `decks.archetype_id` only when
   there is no standing. That column was written by `Decks::ArchetypeDetector` at import and
   contradicts the standing on **512 of 1798** field lists in development (405 of 1223 on the
   production copy cited in `CLAUDE.md`); #195 realigns it. Until then the public page's badge
   (which reads the column) can name a different archetype than the copy receives, and that is
   accepted: the copy gets the true one.
2. **The name is copied verbatim** for a deck the reader does not own. `"Copy of "` stays the rule
   for duplicating one's own deck, where the two would otherwise sit side by side under one name.
3. **Duplicating one's own deck now copies the archetype too.** It never did, and one code path
   serves both cases.

## What the copy is

| Attribute | Own deck | Somebody else's shared deck |
|---|---|---|
| owner | the owner | the reader |
| name | `"Copy of " + name` | `name` |
| description | copied | **not copied**: the request lists what to take, and a description is the author's notes |
| format, `other_format_name`, `standard_pool_id` | copied | copied (the pool is part of the format: a TEF-CRI list stays TEF-CRI) |
| archetype | copied | the standing's, else the column |
| `physical`, `tcg_live` | copied | `false`: they describe how *the author* plays it |
| `shared` | `false` (column default) | `false` |
| deck cards | `(card_id, quantity)`, `owned_copies` 0 | same |
| versions, results, entries | none | none |

`owned_copies` stays 0 in both cases, and on a copy that is not physical it would be 0 anyway: the
reader allocates their own collection by making the deck physical afterwards.

A field list at a Standard event carries the event's pool (`Tournaments::StandingListImportJob`),
and 0 Standard decks in development have a NULL pool, so `create!` does not trip on the pool
validation. The rare pre-existing case stays as it was.

## Authorisation

`DeckPolicy#duplicate?` becomes `user.present? && show?`: whoever may read the deck, and is signed
in, may copy it. It is no longer an owner-only write, since it writes nothing to the source.
`DecksController#duplicate` therefore swaps `current_user.decks.find_by!` for
`Deck.find_by!(key:)` followed by `authorize` on the next line, the app's fourth unscoped deck
lookup after `#show`, `#export` and `#odds`. A private deck of somebody else is still a 404,
because `PubliclyReachable` rescues `Pundit::NotAuthorizedError` into `not_found`. `duplicate` is
**not** made publicly reachable: a visitor is bounced to sign-in by `authenticate_user!` before the
lookup runs.

No rate limit: every caller is signed in, and the nine other `rate_limit`s exempt signed-in members.

## Interface

`Decks::PublicShowView` gains a **"Copy to my decks"** button in its actions bar, rendered only when
the ERB passes `can_duplicate: policy(@deck).duplicate?`. That is the `can_record` pattern from
`tournaments/show.html.erb`: the public view stays unaware of sessions. A visitor sees no button,
since the navbar already offers sign-in. The redirect lands on the new deck, with the notice
"Deck copied to your decks.".

## Out of scope

- Realigning `decks.archetype_id` on field lists (#195).
- Copying the author's description or notes.
- A copy from the shared-decks grid or the dashboard showcase. Only the deck page offers it.
