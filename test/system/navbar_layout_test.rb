require "application_system_test_case"

# The regression test the navbar never had.
#
# Reported as a broken navbar on a 1280px tablet; measured, it was not a tablet bug at all.
# `.navbar-inner` is `max-width: 1200px`, so its container is 1232px wide at every viewport above
# that, and the member navbar's nine links plus an email and three account links needed **1430px**
# of incompressible width — the email is one unbreakable word and `.navbar-links` is itself a flex
# container, so the row could not shrink to fit and overflowed instead. 1280 was merely the width
# at which that constant 198px spill also ran off the *document*. On master:
#
#   member, 1280px : 174px of document overflow      admin, 1280px : 74px
#   member,  769px : 661px                           admin,  769px : 561px
#
# 769 is the narrowest desktop width, which CI renders on every run, and nothing looked.
#
# Everything here is asserted on **geometry**, not on text: every element involved rendered
# perfectly well in the broken state — it rendered in the wrong place. A text assertion cannot see
# that, which is exactly why this went unnoticed through the nine entries that accumulated.
class NavbarLayoutTest < ApplicationSystemTestCase
  OVERFLOW = <<~JS
    (() => {
      const de = document.documentElement;
      const inner = document.querySelector(".navbar-inner");
      return {
        document: de.scrollWidth - de.clientWidth,
        navbar: inner.scrollWidth - inner.clientWidth
      };
    })()
  JS

  def assert_navbar_fits(where)
    overflow = evaluate_script(OVERFLOW)

    assert_equal 0, overflow["document"], "#{where}: the page scrolls sideways by #{overflow["document"]}px"
    assert_equal 0, overflow["navbar"], "#{where}: the navbar row overflows its container by #{overflow["navbar"]}px"
  end

  # Chrome will not give a window narrower than 500px by any means, so both widths go through
  # `drive_at`, which overrides the viewport via CDP and escapes that floor. Each class is pinned
  # to one width, because `drive_at` is class-level and skips the half of the sweep it is not on.
  class AtTabletWidth < NavbarLayoutTest
    drive_at 1280, 853

    test "the member navbar fits the reported tablet" do
      login_as users(:one), scope: :user
      visit dashboard_path

      assert_navbar_fits "member at 1280"
    end

    test "the admin navbar fits the reported tablet" do
      users(:one).update!(admin: true)
      login_as users(:one), scope: :user
      visit admin_root_path

      assert_navbar_fits "admin at 1280"
    end

    # A panel is `top: 100%` of its group, so the group has to be as tall as the bar or 100% is the
    # bottom of a 34px box centred in a 56px one — measured, the panel then opened 7px *above* the
    # bar's own bottom edge and overlapped it. `align-self: stretch` on `.navbar-group` and
    # `.navbar-links` is what fixes that, and nothing else in the suite measures this dimension:
    # deleting those two declarations leaves all 11 other cases here green.
    test "an open panel hangs below the bar rather than overlapping it" do
      login_as users(:one), scope: :user
      visit dashboard_path

      find(".navbar-group-trigger", text: "Decks").click

      box = evaluate_script(<<~JS)
        (() => {
          const bar = document.querySelector(".navbar").getBoundingClientRect();
          const panel = document.querySelector(".navbar-group-panel--open").getBoundingClientRect();
          return { barBottom: Math.round(bar.bottom), panelTop: Math.round(panel.top) };
        })()
      JS

      assert_operator box["panelTop"], :>=, box["barBottom"],
        "the panel starts #{box["barBottom"] - box["panelTop"]}px above the bar's bottom edge"
    end
  end

  class AtNarrowestDesktop < NavbarLayoutTest
    drive_at 769, 900

    test "the member navbar fits the narrowest desktop width" do
      login_as users(:one), scope: :user
      visit dashboard_path

      assert_navbar_fits "member at 769"
    end

    test "the admin navbar fits the narrowest desktop width" do
      users(:one).update!(admin: true)
      login_as users(:one), scope: :user
      visit admin_root_path

      assert_navbar_fits "admin at 769"
    end

    # Ui::PublicNavbar is the one navbar this change does NOT regroup, and it is therefore the one
    # that can be broken by a rule written for the other two. It nearly was: the plan proposed
    # `white-space: nowrap` on `.navbar-link` as a tidy-up once the row fits, and measured signed
    # out at this width that single declaration takes the visitor's row from 0 to 48px of document
    # overflow — this navbar fits *because* "Shared decks" is allowed to wrap to two lines. The
    # count assertion is what proves this case really rendered the visitor's navbar: signed in, the
    # same page renders a different one and the overflow assertions would pass for the wrong reason.
    test "the visitor navbar fits the narrowest desktop width" do
      visit shared_decks_path

      assert_selector ".navbar-links a.navbar-link", count: 4
      assert_navbar_fits "visitor at 769"
    end

    # A closed panel is `display: none` and so contributes to neither measurement above — the whole
    # of the fit could be true with every panel a viewport-wide overhang. The account menu is the
    # case that matters: it is the last item in the row, so a panel anchored to its left edge opens
    # off the right of the screen, which is what `.navbar-group-panel--right` exists for.
    test "no open panel leaves the viewport" do
      users(:one).update!(admin: true)
      login_as users(:one), scope: :user
      visit admin_root_path

      all(".navbar-group-trigger").each do |trigger|
        trigger.click

        spill = evaluate_script(<<~JS)
          (() => {
            const panel = document.querySelector(".navbar-group-panel--open");
            if (!panel) return "no panel opened";
            const r = panel.getBoundingClientRect();
            return { left: Math.round(r.left), right: Math.round(r.right), viewport: window.innerWidth };
          })()
        JS

        assert_kind_of Hash, spill, "clicking #{trigger.text.strip.inspect} opened nothing"
        assert_operator spill["left"], :>=, 0, "#{trigger.text.strip}: the panel starts off the left edge"
        assert_operator spill["right"], :<=, spill["viewport"],
          "#{trigger.text.strip}: the panel runs #{spill["right"] - spill["viewport"]}px off the right edge"

        trigger.click
      end

      assert_navbar_fits "admin at 769, panels cycled"
    end
  end

  # Making "Collection" a top-level entry cost the member's row 37px of overflow at 769px, and the
  # 91px wordmark is what paid for it — which is what a mark is for. The band is narrow and its
  # edges are the whole rule, so both are pinned: hidden at 880, back at 881, and no overflow on
  # either side of the boundary.
  class AtTheWordmarkBoundary < NavbarLayoutTest
    drive_at 880, 900

    test "the wordmark gives way to the mark where the row has no slack" do
      login_as users(:one), scope: :user
      visit dashboard_path

      assert_selector ".navbar-brand .navbar-logo"
      assert_no_selector ".navbar-brand-word"
      assert_navbar_fits "member at 880"
    end
  end

  class JustAboveTheWordmarkBoundary < NavbarLayoutTest
    drive_at 881, 900

    test "one pixel wider, the word is back and still fits" do
      login_as users(:one), scope: :user
      visit dashboard_path

      assert_selector ".navbar-brand-word", text: "Cartodex"
      assert_navbar_fits "member at 881"
    end
  end

  # The responsive half of Ui::NavGroup is pure CSS — the trigger disappears below the breakpoint
  # and the heading that carries the same label takes its place — and nothing else in the suite
  # looks at either element: `click_nav_link` only needs the leaf to be visible, so a trigger left
  # showing in the drawer, or a heading showing on the desktop, changes nothing it asserts.
  class AboveTheBreakpoint < NavbarLayoutTest
    drive_at 1280, 853

    test "a group is a trigger and not a heading" do
      login_as users(:one), scope: :user
      visit dashboard_path

      assert_selector ".navbar-group-trigger", text: "Decks"
      assert_no_selector ".navbar-group-heading"
    end
  end

  class BelowTheBreakpoint < NavbarLayoutTest
    drive_at 390, 844

    test "a group is a heading and not a trigger, and its links need no second tap" do
      login_as users(:one), scope: :user
      visit dashboard_path

      find(".navbar-toggle").click

      # Case-insensitive because Capybara reads *rendered* text and the drawer's headings are
      # `text-transform: uppercase`. The component's content is "Decks"; pinning "DECKS" here would
      # be asserting a styling choice from a test that is about which of the two elements shows.
      assert_selector ".navbar-group-heading", text: /\ADecks\z/i
      assert_no_selector ".navbar-group-trigger"
      # The panel is open by construction here, which is the point: on a phone the drawer shows
      # every group's links at once rather than making each one a second tap.
      assert_selector ".navbar-group-panel a.navbar-link", text: "Shared decks"
    end
  end

  # The three ways a panel closes, and the only test in the suite that can see the open class being
  # read from `openClassValue` rather than hardcoded: the two deck dropdowns both run on the
  # default, so a literal `"dropdown-menu--open"` anywhere in the controller is invisible to them
  # and breaks only here.
  class ClosingAGroup < NavbarLayoutTest
    drive_at 1280, 853

    setup do
      login_as users(:one), scope: :user
      visit dashboard_path
    end

    test "escape closes an open group" do
      open_decks_group

      find("body").send_keys :escape

      assert_no_selector ".navbar-group-panel--open"
    end

    test "a click outside closes an open group" do
      open_decks_group

      find("h1").click

      assert_no_selector ".navbar-group-panel--open"
    end

    # A snapshot cached with the panel open is restored *open*, floating over a page whose links
    # have moved, and a restoration visit serves it without re-requesting — so nothing repaints it
    # away. Same trap Search::Overlay closes on turbo:before-cache for.
    test "coming back to a cached page does not restore an open group" do
      open_decks_group
      click_on "My decks"

      assert_current_path decks_path
      page.go_back

      assert_current_path dashboard_path
      assert_no_selector ".navbar-group-panel--open"
    end

    # Nothing in the suite observed focus before these two, and both defects they cover were found
    # by driving a browser rather than by reading the code: the whole navigation became a
    # disclosure widget in this change, and a disclosure that loses the user's place is a
    # regression a green suite cannot see.

    # The disclosure contract: Escape hands focus back to the trigger. Without it, closing the
    # panel destroys the focused link — `display: none` — and the browser drops activeElement to
    # <body>, which puts a keyboard user back at the top of the document.
    test "escape from inside a panel returns focus to its trigger" do
      open_decks_group

      # Focused through the DOM and the key sent to whatever is focused, rather than
      # `element.send_keys`: Selenium refuses that on an `<a>` as not interactable, and what this
      # test is about is precisely where focus *is* when the key arrives.
      execute_script(<<~JS)
        [...document.querySelectorAll(".navbar-group-panel--open a.navbar-link")]
          .find(a => a.textContent.trim() === "Shared decks").focus()
      JS
      assert_equal "Shared decks", evaluate_script("document.activeElement.textContent.trim()")

      page.driver.browser.action.send_keys(:escape).perform

      assert_no_selector ".navbar-group-panel--open"
      assert_equal "Decks", evaluate_script("document.activeElement.textContent.trim()")
      # The class list, not an equality: on /dashboard the lit entry is the brand, so this trigger
      # carries no `active` — which is beside the point and would make the assertion a trap for the
      # next person who moves this test to another page.
      assert_includes evaluate_script("document.activeElement.className"), "navbar-group-trigger"
    end

    # The mouse had a way out of an open panel — the document click listener — and the keyboard had
    # none: tabbing past the last link left the panel on screen, still announcing
    # aria-expanded="true", while focus had moved on to the next entry.
    test "tabbing out of an open panel closes it" do
      open_decks_group

      find(".navbar-group-trigger", text: "Decks").send_keys %i[shift tab]

      assert_no_selector ".navbar-group-panel--open"
      assert_selector ".navbar-group-trigger[aria-expanded=false]", text: "Decks"
    end

    private

    def open_decks_group
      find(".navbar-group-trigger", text: "Decks").click

      assert_selector ".navbar-group-panel--open"
      assert_selector ".navbar-group-trigger[aria-expanded=true]", text: "Decks"
    end
  end
end
