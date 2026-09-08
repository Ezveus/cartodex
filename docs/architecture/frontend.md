# Frontend: design system, global search, navbars, shared components

The token system every view colours from, the spotlight reachable from every page, the three navbars, and the pickers more than one form renders.

This file carries detail that used to sit inline in `CLAUDE.md`. Everything here is a decision with a measurement behind it — read it before changing the code it covers, because most entries record something that was already tried and rejected.

Design records:

- `docs/superpowers/specs/2026-08-13-dashboard-search-design.md`

---

**All three navbars go through `Ui::NavbarShell`**, the admin one included. The shell exists for the test suite as much as for looks: below 768px `.navbar-menu` is `display: none` until the `navbar` Stimulus controller adds `.navbar-menu--open`, and `click_nav_link` drives exactly that — so a navbar missing the toggle fails every mobile system test that navigates while looking like a Capybara visibility bug. `Ui::AdminNavbar` was the last one carrying its own copy of that markup, and therefore the only one that would not pick up a fix made in the shell; it now passes `brand_label:`, `brand_active:` and `nav_class:`, the three things that actually differ. The brand renders `Ui::Logo` beside the word, and takes `active` on the page it points at — since grouping dropped "Dashboard" as an entry of its own, the brand is the only thing pointing there, which is why `brand_active:` is a parameter rather than a section read in the shell: the shell is the one navbar component that does not know what a section is, and each navbar resolves its own home (`"home"` for the two app ones, `"dashboard"` for the admin panel). Moving it was invisible to the suite until `test/system/admin_navigation_test.rb` existed, since nothing had ever visited the admin panel through its navbar. `nav_link` lives in `Ui::NavLinks`, a module rather than a method on the shell: the shell takes its links as a block, and a block is evaluated in the *caller's* context. **What lights an entry is a nav section, not a controller name.** `Ui::NavLinks.section_for(controller_name, action_name)` resolves a request to exactly one section, keyed on `(controller_name, action_name)` through a `SECTION_OVERRIDES` table rather than the controller name alone: `decks#shared` becomes `"shared_decks"` because `DecksController` serves both deck lists, and `tournaments#mine` becomes `"my_tournaments"` for the same reason — `TournamentsController` serves both the public catalog and the member's own entries. Every other route falls through to its controller name unchanged, and `nav_link` takes the sections that light it, so "one entry is lit" holds by construction rather than by two independent rules agreeing. Keying on `controller_name` alone is what used to light "Decks" and "Shared decks" together on every deck page. A link declaring **two** sections is the visitor's navbar: it has no "Decks" entry, so its "Shared decks" link is what a shared deck's own page must light, while the member's navbar splits the same pages between its two entries. `test/controllers/navbar_active_section_test.rb` asserts the count as well as the label, per page and per navbar — a rule that lights two entries and a rule that lights none fail it differently.

