require "test_helper"

# DecksController serves both deck lists, so `controller_name` alone cannot tell them apart:
# "Decks" and "Shared decks" used to light up together on every one of its pages. The rule is
# now a nav *section* (Ui::NavLinks.section_for), and what these tests pin is the property that
# makes it worth having — exactly one navbar entry is lit, and it is the right one. The visitor's
# navbar is the reason a link declares its sections rather than the section naming one link:
# with no "Decks" entry of its own, "Shared decks" is what a shared deck's page must light there.
class NavbarActiveSectionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user)
  end

  test "a member's deck pages light one entry each" do
    sign_in @user

    assert_active_nav_link "Decks", decks_path
    assert_active_nav_link "Decks", deck_path(@deck)
    assert_active_nav_link "Shared decks", shared_decks_path
  end

  test "a visitor's deck pages light the only deck entry there is" do
    @deck.update!(shared: true)

    assert_active_nav_link "Shared decks", shared_decks_path
    assert_active_nav_link "Shared decks", deck_path(@deck)
  end

  test "a member's tournament pages light one entry each" do
    sign_in @user

    assert_active_nav_link "Tournaments", tournaments_path
    assert_active_nav_link "Tournaments", tournament_path(tournaments(:one))
    assert_active_nav_link "My tournaments", mine_tournaments_path
  end

  test "a member's own participation page lights My tournaments alone" do
    sign_in @user

    entry = tournament_entries(:one)
    assert_active_nav_link "My tournaments", tournament_entry_path(entry.tournament, entry)
  end

  test "the other sections still light on their own controller" do
    sign_in @user

    assert_active_nav_link "Dashboard", dashboard_path
    assert_active_nav_link "Cards", cards_path
  end

  # ArchetypesController reports controller_name "archetypes", which Ui::NavLinks.section_for
  # resolves with no SECTION_OVERRIDES row of its own. This pins that, instead of the reasoning
  # that says it should — and, being an exactly-one assertion, it is also what would catch the
  # member navbar's entry lighting on a page that is not an archetype page.
  test "a member's archetype pages light the archetype entry alone" do
    sign_in @user

    assert_active_nav_link "Archetypes", archetypes_path
    assert_active_nav_link "Archetypes", archetype_path(archetypes(:ogerpon))
  end

  test "a visitor's tournament pages light the catalog entry" do
    assert_active_nav_link "Tournaments", tournaments_path
    # One section, not two: unlike "Shared decks", this link has no second list to stand in
    # for — a visitor cannot reach /tournaments/mine at all.
    assert_active_nav_link "Tournaments", tournament_path(tournaments(:one))
  end

  # The admin navbar had no coverage here at all, so a new admin screen could light nothing — or
  # two entries — and no test would notice. It is the third navbar built on Ui::NavbarShell and
  # obeys the same rule: one entry lit, and the right one.
  test "an admin page lights one entry in the admin navbar" do
    @user.update!(admin: true)
    sign_in @user

    assert_active_nav_link "Archetypes", admin_archetypes_path
    assert_active_nav_link "Limitless import", new_admin_standings_import_path
  end

  # Admin::CardLabelsController reports controller_name "card_labels", which had no nav_link at
  # all — the admin navbar lit zero entries on every one of its pages, and this is the case that
  # would have caught it (a missing link fails the "exactly one lit" assertion the same way an
  # extra one would).
  test "an admin's card label pages light the card labels entry alone" do
    @user.update!(admin: true)
    sign_in @user

    assert_active_nav_link "Card Labels", admin_card_labels_path
  end

  # Admin::ArchetypesController and ArchetypesController report the *same* controller_name, and
  # both navbars carry a link on that section. That is only harmless because the two navbars are
  # never rendered together — Layouts::AdminLayout renders one, Layouts::ApplicationLayout the
  # other. Asserting the count as well as the label is what makes this a real check: were the
  # admin panel ever moved onto the member layout, /admin/archetypes would light two entries and
  # this would go red rather than merely look right.
  test "the member and admin archetype pages do not light each other's entry" do
    @user.update!(admin: true)
    sign_in @user

    get admin_archetypes_path
    assert_response :success
    assert_select "a.navbar-link[href=?]", archetypes_path, { count: 0 },
      "the admin layout must not render the member navbar"

    get archetypes_path
    assert_response :success
    assert_select "a.navbar-link[href=?]", admin_archetypes_path, { count: 0 },
      "the member layout must not render the admin navbar's archetype link"
  end

  private

  def assert_active_nav_link(label, path)
    get path
    assert_response :success, "expected #{path} to render, got #{response.status}"

    active = css_select("a.navbar-link.active").map { |a| a.text.strip }
    assert_equal [ label ], active, "expected #{path} to light #{label.inspect} alone"
  end
end
