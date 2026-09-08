# Plan — grouped navigation, the logo in the brand, and the overflow it fixes

Design: `docs/superpowers/specs/2026-09-08-grouped-navigation-design.md`.

Baselines in this worktree:

- unit — **1713 runs, 8028 assertions, 0 failures, 0 errors, 0 skips** (56.8 s), run in the
  `cartodex-test` container: `libvips` is absent from this host and `test/services/og/renderer_test.rb`
  does `require "vips"` at load, which takes down `bin/rails test` before a single test runs. A
  **single** test file runs fine on the host (measured: `test/components/ui/archetype_badge_test.rb`,
  4 runs, 0 failures), which is what makes host-side TDD on one file possible.
- system, desktop — **98 runs, 294 assertions, 0 failures, 0 errors, 18 skips** (41.4 s).
- system, mobile — **98 runs, 372 assertions, 0 failures, 0 errors, 3 skips** (38.1 s) on the second
  run; the **first run of the same commit failed one test**, which is the known parallel-limit
  flakiness of this suite. A single mobile failure is therefore not evidence of a regression until
  it reproduces.

This plan was rewritten after being attacked. The fourteen findings are recorded at the bottom; the
body already incorporates them, so the two do not disagree.

## Three corrections to the spec, made before any code

**1. `white-space: nowrap` is dropped, and the reason is measured.** The spec proposed it on
`.navbar-link` as a tidy-up once the row fits. It does not fit everywhere: `Ui::PublicNavbar` is the
one navbar this change does *not* regroup, and `docs/architecture/frontend.md` records that its fit
at 769px **depends on** "Shared decks" wrapping to two lines. Measured in Chrome, signed out, at
769px:

| | document overflow | tallest link |
| --- | --- | --- |
| as shipped | **0 px** | 54 px (two lines) |
| with `.navbar-link { white-space: nowrap }` | **48 px** | 35 px |

So the tidy-up introduces, on the visitor's navbar, the exact defect this branch exists to remove.
Wrapping stays what it is — the safety valve for a row that cannot fit — and `nowrap` applies only
**inside a panel** (`.navbar-group-panel .navbar-link`), where the column sizes itself to its
content and there is nothing to overflow.

**2. `public/icon-small.svg` holds three shapes, not five.** The frozen contract said five, which is
`icon.svg`'s count. The reduced mark is a `<g transform="rotate(-11 256 256)">` holding two rects,
plus one rect outside it. The drift test iterates **both** sides and asserts the counts are equal
and equal to three — a test that walks only the component's shapes passes when the component omits
one.

**3. `.navbar-right` does not survive as an alias.** The plan said the account element would keep
`.navbar-right` "so its mobile rules stay". That makes the whole rename a no-op —
`global_search_test.rb`'s gap assertion would resolve the same node before and after and prove
nothing. The member and admin navbars get `.navbar-account` with its own rules on both sides of the
breakpoint; `.navbar-right` stays, unchanged, on `Ui::PublicNavbar`, which still has one.

## Frozen contract

Everything below is fixed before any lane starts. No lane renegotiates a name.

```ruby
# app/views/components/ui/logo.rb
Ui::Logo.new(size: 26)          # px, square, default 26
# → <svg class="navbar-logo" width="26" height="26" viewBox="0 0 512 512"
#        aria-hidden="true" focusable="false"> … </svg>
# The three shapes of public/icon-small.svg, geometry byte-for-byte. Only the fills differ:
#   mat   #0E1320 → var(--ink-700)   (#0E1320 IS --ink-900, which IS the navbar's background)
#   line  #28324A → var(--ink-500)
#   card  #DD2C16 → var(--flare)     (same value, named through the token)
```

```ruby
# app/views/components/ui/nav_group.rb
Ui::NavGroup.new(
  label:,                 # String, the trigger's text and the drawer heading's text
  id:,                    # String slug, unique per rendered navbar → DOM id "navbar-group-#{id}"
  entries: [],            # [[label, path, [section, …]], …]
  active_section: nil,    # the request's section; the group lights when it is in the union
  initial: nil,           # String — renders a chip instead of the label (the account menu)
  align: :left            # :right puts the panel's right edge on the group's (the account menu)
)
# An optional block is appended inside the panel, after the entries.
```

DOM the CSS and the system tests may rely on:

