# Filtering an event's standings sheet — design

**Date:** 2026-10-03
**Surface:** `/tournaments/:id` (public), `TournamentsController#show`

## Problem

An imported event's sheet is long and paginated at `TournamentStanding::SHEET_PER_PAGE` (50).
Measured on the development copy of event 298 (Regional Frankfurt, 2026-09-26): **524 standings**
— 508 masters, 8 senior, 8 junior — over **42 distinct archetypes** in masters alone, so eleven
pages. Finding one player, one deck, or the junior division means paging by hand.

## What it does

Three filters above the sheet, combined with AND:

| Param | Control | Match |
|---|---|---|
| `player` | search field, debounced | substring of `player_name_normalized`, case-folded and squished the way the column is, LIKE metacharacters escaped |
| `archetype` | select of the archetypes **present at this event**, by name | exact `archetypes.slug` — **variants are not folded in** |
| `division` | select of the divisions present at this event, in `DIVISIONS` order | exact; rendered only when the event holds more than one division |

- **Exact archetype, confirmed by the owner.** 118 of the 524 rows are filed under a child
  archetype (Dragapult ex / Dusknoir 33, Dragapult ex / Blaziken ex 29, …). Choosing
  "Dragapult ex" shows the parent's rows only, the rule `Archetypes::DeckList` and
  `MetagameScope` already follow. Each variant is its own option.
- **The slug, not the id, travels in the URL**: a filtered sheet is a shareable public address,
  and the slug is what an archetype's address already is. An unknown slug, division or a
  non-scalar param shape (`?player[]=x`) is ignored rather than refused — the select then shows
  "All", which is what the page is showing.
- **Options cover the whole event, not the current filter.** The form sits outside the frame (see
  below) and is never re-rendered by a filter request, so options narrowed by the other filters
  would be stale the moment a second filter moved.
- **Pagination counts the filtered rows**, and the pager's links carry the filters. The
  out-of-range clamp applies to the filtered page count.
- **An empty filtered result says so** ("No standings match these filters.") — never the
  unfiltered "No standings recorded for this event yet.", which would be false. The filter bar
  does not render at all on an event with no standings.
- **Writes still return to the unfiltered sheet.** `Row.sheet_position` answers the row's page in
  the *whole* sheet; a member editing a row from a filtered view lands back on the row, unfiltered.
  Accepted: the anchor still finds the row, and threading filters through three write paths buys
  little.

## The Turbo Frame this page used to refuse

`docs/architecture/tournaments-and-standings.md` records "There is **no Turbo Frame** here" —
because nothing on the page fired on its own, and a frame captures every link in the rows. A
debounced field is exactly what that sentence said was absent: a full-page Turbo visit per
keystroke would replace the field being typed in and drop its focus. So the table and its pager
move inside `Tournaments::ShowView::SHEET_FRAME_ID`, with the frame declared **`target="_top"`**:
every link and form in the rows (the deck link, Edit, Delete, "This is me", Unlink) keeps
navigating the whole page without each one learning `data-turbo-frame="_top"`, and only the
pager's two links opt back into the frame, with `turbo_action: "replace"` so `?page=` and the
filters reach the address bar. The broadcast that replaces a row when a field list lands targets
the row's DOM id, which a frame does not change.

## Rate limit: none added, deliberately

`TournamentsController#show` carries no limiter, on the recorded rule "one page load per click,
with no live control behind it". A debounced field is a live control, and `#index` got 60/min for
one. It is **not** copied here: this page is read at the venue, during the event, by a room of
players behind one NAT address — a per-IP limiter on the event page would ration a whole venue's
access to the standings. A filter request costs what a plain load does (same queries, the frame
discards the rest of the markup), so the field raises a human's rate from one per click to a few
per second while typing, the same order as the hover prefetch already accepted for this page.
Revisit if this page's logs show abuse.

## Query cost

Two queries are added to `#show`, both flat in the size of the sheet: the archetype options and
the present divisions. The existing flat-cost test keeps holding the page constant in the number
of standings; a new one holds a filtered request constant too.

## Out of scope

Filtering by record or placement range, sorting, folding variants under a parent, and carrying
filters through write redirects.
