require "application_system_test_case"

module CardRoleCuration
  def sign_in_admin_with_roles
    @admin = users(:one)
    @admin.update!(admin: true)
    login_as @admin, scope: :user
    @roles = CardLabel::ROLES.to_h do |attributes|
      [ attributes[:slug], CardLabel.create!(family: "role", **attributes) ]
    end
    @card = cards(:budew_pre)
  end
end

# The screen answers with the row the database holds, not with the box the browser ticked — which
# is only observable in a browser: the request is fired by Stimulus on `change`, and the reply is a
# Turbo Stream replacing the row. A controller test proves the write; this proves the click reaches
# it and the answer lands.
class AdminCardRolesTest < ApplicationSystemTestCase
  include CardRoleCuration

  setup { sign_in_admin_with_roles }

  test "an admin ticks a role and the row comes back decided" do
    visit admin_card_roles_path(played: "0", q: "budew")

    assert_selector "#card-role-#{@card.fingerprint}"

    find("#card-role-#{@card.fingerprint} input[value='gust']").click

    # The assertion is on the *server's* answer: the box stays ticked because the row was replaced
    # by one the database rendered, not because the browser left it where the click put it.
    assert_selector "#card-role-#{@card.fingerprint} input[value='gust'][checked]"
    assert CardLabelAssignment.exists?(fingerprint: @card.fingerprint, source: "curated",
                                       rejected: false, card_label: @roles["gust"])
  end

  # Unticking is a refusal and not a deletion, and the two are indistinguishable on the page until
  # the row comes back: an unticked box is what both look like.
  test "unticking a suggestion records the refusal rather than clearing it" do
    @roles["gust"].assignments.create!(fingerprint: @card.fingerprint, source: "suggested")
    visit admin_card_roles_path(played: "0", q: "budew")

    assert_selector "#card-role-#{@card.fingerprint} .card-role-choice--suggested"

    find("#card-role-#{@card.fingerprint} input[value='gust']").click

    assert_no_selector "#card-role-#{@card.fingerprint} input[value='gust'][checked]"
    assert CardLabelAssignment.exists?(fingerprint: @card.fingerprint, source: "curated",
                                       rejected: true, card_label: @roles["gust"])
  end
end

# Nine cells on one row — the card, its type and seven checkboxes — on a screen 390px wide. Below
# 768px `.data-table` turns each row into a card whose cells are `display: flex` with a `::before`
# label, and a checkbox cell that overflowed would read as a row wider than the page rather than
# as an error. Geometry, not text: the text renders fine either way, which is exactly what made
# the same defect invisible to a text assertion on the archetype catalog.
class AdminCardRolesNarrowTest < ApplicationSystemTestCase
  include CardRoleCuration

  drive_at 390, 844

  setup { sign_in_admin_with_roles }

  test "a row's nine cells stay inside the page at 390px" do
    visit admin_card_roles_path(played: "0", q: "budew")

    row = find("#card-role-#{@card.fingerprint}")
    container = find(".admin-container")

    assert_operator row.rect.width, :<=, container.rect.width + 1,
      "the row is wider than the page's container"

    all("#card-role-#{@card.fingerprint} .data-table-cell").each do |cell|
      assert_operator cell.rect.x + cell.rect.width, :<=, row.rect.x + row.rect.width + 1,
        "a cell overflows the row"
    end
  end
end
