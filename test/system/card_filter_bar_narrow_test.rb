require "application_system_test_case"

# The card catalogue's filter bar at a phone's width. It went from six controls to eight when the
# label and role filters landed, and nothing in the repository had ever driven it: the only system
# test that visits /cards does so to click through to a card.
#
# 344px because that is where a bar that cannot shrink runs out of room first, and the sweep's
# mobile half bottoms out at 500 (Chrome's floor) — the case `drive_at` exists for. And the claim
# is geometric rather than textual: `.cards-search-select` is `flex: 0 0 auto`, i.e. it refuses to
# shrink, so `flex-wrap` moves the controls relative to each other but cannot narrow any one of
# them. A control wider than the line overflows the page, and both assertions below would still
# find every select present and correctly labelled.
class CardFilterBarNarrowTest < ApplicationSystemTestCase
  drive_at 344, 780

  setup do
    login_as users(:one), scope: :user
    CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    CardLabel.create!(slug: "energy-acceleration", name: "Energy acceleration",
                      family: "role", position: 70)
  end

  test "every filter control stays inside the bar at a phone's width" do
    visit cards_path

    assert_selector "select[name=label]"
    assert_selector "select[name=role]"

    overflow = evaluate_script(<<~JS)
      (function () {
        const bar = document.querySelector(".cards-search");
        const right = bar.getBoundingClientRect().right;
        const wide = Array.from(bar.children)
          .filter((el) => el.getBoundingClientRect().right > right + 1)
          .map((el) => el.getAttribute("name") || el.tagName);
        return { wide: wide, page: document.documentElement.scrollWidth - window.innerWidth };
      })()
    JS

    assert_empty overflow["wide"],
      "these controls hang outside the filter bar: #{overflow['wide'].join(', ')}"
    assert_operator overflow["page"], :<=, 0,
      "the page scrolls horizontally by #{overflow['page']}px"
  end
end
