require "application_system_test_case"

# The sweep's own guard.
#
# The suite runs twice, once on each side of the 768px breakpoint, and which side is selected by
# SYSTEM_TEST_VIEWPORT. Every other system test then trusts that selection silently: a run that
# believes it is mobile while the browser renders desktop layout does not fail, it passes — on the
# wrong side, proving nothing. Nine tests already did exactly that before #97, which is what this
# issue is about.
#
# So this class asks the browser directly, and it deliberately reads the environment variable rather
# than asking ApplicationSystemTestCase what side it thinks it picked. The question is whether the
# side the *run* was asked for reached the browser; a mechanism reporting on itself cannot answer it.
#
# Both consumers of the breakpoint are checked, because they are two separate reads that could
# disagree: the CSS media query (`@media (max-width: 768px)`, three blocks in application.css) and
# the JS check (`window.innerWidth <= 768` in card_preview_controller.js). They agree on 768 itself
# by one pixel, so a viewport landing exactly on the boundary is the one case where they might not.
class ViewportSweepTest < ApplicationSystemTestCase
  BREAKPOINT = 768

  test "the browser renders on the side of the breakpoint the run asked for" do
    visit root_path

    inner_width = page.evaluate_script("window.innerWidth")
    matches_mobile = page.evaluate_script("window.matchMedia('(max-width: #{BREAKPOINT}px)').matches")

    if ENV["SYSTEM_TEST_VIEWPORT"] == "mobile"
      assert_operator inner_width, :<=, BREAKPOINT,
        "SYSTEM_TEST_VIEWPORT=mobile, but the JS breakpoint check sees a desktop viewport"
      assert matches_mobile,
        "SYSTEM_TEST_VIEWPORT=mobile, but the CSS media query does not match"
    else
      assert_operator inner_width, :>, BREAKPOINT,
        "this run is the desktop half of the sweep, but the JS breakpoint check sees a mobile viewport"
      assert_not matches_mobile,
        "this run is the desktop half of the sweep, but the CSS media query matches mobile"
    end
  end
end
