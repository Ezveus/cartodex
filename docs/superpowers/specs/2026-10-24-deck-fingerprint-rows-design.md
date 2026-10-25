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
another printing, into: the printings in the deck, then an "Other printings (N)" disclosure for
every printing it does not play — the ones the member owns first, then the rest — fetched the first
time it opens (see decision 1). Each sub-row carries the quantity stepper, the
real/proxy stepper (physical decks), and **⇄**, which moves one copy into that printing from the
in-deck printing holding the most proxies (then the most copies), named in its tooltip.

**Greedy everywhere.** A quantity increase claims free real copies through
`Allocations::Backing.greedy` (so does ⇄, for the copy it lands); a decrease drops proxies first and
never claims. That is `Decks::DeckCardQuantitySetter`, and therefore MCP `set_deck_card_quantity`,
whose description says so.

**"+ add to my collection and use it here"** is offered on a physical deck's printing when it has a
proxy and is not over-allocated. `Decks::CollectionCopyAdder` adds one copy to the collection
(`Collections::CardAdder`, language and finish `unknown`) and then backs the row greedily
(`Allocations::Backing.greedy` over a fresh availability), in one `serialized_transaction` — so
with free copies already in the collection one click may back several proxies.

**The server renders, the browser applies.** Every write answers with the fingerprint's whole state
(per printing: quantity, real, proxies, `max_owned`, available, owned, over-allocated, ⇄'s default
source, whether "add to collection" is offered), the fingerprint's rows rendered by the same Phlex
components as the page, the placement of each row (its section and the ordered keys of that
section), the empty shell of any section a new row needs, every section's counts, and the deck's
total and Proxies flag. Every button carries the request it sends (URL, method, body) as Stimulus
action params rendered by the server, with `disabled` decided server-side, so
`deck_rows_controller.js` computes no quantity, no bound and no order. The steppers send a step
(`quantity_delta` / `owned_copies_delta`, ±1) that the setter resolves inside its transaction, never
the count the page shows: from a stale tab, an absolute "−" (page at 4, server at 1) arrived as an
increase to 3 and claimed reals. Adding from search uses the same answer — no Turbo reload, whether the
fingerprint is new or not — and is sent by `deck_rows_controller.js` itself, after the write in
flight, so an older stepper answer can never land on top of it.

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

1. **"Other printings" are fetched on first open** — every printing the row's card holds outside
   the deck, owned or not, behind one disclosure. *Reversed by the owner*: the first build rendered
   them with the page, hidden, and listed the owned ones in the expansion itself. The page now
   renders the disclosure alone: its count ("Other printings (N)", beside "All printings (M)" on
   the row's toggle) costs no query, FingerprintStates having read every printing already for ⇄ and
   M, and the owner page's query count is unchanged (15 on the B7 test's deck before and after).
   Opening it the first time, `deck_rows_controller.js#others` fetches
   `GET /api/decks/:deck_id/cards/:id/other_printings` — owner-only and deck-scoped like every
   `Api::DeckCards*` action (another member's deck is a 404, a visitor a 401), keyed on the card's
   fingerprint so any printing of it names the list — inserts the server-rendered sub-rows
   (`Decks::OtherPrintingRows`) and never fetches again; a failure flashes the server's reason and
   closes the list, so the next open retries. **A write's answer renders the list whole**: the row
   it re-renders replaces one whose list the member may have opened, and the page re-opens every
   disclosure that was open, so the list comes back open with fresh ⇄ and + states, and one never
   opened needs no fetch later. That was weighed against refetching after the write (a second
   request per write and a window where the opened list is empty) and against telling the server
   which lists are open (state the server would have to trust); one fingerprint's printings are a
   few hundred bytes each in an answer that already carries the row. A fetch answered after a write
   replaced its row lands in the list that row took out of the page, never over the newer one. On
   the case: expand, open "Other printings", ⇄ on PAL 172 → 2× MEG 114 + 1× PAL 172 — whether the
   member owns PAL 172 or not, which is one click more than before when they do.
2. **⇄'s source is the other in-deck printing with the most proxies; a tie goes to the one with the
   most copies, then to the first in catalogue order** (newest set first, the `Cards::Printings`
   order). *Reversed by the owner*: the first build took the most copies, which could move a real
   copy off a fully backed printing while another printing still played proxies; moving a proxy
   leaves every physical card where it is. On a non-physical deck proxies are not compared at all
   (every copy is one there), so the rule is the most copies. The row's display card still goes by
   copies alone. On the case: MEG 114 is the only candidate, so every rule gives 2× MEG 114 + 1×
   PAL 172 in one click.
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
6. **"+ add to my collection" is refused by the API only when there is no proxy to back or the
   printing is over-allocated** (the button is only rendered otherwise: on an over-allocated
   printing the added copy would not be free for this deck, so the collection write is rolled back
   with the refusal). *Reversed by the owner*: the first build also refused when a free copy already
   existed, to keep one click from claiming several reals; the owner accepted exactly that — the
   click adds one copy and backs greedily, the free copies and the new one alike. One consequence
   follows from the rule as stated: when the free copies already cover every proxy, the click still
   adds a copy to the collection, which this deck then does not need. On the case: offered on PAL
   172 after ⇄ whenever it plays a proxy there.
7. **The expand toggle exists only when the catalogue holds another printing**; a single-printing
   row's expansion does not repeat the printing it already shows. "N printings" always counts the
   printings in the deck; the owner's toggle reads "All printings (M)", counting the catalogue.
8. **The summary line of a multi-printing row previews the printing with the most copies.**
9. **`GET …/printings` and `PATCH …/printing` stay** (no JS caller once the picker is gone; MCP calls
   the services) and `PATCH …/printing` now also answers the fingerprint payload.

## Out of scope

Decreasing the collection from the deck page (stays on the card and collection pages); a move tool
for MCP.
