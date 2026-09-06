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

  # Agreeing is the commonest answer on this screen, and it has to be one click: the row submits
  # on `change`, so without a Save button confirming a suggestion meant ticking a role that is
  # wrong — publishing it — and unticking it again.
  test "an admin confirms a suggestion without changing a box" do
    @roles["gust"].assignments.create!(fingerprint: @card.fingerprint, source: "suggested")
    visit admin_card_roles_path(played: "0", q: "budew")

    find("#card-role-#{@card.fingerprint} input[type='submit']").click

    assert_selector "#card-role-#{@card.fingerprint} .card-role-choice--decided"
    assert CardLabelAssignment.exists?(fingerprint: @card.fingerprint, source: "curated",
                                       rejected: false, card_label: @roles["gust"])
  end

  # The way back out. The button lives in the row and the form it submits is a hidden sibling —
  # forms cannot nest — so this also proves the HTML5 `form` attribute wiring, which no request
  # test can see.
  test "an admin clears a row's decisions and hands the card back to the rules" do
    @roles["gust"].assignments.create!(fingerprint: @card.fingerprint, source: "curated")
    visit admin_card_roles_path(played: "0", q: "budew")

    accept_confirm { find("#card-role-#{@card.fingerprint} button", text: "Clear").click }

    assert_no_selector "#card-role-#{@card.fingerprint} .card-role-choice--decided"
    assert_equal 0, CardLabelAssignment.curated.where(fingerprint: @card.fingerprint).count
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

  # The unlabellable row's note must sit *under* the card's name and not beside it. Both render
  # either way — which is exactly why this is measured rather than asserted on text: as flex
  # siblings in a cell that is `justify-content: space-between`, the note is pushed to the far
  # right of the row and the name has half a cell to live in.
  test "the no-fingerprint note stacks under the card name at 390px" do
    visit admin_card_roles_path(played: "0", q: "Boss")

    row = "#card-role-unfingerprinted-#{cards(:trainer_card).id}"
    # Scoped to the card cell: the Decision cell of the same row carries its own note saying the
    # row cannot be written, and this test is about the one under the card's name.
    unlabellable = find("#{row} .card-role-card .card-role-note")
    name = find("#{row} .card-role-name")

    assert_operator name.rect.y + name.rect.height, :<=, unlabellable.rect.y + 1,
      "the note is beside the card name rather than under it"
  end
end
