# Standings import: one Limitless URL instead of six fields

## What changes

`/admin/standings_imports/new` used to take a **Source** select plus five fields (tournament id,
deck id, leaderboard slug, rotation, set), each labelled with the source it belongs to. The admin
had to read the URL they were looking at and split it by hand. The screen now takes **one field,
the Limitless URL**, and derives the source and those five values from it.

Everything downstream is unchanged: the archetype select, the event filters and the top-N cap stay
on the form. The preview's plan, the arbitration table, the confirm forms' hidden fields, `#create`,
`Tournaments::LimitlessImportJob` and its arguments all stay as they were. The confirm forms still
post the *parsed* values (`source`, `deck_id`, `slug`, …), so the POST and the job never see a URL.

## Accepted shapes

| Source | URL | Extracted |
|---|---|---|
| paper | `https://limitlesstcg.com/decks/284/results` (also `/decks/284`, trailing slash) | `deck_id` |
| online | `https://play.limitlesstcg.com/decks/dragapult-ex?format=standard&rotation=2026&set=30C` (trailing slash too, which is how Limitless's own links spell it) | `slug`, `rotation`, `set` |
| event | `https://limitlesstcg.com/tournaments/578`, or any one sub-page of it (`/JR`, `/SR`, `/decklists`, `/statistics`, `/cards`) | `tournament_id` |

`http` and a `www.` prefix are accepted; a fragment is ignored. The parser is
`Tournaments::LimitlessUrl`, and it only *extracts*: the narrowness guards on each value
(`DECK_ID_RE`, `SLUG_RE`, `ROTATION_RE`, `SET_RE`, `TOURNAMENT_ID_RE`) stay in the controller,
where they already refuse before any fetch.

## Refusals, and why each is one

Measured on 2026-10-03 against the live pages:

- **A paper URL carrying `?variant=`** is refused. `decks/284/results?variant=3` serves a different
  page from `decks/284/results`: 1,579,172 bytes against 3,119,579, a subset. `LimitlessResults`
  reads the whole deck and nothing else. Dropping the parameter would import roughly twice the rows
  the admin was looking at, with nothing on the preview saying so.
- **An online URL missing any of `format`, `rotation`, `set`** is refused. Today the bare
  `play.limitlesstcg.com/decks/dragapult-ex` serves byte for byte the same page as
  `…?format=standard&rotation=2026&set=30C`, but that default follows the newest set. `set` anchors
  every row the run writes to a Standard pool, so it must come from the admin and not from whatever
  Limitless's default was that day. Limitless's own filter links always carry all three, so the
  refusal costs a copy-paste.
- **An online URL whose `format` is not `standard`** is refused. The job fetches with
  `ONLINE_FORMAT = "standard"`, whatever the URL says. Accepting `format=expanded` would import the
  Standard leaderboard under a URL that named another one.
- **Any other host or path** is refused, and the message names the three shapes.

A blank field is refused before anything else, with the same message.

## Not done

- `?variant=` support for the paper source. That would change what the import reads, which is out
  of scope.
- The `matchups` sub-page of an online deck. It is not a results page, and nobody asked for it.
- Reading Limitless's default rotation/set off the page.
