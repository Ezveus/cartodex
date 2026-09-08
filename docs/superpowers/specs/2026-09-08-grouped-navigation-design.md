# The navbar overflows the page at every width, and the fix is fewer top-level entries — Design

Issue: none for the overflow — reported directly, with a screenshot at 1280×853. Closes #105 as a
side effect (see *The hamburger's `aria-expanded`* below).

## Goal

`Ui::AppNavbar` carries nine links plus an email and three account links; `Ui::AdminNavbar` carries
twelve plus three. Above 768px `.navbar-inner` is a single flex row with no `wrap`, and every one of
those items has an incompressible *min-content* width — the email is one unbreakable word,
`.navbar-links` is itself a flex container. The row cannot shrink to fit, so it overflows.

This change replaces the flat rows with five top-level entries in the member navbar — two of them
expanding groups — and three in the admin one, plus an account menu that takes the email and the
account links out of the row. It also puts the app's mark in the brand, which has been a bare word since the icon
shipped in #178.

## The measurements

Measured in Chrome against the dev server, signed in as an admin whose email is exactly as long as
the reporter's (16 characters), reading `getBoundingClientRect` and `scrollWidth`/`clientWidth`
rather than looking at the page:

| Navbar | Viewport | Content needs | Container gives | Document overflows by | Tallest link |
| --- | --- | --- | --- | --- | --- |
| Member | 769 | 1430 | 769 | **661 px** | 54 px |
| Member | 1280 | 1430 | 1232 | **174 px** | 54 px |
| Member | 1600 | 1430 | 1232 | **14 px** | 54 px |
| Member | 1700 | 1430 | 1232 | 0 | 54 px |
| Admin | 769 | 1330 | 769 | **561 px** | 73 px |
| Admin | 1280 | 1330 | 1232 | **74 px** | 73 px |
| Either | 500 (Chrome's floor) | 500 | 500 | 0 | — |

Three things follow, and only the first was suspected.

**The bug is not a tablet bug.** `.navbar-inner` is `max-width: 1200px`, so the row's container is
1232 px wide (1200 plus 2×1rem of padding) at *every* viewport above that. The member navbar needs
1430 px of content. It therefore overflows its own container by a constant **198 px** whatever the
screen — 1280 is merely the width at which that spill also runs off the *document*, which is what
makes a horizontal scrollbar appear and what the reporter saw. Above roughly 1660 px the page stops
scrolling sideways and the only remaining symptom is a navbar that sits visibly off-centre against
the 1200 px column of content below it. Nothing was ever measuring this.

**769 px is far worse than 1280 px, and it is a width CI renders on every run.**
`docs/architecture/frontend.md` records a measurement at 769 px saying the visitor's four-link row
fits with two labels wrapping. That is true, and it is about `Ui::PublicNavbar`. The member navbar
overflows the document by 661 px at the same width and the admin one by 561 px, and neither was
measured when that paragraph was written.

**Labels already wrap and it does not help.** Every member link renders 54 px tall inside a 56 px
band (two lines), and every admin link 73 px (three lines, overflowing the band vertically as well).
Wrapping is what `white-space: normal` buys, and it buys nothing: the min-content width of the row
still exceeds the container, so the row wraps *and* overflows.

## Confirmed decisions (from the brainstorming interview)

1. **Group by object, not by ownership.** `Decks▾`, `Collection`, `Tournaments▾`, `Cards`,
   `Archetypes` in the member navbar. A "Mine / Browse" split was considered and rejected: two
   abstract labels that have to be opened before they say anything. *Collection* was first filed
   inside `Decks▾` — it is what feeds a physical deck — and pulled back out to the top level after
   review: it is an inventory of cards, reached on its own, and a destination that is neither a deck
   list nor the card catalogue does not belong behind either one's disclosure. It sits beside
   `Decks▾` rather than beside `Cards` on purpose, those two names being confusable enough already.
   The fifth entry cost the row 37 px of overflow at 769 px, which is what the responsive wordmark
   below pays for.
2. **Dashboard moves onto the logo.** The brand link already pointed at it.
3. **The account block becomes a menu**, taking the email — the single widest incompressible item in
   the row — out of the row.
4. **The admin navbar gets the same treatment**, `Catalog▾ / Content▾ / Imports▾`. Leaving it flat
   was offered and refused.
5. **Click to open above the breakpoint; below it the groups are sections of the existing drawer,
   already expanded.** No second tap on a phone, and `click_nav_link`'s mobile path is untouched.
6. **The mark is inline SVG with its mat lightened**, because `#0E1320` — the mat's fill in
   `public/icon-small.svg` — is exactly `--ink-900`, the navbar's own background: posted unchanged
   the mark's body is invisible and only the red card and the blue line survive.

## Information architecture

**Member** — `Ui::AppNavbar`:

| Entry | Contains | Sections it lights |
| --- | --- | --- |
| *(the brand)* | Dashboard | `home` |
| `Decks▾` | My decks, Shared decks | `decks`, `shared_decks` |
| `Collection` | — | `collections` |
| `Tournaments▾` | All tournaments, My tournaments, Profiles | `tournaments`, `my_tournaments`, `entries`, `tournament_profiles` |
| `Cards` | — | `cards` |
| `Archetypes` | — | `archetypes` |
| *(account)* | the email, Settings, Admin (if admin), Sign out | none |

**Admin** — `Ui::AdminNavbar`:

| Entry | Contains |
| --- | --- |
| *(the brand)* | Dashboard |
| `Catalog▾` | Card sets, Cards, Card labels, Card roles |
| `Content▾` | Users, Decks, Archetypes, Standard pools |
| `Imports▾` | Imports, Limitless import, Jobs |
| *(account)* | the email, Back to app, Sign out |

**Visitor** — `Ui::PublicNavbar` keeps its four flat links. It measures 4 links and fits; grouping
two of them would be ceremony.

`Dashboard` disappearing as a labelled entry is the one deliberate loss. The brand is a link to it in
all three navbars already, and it is the only entry whose destination the logo can plausibly carry.

## Components

### `Ui::Logo`

Renders the reduced mark inline, `Ui::Logo.new(size: 24)`. Inline rather than
`image_tag "/icon-small.svg"` because the mat has to be recoloured to `--ink-700` to be visible on
`--ink-900`, and an `<img>` cannot be recoloured.

This puts the drawing in a second place. `public/icon-small.svg` stays the favicon's source and
`bin/rails icons:build` stays its rasteriser; the component redraws the same **three** shapes (a
`<g>` holding two rects, plus one outside it). **A test parses both and asserts the geometry agrees** — the `rect`/`g` coordinates, not
the fills, which are exactly what is meant to differ. That is the same anti-drift mechanism
`icons:build` exists to provide for the PNGs, applied to the one derivative it cannot cover.

### `Ui::NavGroup`

```ruby
render Ui::NavGroup.new(
  label: "Decks",
  active_section: @active_section,
  entries: [
    [ "My decks",     decks_path,        %w[decks] ],
    [ "Shared decks", shared_decks_path, %w[shared_decks] ]
  ]
)
```

**Entries are data, not a block, and that is the load-bearing decision.** The group is lit when
`@active_section` is in the union of its entries' sections, computed from the entries themselves. A
group that declared its own sections beside children that declared theirs would be two lists to keep
in step, and the first entry added to a group would forget one of them. This is the same reasoning
that put `SECTION_OVERRIDES` in one table rather than leaving each navbar to guess: "exactly one
entry is lit" has to hold by construction.

It renders three children:

- `<button class="navbar-group-trigger">Decks ▾</button>` with `aria-expanded` and
  `aria-controls`, **`display: none` below 768px**;
- `<span class="navbar-group-heading">Decks</span>`, **`display: none` above 768px** — and *not*
  `aria-hidden`, since below the breakpoint it is the only label on screen and hiding it left the
  drawer as eleven undifferentiated links;
- `<div class="navbar-group-panel">` holding the entries as ordinary `.navbar-link`s.

Two elements carrying one label, rather than one element restyled, so that no JavaScript has to know
about the breakpoint and `aria-expanded` never contradicts what is on screen. The alternative —
one button, `matchMedia`, `disabled` and `aria-expanded="true"` below the breakpoint — was rejected:
it puts the breakpoint in a third place (CSS, `card_preview_controller.js`, and now this) and it
makes the drawer's section headings focusable buttons that do nothing.

The account menu is the same component with `label:` replaced by the user's initial in a chip and
the email rendered as the panel's first, non-interactive row.

### The Stimulus side

`dropdown_controller.js` already implements toggle-plus-outside-click and is used by
`Decks::ActionsDropdown` and `Decks::ExportDropdown`. `Ui::NavGroup` uses it rather than adding a
fourth controller that opens a panel, and the controller gains three things every one of its callers
wants:

- `Escape` closes it (`printing_picker_controller.js` is the precedent, and the only controller in
  the app that binds it today);
- `aria-expanded` is written on the trigger — **this is #105**: the navbar's own hamburger hardcodes
  `aria-expanded="false"` and never updates it, and `navbar_controller.js#toggle` is three lines
  away from the same fix;
- `turbo:before-cache` closes it, for the reason `Search::Overlay` does: a snapshot cached with the
  panel open restores it open, over a page whose links have moved.

## CSS

`.navbar-group` is `position: relative`, its panel `position: absolute` on `--ink-800` with
`--e2` — the dark counterpart of `.dropdown-menu`, which is `--surface` and would be a white card
hanging off a black bar. Inside the `max-width: 768px` block the panel becomes static and always
displayed, the trigger goes to `display: none` and the heading comes back, which is the whole of the
responsive behaviour.

`.navbar-link` gains `white-space: nowrap`. Wrapping was a symptom-level mitigation for a row that
did not fit; the row now fits, and a wrapped label in a 56 px band is worse than a wide one.

## Testing

**The regression test the bug never had.** A system test at 1280×853 via `drive_at` asserting
`documentElement.scrollWidth == clientWidth` and `.navbar-inner`'s `scrollWidth == clientWidth`, for
the member navbar and the admin navbar. `drive_at` is what escapes Chrome's 500 px floor, and 1280
is where the report came from. The corresponding assertion at 769 — where the member navbar is
661 px over — is the harder case and is included.

**The active-section assertions keep working and gain a sibling.**
`NavbarActiveSectionTest#assert_active_nav_link` collects `a.navbar-link.active` and asserts exactly
one; a group trigger is a `<button>`, so that assertion means the same thing after this change as
before it, which is why it is not being rewritten. What is added is the symmetric assertion — the
containing group is lit, and exactly one group is — and the admin cases for the three new groups.

**`click_nav_link` keeps its one-argument signature.** Above the breakpoint it now opens the group
containing the link before clicking it; below the breakpoint the panel is already open and its path
is unchanged. Three of its twelve call sites change label (`"Decks"` → `"My decks"`, and the two
admin ones), and `global_search_test.rb`'s geometry assertion — which compares
`.navbar-search-trigger` against `.navbar-right` — has to follow `.navbar-right` into the account
menu.

**`Ui::Logo` gets the drift test** described above, and `/styleguide` gets both components.

## Out of scope

- Any change to `Ui::PublicNavbar`'s link set. It gains the logo and nothing else.
- Hover-to-open. Refused in the interview: the reported device is a 1280 px touchscreen.
- Keyboard arrow navigation inside a panel. The three existing dropdowns do not have it either;
  adding it here alone would make the navbar the odd one out in both directions.
- Splitting `application.css`, which is #104.
- A persistent "you are here" breadcrumb, or any second navigation surface.