**Design system**: A single CSS-custom-property token system lives at the top of `app/assets/stylesheets/application.css` (neutrals, brand `--flare`, a per-energy-type palette, semantic result colours, elevation, and `--font-*` roles), with three override layers at the bottom of the file (base typography/dark navbar; energy-typed badges + holo treatment; the deck row's narrow-screen rules). Those layers are all single-class specificity, and a media query adds none — so a responsive rule that has to beat one of them says so in its selector (the last layer is scoped to `.deck-card-list`) rather than relying on sitting later in the file, which the next layer appended below would silently undo. Self-hosted fonts (Archivo / IBM Plex Sans / IBM Plex Mono) are in `app/assets/fonts`. `Card::TYPE_TOKENS` maps each energy type to its colour token — use it (not literal hexes) when colouring by type. A living reference renders the real tokens and components at **`/styleguide`** (`Styleguide::PageView`, non-production only); update it when adding components or tokens.

**Global search.** `Search::Spotlight` is reachable from every page, and a page carries **exactly one** of it — `Search::ResultsView::FRAME_ID` is a DOM id and Turbo resolves a frame by id, so a second spotlight would swallow the first one's results. `Ui::SearchTrigger` (a magnifier plus the ⌘K hint) is rendered by `Ui::NavbarShell` **outside `.navbar-menu`**, because below 768px that menu is `display: none` until the hamburger opens it and a search you must unfold a menu to reach is not reachable from anywhere; CSS `order`, not DOM order, puts it right of the links above the breakpoint. Where the page has no field of its own the trigger opens `Search::Overlay`, a `<dialog>` wrapping the same component; on the dashboard and the styleguide, which render one inline, `SearchOverlayHost#search_overlay?` suppresses the dialog and the trigger focuses the field already there. That concern is included by `ApplicationController` **and** by `Oauth::AuthorizationsController` — `Layouts::ApplicationLayout` has two hosts, and a layout helper missing on the second is a 500 on the consent screen alone. The `search-overlay` Stimulus controller sits on `<body>` (the trigger is in the navbar, the field is elsewhere) and owns ⌘K / `/` outright: `dashboard-search` no longer binds them, since the shortcut may have a dialog to unfold first. Esc is handled on the dialog rather than left to its native cancel — the field's own Esc handler calls `preventDefault`, which kills it; the event still bubbles, so one press empties the query and closes the overlay. The admin panel is out: `Layouts::AdminLayout` renders neither the overlay nor the controller, so `Ui::AdminNavbar` passes `search: false`.

Four details keep the trigger and the field from working against each other, each with a system test behind it. The trigger carries **`data-search-surface`**, which `dashboard-search#clickOutside` treats as inside the search: that watcher sits on the document, so the click that opens the search reaches it *after* `open()` ran, and collapsing there dismissed the panel the click had just restored — leaving the arrows and Enter dead until the query text changed. The dialog's padding lives on a **`.search-overlay-content` wrapper**, because a click reported against the dialog element is precisely how `clickBackdrop` recognises a click outside the panel, so padding on the dialog itself made the visible ring around the field a dismiss zone. **`turbo:before-cache` closes it**: the overlay's usual exit is a result that navigates away, and a snapshot cached with an open `<dialog>` restores it *non-modal* — no backdrop to click, and `open()` reads it as already open, so nothing on the page can dismiss it again. And only the trigger takes the navbar's free space: **`.navbar-right`'s `margin-left: auto` is zeroed when a trigger precedes it** (the admin navbar, which has none, keeps it), since two auto margins split that space and park the magnifier mid-navbar — the same construct the mobile block fixes for the hamburger. The **⌘K hint is written by the controller on connect**, never by the template: `shortcut()` takes Ctrl+K just as readily, only the client knows which key this keyboard has, and it writes `hintTargets` rather than the first one because the styleguide renders the shipped trigger beside the navbar's own.

`Ui::CardSelect` (Stimulus `card-select`) is the card autocomplete behind all three archetype pickers — the admin form, `Ui::ArchetypePicker` and the deck result modal. `Ui::ArchetypePicker` used to be `Decks::ArchetypeField`, soldered to a deck (it read `@deck.key` for the Suggest button and `@deck.archetype&.name` for the input's value); it now lives under `Ui::` and takes an **optional** `deck_key:`, because the tournament standings form renders the same picker for a row that has an archetype and no deck. `deck_key: nil` renders no Suggest button — the only thing here a deck is needed for — and the `archetype-picker` Stimulus controller already tolerates the missing value, since `deckKey` is declared as a String value and Stimulus defaults an absent one to `""`. It searches **every** card type and never deduplicates results by name: which printing an archetype designates is the user's choice, so collapsing them would hide every option but the first. The endpoint behind it (`Api::CardsController`) caps how many printings of one name may take its 20 slots (`PRINTINGS_PER_NAME`), ranked newest-first over the whole match rather than over a fetched prefix — otherwise a heavily reprinted card fills the list and a differently named card is unreachable whatever the user types; the older printings are reached by naming the set, which the query parser already understands. All three pickers fill their input with `Card#printing_label` ("Name (SET NUMBER)"), the same label the admin form pre-fills, because a bare name does not say which printing the hidden id now holds.

`Ui::StandardPoolNotice` tells a user their deck or tournament is anchored to a Standard pool other than the expected one, and is **informative only** — the anchor is pinned by design and nothing moves it automatically. It lives under `Ui::` because both the deck and tournament forms render it, and **no string it emits may name a record type or mention a date**: a deck has no date, and a tournament's mismatch can run in either direction (its anchor may be older *or* newer than the pool its date calls for). The `expected` pool it is handed differs by caller — `StandardPool.current` for a deck, `StandardPool.at(date)` for a tournament — because those are different questions: a deck's mismatch is staleness, a tournament's is a data-entry error.

**A row of links does not shrink to fit, and the paragraph that used to sit here said so about the
wrong navbar.** It recorded that at 769 px — the narrowest desktop width, which CI renders on every
run — the visitor's four links fit with two labels wrapping, and read that as a property of all
three navbars. It was only ever true of `Ui::PublicNavbar`. Measured signed in, with `scrollWidth`
against `clientWidth` rather than by looking:

| Navbar | 769 px | 1280 px | 1600 px | 1700 px |
| --- | --- | --- | --- | --- |
| member, before grouping | 661 px over | 174 px | 14 px | 0 |
| admin, before grouping | 561 px over | 74 px | — | — |
| either, after grouping | **0** | **0** | **0** | **0** |

`.navbar-inner` is `max-width: 1200px`, so its container is 1232 px at *every* viewport above that
and the member navbar's 1430 px of content overflowed it by a constant 198 px regardless of screen
— 1280 was merely where that spill also left the document. Wrapping was not a mitigation: every
member link rendered 54 px tall in a 56 px band and every admin link 73 px, and the row overflowed
anyway, because a flex item's floor is its *min-content* width and the email is one unbreakable
word.

**Two rules follow, and both are counter-intuitive enough to be worth stating.** First,
`white-space: nowrap` on `.navbar-link` is **forbidden**: `Ui::PublicNavbar` is the one navbar not
grouped, it fits at 769 *because* "Shared decks" wraps to two lines, and that single declaration
measurably takes it from 0 to 48 px of document overflow. `nowrap` lives on
`.navbar-group-panel .navbar-link`, where the column sizes itself to its content. Second,
`.navbar-inner`'s `gap` is **1.5rem, not 2**: `.navbar-menu` is `display: contents`, so that gap
falls between four items in the visitor's row, and adding the brand mark at 2rem took that navbar
to 6 px of overflow.

**`Ui::NavGroup` is an entry that expands, and it takes its entries as data rather than as a
block.** The group lights when the request's section is in the union of its entries' sections, and
that union is computed from the entries — so a link added to a group cannot be forgotten by a
second list, which is the same property `Ui::NavLinks.section_for` gives the flat links. It renders
**three** children: a `<button>` trigger hidden below 768 px, a `<span>` heading carrying the same
label hidden above it, and the panel — absolutely positioned above the breakpoint, a plain
always-open section of the drawer below it. One element restyled by a media query was the obvious
alternative and is wrong twice: it puts the breakpoint in a third place beside the CSS and
`card_preview_controller.js`, and it leaves a button announcing `aria-expanded="false"` over a panel
the drawer is showing. `.navbar-group` and `.navbar-links` are `align-self: stretch` so that the
panel's `top: 100%` is the *bar's* bottom edge — centred in the row, a group is a 34 px box in a
56 px bar and its panel opened 7 px above the bar's own bottom.

`Ui::NavGroup` drives the shared `dropdown` controller rather than a fourth controller that opens a
panel; the controller's open class is a Stimulus value (default `dropdown-menu--open`, the navbar
passes `navbar-group-panel--open`) and **every** path reads it, since the two deck dropdowns run on
the default and a hardcoded literal is invisible to them. `trigger` is an optional target for the
same reason, and the class is written before the `aria-expanded` so a missing one cannot strand a
panel open. `test/system/navbar_layout_test.rb` is the only test in the suite that can see either
rule.

**The trail, not the label, is what `NavbarActiveSectionTest` asserts.** `assert_active_nav` reads
`[group, leaf]` out of **one** subtree — the lit group's own panel — because two flat `css_select`s
cannot tell a leaf filed into the wrong group from a correct one, and that misfiling is the only
new mistake grouping makes possible. Every row of both navbars' entry tables has a case, eighteen
leaves in all: a group lights identically from any one of its entries, so a handful of cases would
leave most leaves free to sit anywhere. Dashboard has no entry of its own — the brand is the only
thing pointing there, so the brand takes the class, and the helper reads the brand's *own text*
rather than substituting a literal, which is what makes the same assertion cover the admin panel's
differently-labelled front page.
