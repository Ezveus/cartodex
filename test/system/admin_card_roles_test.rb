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

  # The Turbo Stream replaces one element, so the row's form and the hidden form its Clear button
  # submits have to be one element: with the id on the form alone, each save inserted a fresh
  # clear form beside the one already there — measured, two after two saves, both carrying the
  # same id, which is invalid markup and a stale target waiting to be picked.
  test "saving a row twice leaves exactly one clear form behind it" do
    visit admin_card_roles_path(played: "0", q: "budew")

    find("#card-role-#{@card.fingerprint} input[value='gust']").click
    assert_selector "#card-role-#{@card.fingerprint} input[value='gust'][checked]"

    # The second save has to *change* something, or nothing on the page tells the test that the
    # server's answer has landed: asserting the state the row is already in passes against the old
    # row, the count runs before the replacement, and the test proves nothing. Unticking is
    # observable — and a refusal is still a decision, so the row stays decided.
    find("#card-role-#{@card.fingerprint} input[value='gust']").click
    assert_no_selector "#card-role-#{@card.fingerprint} input[value='gust'][checked]"
    assert_selector "#card-role-#{@card.fingerprint} .card-role-choice--decided"

    assert_equal 1, all("form.card-role-clear-form", visible: :all).size
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

# The desktop half of the same geometry, and the half that had no test at all. Above 768px
# `.card-role-choice-name` is `display: none`, so the column header is the **only** visible thing
# naming a checkbox — and the header divides the row by its own rules, not the row's, because
# `flex: 1` floors a flex item at min-content. A header of long words therefore drifts from the
# cells it labels once its min-content sum passes the container.
#
# Measured when two roles took this table from ten cells to twelve: at a 1100px window the header
# overflowed by 40px and put three checkboxes under the wrong role name, where the ten-cell version
# fitted exactly. The same table was already misaligned at 1000px before that, so this pins a
# pre-existing defect as well as the regression that surfaced it.
#
# 1100px and not 1400px: above roughly 1230px `.admin-container` stops growing, so the widest
# viewport is the *easiest* case and the interesting one is the ordinary laptop window. `drive_at`
# is what reaches it — the desktop half of the sweep renders at 1400 — and the assertion is on
# geometry because the text renders correctly either way. It renders in the wrong place.
class AdminCardRolesWideTest < ApplicationSystemTestCase
  include CardRoleCuration

  drive_at 1100, 900

  setup { sign_in_admin_with_roles }

  test "every column header sits over the checkbox it names at 1100px" do
    visit admin_card_roles_path(played: "0", q: "budew")

    assert_selector "#card-role-#{@card.fingerprint}"

    misplaced = evaluate_script(<<~JS)
      (function () {
        const header = document.querySelector('.data-table-header');
        const row = document.querySelector('.data-table-row');
        const heads = [...header.querySelectorAll('.data-table-cell')];
        const cells = [...row.querySelectorAll('.data-table-cell')];
        const wrong = [];
        cells.forEach((cell, i) => {
          const box = cell.querySelector('input[type=checkbox]');
          if (!box) return;
          const rect = box.getBoundingClientRect();
          const middle = rect.left + rect.width / 2;
          const over = heads.findIndex((head) => {
            const bounds = head.getBoundingClientRect();
            return middle >= bounds.left && middle <= bounds.right;
          });
          if (over !== i) {
            wrong.push(heads[i].textContent.trim() + ' -> ' + (heads[over] ? heads[over].textContent.trim() : 'nothing'));
          }
        });
        return wrong;
      })()
    JS

    assert_empty misplaced,
      "a checkbox sits under a header naming a different role: #{misplaced.inspect}"
  end

  # The other half of the same claim, and the one that says *why* it held: a header wider than the
  # table is how the columns come apart, so it is asserted directly rather than inferred from the
  # alignment above.
  test "the header does not overflow the table it heads at 1100px" do
    visit admin_card_roles_path(played: "0", q: "budew")

    assert_selector "#card-role-#{@card.fingerprint}"

    overflow = evaluate_script(<<~JS)
      (function () {
        const heads = [...document.querySelectorAll('.data-table-header .data-table-cell')];
        const last = heads[heads.length - 1].getBoundingClientRect();
        const container = document.querySelector('.admin-container').getBoundingClientRect();
        return Math.round(last.right - container.right);
      })()
    JS

    assert_operator overflow, :<=, 1, "the header runs #{overflow}px past the page's container"
  end
end

# Twelve cells on one row — the card, its type, nine checkboxes and the Decision cell — on a
# screen 390px wide. (The name read "nine" before two roles were added and was already short by
# one: the Decision cell holding Save and Clear was never counted.) Below
# 768px `.data-table` turns each row into a card whose cells are `display: flex` with a `::before`
# label, and a checkbox cell that overflowed would read as a row wider than the page rather than
# as an error. Geometry, not text: the text renders fine either way, which is exactly what made
# the same defect invisible to a text assertion on the archetype catalog.
class AdminCardRolesNarrowTest < ApplicationSystemTestCase
  include CardRoleCuration

  drive_at 390, 844

  setup { sign_in_admin_with_roles }

  test "a row's twelve cells stay inside the page at 390px" do
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