```html
<div class="navbar-group" data-controller="dropdown"
     data-dropdown-open-class-value="navbar-group-panel--open"
     data-action="turbo:before-cache@document->dropdown#closeNow">
  <button class="navbar-group-trigger" type="button"
          aria-expanded="false" aria-controls="navbar-group-decks"
          data-action="dropdown#toggle keydown->dropdown#keydown"
          data-dropdown-target="trigger">
    Decks<span class="navbar-group-caret" aria-hidden="true"></span>
  </button>
  <span class="navbar-group-heading" aria-hidden="true">Decks</span>
  <div class="navbar-group-panel" id="navbar-group-decks" data-dropdown-target="menu">
    <a class="navbar-link" href="/decks">My decks</a>
    …
  </div>
</div>
```

- lit trigger → `class="navbar-group-trigger active"`; lit leaf → the existing `.navbar-link.active`.
- open panel → `.navbar-group-panel--open`.
- `.navbar-brand` gains `active` on both dashboards — see below.
- the account menu is `.navbar-group.navbar-account`; the email is a `.navbar-user` **inside** its
  panel.

```js
// app/javascript/controllers/dropdown_controller.js — generalised, not replaced
static targets = ["menu", "trigger"]
static values  = { openClass: { type: String, default: "dropdown-menu--open" } }
// open()/close()/toggle()/closeNow() ALL read this.openClassValue — never the literal.
// aria-expanded is written only when a triggerTarget exists (the two deck dropdowns declare none),
//   and after the class write, so a missing target cannot leave a panel stuck open.
// Escape closes. turbo:before-cache closes.
```

## The active-section assertions

`assert_active_nav(trail, path)` replaces `assert_active_nav_link`. The trail is read **out of one
subtree**, not by concatenating two flat `css_select`s — a leaf misfiled into a sibling group
produces an identical flat pair, which is the whole failure the grouping can have:

```ruby
# ["Decks", "My decks"] on /decks · ["Cards"] on /cards · ["Dashboard"] on /dashboard
def assert_active_nav(trail, path)
  # exactly one lit group; its own panel holds exactly one lit leaf; every other group holds none.
  # a lit .navbar-brand contributes the literal "Dashboard" — the one destination in the app with
  # no entry of its own, in both the member navbar and the admin one.
end
```

Driven off a literal table, **one case per row of both IA tables** — six member leaves and twelve
admin leaves. `NavbarActiveSectionTest` today has no case at all for `collections_path`,
`tournament_profiles_path`, or nine of the twelve admin sections, and a group lights identically
from any one of its entries, so "the three admin groups" would be satisfied by three cases while
nine leaves were filed anywhere at all.

## Lanes

Two lanes, both genuinely disjoint from the trunk and from each other, each in **its own worktree**
so it can run its own file (one shared SQLite test database cannot take three concurrent runners —
`config/database.yml` appends no `TEST_ENV_NUMBER`). Everything else is the trunk, done here: the
navbar family is one component graph and splitting it would be coordination, not parallelism.

**Lane A — `Ui::Logo` and its anti-drift test.** Files: `app/views/components/ui/logo.rb`,
`test/components/ui/logo_test.rb`. The test asserts: three shapes on each side and the counts equal;
the geometry identical attribute for attribute, including the `<g transform>` compared as a whole
string; the fill mapping **literally** (`var(--ink-700)` / `var(--ink-500)` / `var(--flare)`) rather
than "differs from the source", since `var(--ink-900)` differs from `#0E1320` as a string and *is*
it as a colour; a guard that no `fill=` in the output matches `--ink-900` or `#0E1320`; and that
`size:` reaches `width`/`height` while `viewBox` stays `0 0 512 512`.

