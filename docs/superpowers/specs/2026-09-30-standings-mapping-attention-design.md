# Event import: make the lines that need a human stand out, and create an archetype from the line

## Problem

`/admin/standings_imports/preview?source=event` prints one line per distinct Limitless deck. The
lines that need a decision — `proposed`, `ambiguous`, `the name says nothing`, `no candidate`, and
a deck whose list could not be read — rendered as a bare grey word beside green `confirmed earlier`
badges, in the event's own order. Measured on event 578 (2026-09-30): 28 decks, 25 confirmed,
2 proposed, 1 no candidate (`Beedrill`, 371). The three that matter were indistinguishable at a
glance, and the one with no candidate could only be resolved by opening the admin archetype
creator in another tab and re-running the preview — which re-fetches the event.

## Decisions

1. **Two attention levels, carried by the row and by the badge.**
   - *Decide*: nothing is selected (`no candidate`, `ambiguous`, `the name says nothing`, an
     unreadable list). Left unanswered, the deck's rows are blocked. Danger badge, flare rail, wash.
   - *Check*: a machine proposal is selected (`proposed`). Warning badge, bolt rail, wash.
   - *Confirmed earlier*: unchanged, quiet.

   A rail and a wash rather than the rail alone used by blocked events: these rows carry a single
   badge, not a status column, so there is nothing for a wash to compete with.
2. **Lines are ordered Decide, then Check, then Confirmed**, the event's order kept within each
   group. Chosen by the owner. The order is presentation only; nothing downstream reads it.
3. **A summary line under the lead** counts the three groups, so an admin knows how many lines
   they are looking for before scrolling.
4. **An answered Decide/Check line turns quiet in the browser** once its select holds a value
   (a `--answered` modifier), so the admin sees what is left without re-running the preview.
5. **Every line offers "+ New archetype"** (owner's choice: a proposal or an old confirmation may be
   wrong precisely because the right archetype does not exist yet). It opens a primary/secondary
   card search under the select and a *Create & select* button that posts to the existing
   `POST /api/archetypes` — idempotent on the fingerprint pair, race-safe, already used by the
   deck form. The answer is inserted into **every** mapping select on the page (two decks may be
   the same new archetype) and selected on this line. Nothing is persisted as a mapping until the
   confirm form is submitted, exactly as with a select changed by hand.
6. **The card search is pre-filled from the representative list, by the published name — not by
   `Decks::ArchetypeDetector`'s suggestion.** Measured on event 578: the detector's notable-Pokémon
   ranking (rule-box first, then HP) proposes *Beedrill ex / Fezandipiti ex* for `Beedrill` and
   *Cornerstone Mask Ogerpon ex* first for `Okidogi Barbaracle` — rule-box techs, the very
   failure `Tournaments::ArchetypeProposer` exists to avoid. The rule instead:
   - only Pokémon in the list (a name-matched Trainer or Energy is how `Basic Box` would pre-fill
     *Basic Grass Energy*);
   - a card is eligible only if its name shares a token with the deck name (the proposer's own
     `tokens`, so `mega`/`ex`/`box` are ignored the same way);
   - the card covering **most** of the remaining name tokens wins, then the one whose token comes
     first in the name, then the detector's notability order (rule-box, HP, copies);
   - the winner consumes every name token it covers, and the pick repeats once for a secondary.

   So `Rocket's Honchkrow` prefers *Team Rocket's Honchkrow* (two tokens) over *Team Rocket's
   Mewtwo ex* (one); `Cynthia's Garchomp` stops at *Cynthia's Garchomp ex* rather than adding
   *Cynthia's Gabite* on the leftover `cynthia`; `Mega Greninja` picks *Mega Greninja ex* over
   *Greninja ex* on notability and stops; a name matching nothing pre-fills nothing, which is the
   honest answer for `Basic Box`. A confirmed line or one with no readable list has no list read,
   so it opens empty.
7. **The inline fields must never reach the confirm POST.** The card inputs carry no `name`, and
   Enter inside them is swallowed: implicit submission would otherwise run *Confirm mappings and
   import* from a search box.

## Out of scope

- Naming the new archetype (`custom_name`) — the endpoint derives it from the members, as the deck
  form does; renaming stays in the admin panel.
- A parent archetype.
- Re-proposing after a creation: the new archetype is selected, which is the decision.
