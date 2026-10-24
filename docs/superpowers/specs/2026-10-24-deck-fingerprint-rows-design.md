# Deck builder: one row per card, split across printings — design

Issue #236. Chained on #235 (Vitest + jsdom). The issue's "Design agreed with the owner" section is
binding; this file records how it is built and the choices it left open.

## Problem, as measured in the code

- `Decks::ShowView#card_list` computed `max_owned = min(quantity, available)` at render, and
  `deck_card_owned_copies_controller.js` kept that bound for the life of the page: after a quantity
  `+`, the real `+` refused silently until a reload.
- `Decks::DeckCardQuantitySetter` recapped `owned_copies` but never claimed a free real copy, unlike
  `Decks::CardAdder` (`Allocations::Backing.greedy`). It also ran outside `serialized_transaction`.
- Splitting 3× MEG 114 into 1× PAL 172 + 2× MEG 114 (deck `lacOsou1l2RXmpj6n4SK_Q`, Boss's Orders)
  took four actions: `−` twice on MEG 114, search PAL 172, add it. The printing picker moved a whole
  row.
- No path from the deck page added a physical copy to the collection.

## What is built

**One row per fingerprint** (`Card#fingerprint_key`: the fingerprint, or `card:<id>` when blank —
the `Decks::Comparator` rule, now a model method both read). A row with one printing in the deck
carries that printing's steppers; a row with several shows the total and the summed
"N real · M proxy", and the steppers sit in its sub-rows. The row expands, when the catalogue holds
another printing, into: the printings in the deck, then printings the member owns at 0 copies, then
an "Other printings (N)" disclosure for the rest. Each sub-row carries the quantity stepper, the
real/proxy stepper (physical decks), and **⇄**, which moves one copy into that printing from the
in-deck printing holding the most copies, named in its tooltip.

**Greedy everywhere.** A quantity increase claims free real copies through
`Allocations::Backing.greedy` (so does ⇄, for the copy it lands); a decrease drops proxies first and
never claims. That is `Decks::DeckCardQuantitySetter`, and therefore MCP `set_deck_card_quantity`,
whose description says so.

**"+ add to my collection and use it here"** is offered on a physical deck's printing when it has a
proxy and no free copy. `Decks::CollectionCopyAdder` adds one copy to the collection
(`Collections::CardAdder`, language and finish `unknown`) and backs one proxy with it, in one
`serialized_transaction`.

**The server renders, the browser applies.** Every write answers with the fingerprint's whole state
(per printing: quantity, real, proxies, `max_owned`, available, owned, over-allocated, ⇄'s default
source, whether "add to collection" is offered), the fingerprint's rows rendered by the same Phlex
components as the page, the placement of each row (its section and the ordered keys of that
section), the empty shell of any section a new row needs, every section's counts, and the deck's
total and Proxies flag. Every button carries the request it sends (URL, method, body) as Stimulus
action params rendered by the server, with `disabled` decided server-side, so
`deck_rows_controller.js` computes no quantity, no bound and no order. Adding from search uses the
same answer: no Turbo reload, whether the fingerprint is new or not.

**`?group=set`** stays one row per printing, each with a sub-row's controls and its name.

**Public page:** the same fingerprint rows, the total and each printing's count behind a disclosure;
no stepper, no real/proxy, no collection data. It builds its rows with `FingerprintStates.deck_only`,
which reads nothing but the deck's own cards and runs no query, so the pinned 7 queries hold.

**Image export contract:** `.deck-card-item` marks exactly one in-deck printing and carries
`data-card-preview-url` and a `.deck-card-qty` with that printing's count. A multi-printing summary
line prints its total in `.deck-card-total`, not `.deck-card-qty`, so the export lists each printing
once and never the total twice.

## Decisions the issue left open (`owner may reverse`)

Each is evaluated on the motivating case: Boss's Orders, 3× MEG 114, wanted 1× PAL 172 + 2× MEG 114.

1. **"Other printings" are rendered with the page, hidden**, rather than fetched when opened. One
   render path and no extra endpoint; the cost is HTML for printings nobody opens (a printing
   sub-row is a few hundred bytes). *Lazy*: the same clicks plus one request on first open. On the
   case: identical — expand, open "Other printings" if PAL 172 is not owned, ⇄ on PAL 172.
2. **⇄'s source is the in-deck printing with the most copies; a tie goes to the first in catalogue
   order** (newest set first, the `Cards::Printings` order). *Alternatives*: the oldest set, or the
   printing with the most proxies (so a real copy is never the one moved). On the case: MEG 114 is
   the only candidate, so every rule gives 2× MEG 114 + 1× PAL 172 in one click.
3. **Order inside an expanded row: catalogue order within each group** (in deck, owned, others).
   Quantity order was rejected because a sub-row would jump under the cursor after a `+`. The public
   page, which may not query `card_sets`, orders its sub-rows by set code then number. On the case:
   MEG 114 first, PAL 172 among owned or others.
4. **Section headings count fingerprint rows as "unique"**, on both pages — the unit the page now
   shows. *Alternative*: keep counting printings. On the case: Supporter "(N — U unique)" counts
   Boss's Orders once whether it is 3× MEG 114 or 1× PAL 172 + 2× MEG 114.
5. **Only an increase claims free copies; a decrease never does.** *Alternative*: re-derive greedily
   on every write. On the case: ⇄ moves a proxy-or-real copy off MEG 114 (a proxy first) and backs
   PAL 172 with a free copy when there is one.
6. **"+ add to my collection" is refused by the API when there is no proxy to back or a free copy
   already exists** (the button is only rendered then). Allowing it with free copies would let one
   click claim several reals. On the case: offered on PAL 172 after ⇄ only when the member owns no
   free PAL 172.
7. **The expand toggle exists only when the catalogue holds another printing**; a single-printing
   row's expansion does not repeat the printing it already shows.
8. **The summary line of a multi-printing row previews the printing with the most copies.**
9. **`GET …/printings` and `PATCH …/printing` stay** (no JS caller once the picker is gone; MCP calls
   the services) and `PATCH …/printing` now also answers the fingerprint payload.

## Out of scope

Decreasing the collection from the deck page (stays on the card and collection pages); a move tool
for MCP; lazy rendering (see 1).