**Lane B — `dropdown_controller.js` and #105.** Files:
`app/javascript/controllers/dropdown_controller.js`, `app/javascript/controllers/navbar_controller.js`,
`test/system/dropdown_controller_test.rb` (new). Its system test drives the **existing** deck Actions
dropdown, which exists on master, so the lane is testable without any trunk markup — and it must
assert the *close* paths there, because that caller declares no `triggerTarget` and Stimulus swallows
the missing-target error on the open path. It also pins the hamburger's `aria-expanded` through
false → true → false on the mobile side (#105).

**Trunk — me.** `Ui::NavLinks`, `Ui::NavGroup`, `Ui::NavbarShell`, the three navbars, the CSS, the
styleguide, `NavbarActiveSectionTest`, `click_nav_link`, the twelve call sites,
`global_search_test.rb`'s gap assertion, and `test/system/navbar_layout_test.rb`.

## Steps

1. **Lane A and lane B dispatched in parallel.** Both write and run only their own files.
2. **Trunk, TDD, in this order** — each step's test written first and seen red:
   1. `Ui::NavGroup` + `test/components/ui/nav_group_test.rb`. The union case uses three entries and
      four sections and lights the group from the **last entry's second** section, so an
      implementation reading only the first entry — or taking a separate `sections:` list — fails.
      Also: `nil` and an unknown section light nothing; the panel id matches `aria-controls`; the
      heading and the trigger carry the same label.
   2. `Ui::NavLinks#nav_group` and the three navbars regrouped.
   3. `NavbarActiveSectionTest` rewritten to the subtree trail helper, with a case per IA row
      (18 leaves), both dashboards via the brand, and the two account-menu assertions:
      `.navbar-menu > .navbar-user` is gone and `.navbar-group-panel .navbar-user` holds the email.
   4. An id-uniqueness assertion on `admin_root_path`, mirroring
      `styleguide_controller_test.rb`'s page-wide one — the styleguide renders `Ui::AppNavbar` and
      can never see two admin groups colliding.
   5. CSS: `.navbar-group*`, `.navbar-account`, the mobile block, `nowrap` **inside panels only**.
   6. `click_nav_link` opens the containing group above the breakpoint; the twelve call sites.
   7. `test/system/navbar_layout_test.rb`, five cases:
      - member and admin, `drive_at 1280, 853` and `drive_at 769, 900`: no overflow on
        `documentElement` **and** on `.navbar-inner`;
      - **signed out** at 769: the same two assertions plus
        `assert_selector ".navbar-links a", count: 4`, which is the case correction 1 exists for;
      - every group opened in turn: `documentElement` still does not overflow and each open panel's
        `rect.left >= 0 && rect.right <= innerWidth`;
      - desktop: a trigger is visible and no heading is; mobile: after the hamburger, a heading is
        visible and no trigger is;
      - a navbar group closed three ways — Escape, an outside click, and `go_back` onto the
        Turbo-cached snapshot — each asserting `assert_no_selector ".navbar-group-panel--open"`.
        This is the only test that can see `openClass` being read rather than hardcoded.
   8. `/styleguide` gains a navigation section.
3. **Integrate the lanes, run the five CI checks here**, then sabotage, then the three reviews.

## What the adversary found

Fourteen decisions the suite would not have noticed. Three are corrected in the body above
(`nowrap`, the shape count, `.navbar-right`); the other eleven each became a named case in step 2.

| # | Decision | Would have stayed green because |
| --- | --- | --- |
| 1 | global `nowrap` | the layout test signs in, so it never renders the visitor navbar — the only one that needs wrapping. **Measured: +48px at 769px.** |
| 2 | an open panel is `position: absolute` | both overflow numbers are read with every panel closed, and a closed panel is `display: none` |
| 3 | the IA tables' 18 leaf→group rows | no case exists for `collections`, `tournament_profiles` or nine admin sections, and a group lights from any one entry |
| 4 | the brand lights on the dashboard | no case ever visits `admin_root_path`; `Ui::AdminNavbar` resolves it to section `"dashboard"` |
| 5 | `openClassValue` read on every path | the only caller lane B renders uses the **default** class, so a hardcoded literal is indistinguishable |
| 6 | `triggerTarget` is optional | Stimulus logs the missing-target error instead of propagating, so the open path still works |
| 7 | the mat is recoloured *away from* the navbar's background | `var(--ink-900)` differs from `#0E1320` as a string and is it as a colour |
| 8 | the component carries every shape | a one-sided walk passes when the component omits one; the contract said five, the file holds three |
| 9 | `size:` is honoured | the geometry comparison must exclude the root `width`/`height` to pass at all |
| 10 | the trail pins nesting | two concatenated flat lists cannot tell a misfiled leaf from a correct one |
| 11 | the group's lit state is the **union** | a case lighting from the first entry is satisfied by `entries.first.last` |
| 12 | the email left the top-level row | the gap assertion holds whatever the boxes contain, and an aliased class makes the rename a no-op |
| 13 | the trigger/heading swap at the breakpoint | `click_nav_link` only needs the leaf visible; it never looks at either element |
| 14 | unique `navbar-group-*` ids | the styleguide's page-wide id check renders `Ui::AppNavbar` and never the admin one |
