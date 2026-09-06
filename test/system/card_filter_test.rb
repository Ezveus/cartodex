require "application_system_test_case"

# Picking a label out of the filter bar, which is the path a reader actually takes and the one
# nothing covered: the bar sits **outside** the Turbo Frame its form targets, so the server never
# re-renders it, and every request test in the suite arrives at `?label=…` by typing the URL. What
# this proves that they cannot is that `change->card-filter#submit` reaches the new controls, that
# the frame swaps, and that `turbo_action: "replace"` puts the filter in the address bar — so a
# reader can share what they are looking at.
class CardFilterTest < ApplicationSystemTestCase
  setup do
    label = CardLabel.create!(slug: "ace-spec", name: "ACE SPEC", family: "type", position: 10)
    label.assignments.create!(fingerprint: cards(:bosss_orders_meg).fingerprint,
                              card: cards(:bosss_orders_meg), source: "imported")
  end

  test "a visitor picks a label and the catalogue narrows to it" do
    visit cards_path
    assert_text "Select a set or search to browse cards."

    select "ACE SPEC", from: "label"

    assert_selector ".card-grid-name", text: "Boss's Orders"
    assert_no_selector ".card-grid-name", text: "Honedge"
    assert_current_path(/label=ace-spec/)
  end
end
