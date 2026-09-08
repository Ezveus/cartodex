require "test_helper"

# DecksController serves both deck lists, so `controller_name` alone cannot tell them apart:
# "Decks" and "Shared decks" used to light up together on every one of its pages. The rule is
# now a nav *section* (Ui::NavLinks.section_for), and what these tests pin is the property that
# makes it worth having — exactly one navbar entry is lit, and it is the right one. The visitor's
# navbar is the reason a link declares its sections rather than the section naming one link:
# with no "Decks" entry of its own, "Shared decks" is what a shared deck's page must light there.
#
# Since the navbar became grouped, "one entry" is a **trail** — a group and the leaf inside it —
# and it is read out of one subtree rather than by collecting two flat lists. That is not
# ceremony: a leaf filed into the wrong group produces an identical flat pair of "one lit trigger,
# one lit leaf", and the misfiling is the only new mistake grouping makes possible.
#
# Every row of both IA tables gets a case. Nine of them are new — the file had none for
# /collections, /tournament_profiles, or nine of the twelve admin screens — and they are not
# padding: a group lights identically from any one of its entries, so a handful of cases would
# leave most leaves free to sit in any group at all, or in none.
class NavbarActiveSectionTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = users(:one)
    @deck = decks(:one)
    @deck.update!(user: @user)
  end

  test "a member's deck pages light one trail each" do
    sign_in @user

    assert_active_nav [ "Decks", "My decks" ], decks_path
    assert_active_nav [ "Decks", "My decks" ], deck_path(@deck)
    assert_active_nav [ "Decks", "Shared decks" ], shared_decks_path
  end

  test "a visitor's deck pages light the only deck entry there is" do
    @deck.update!(shared: true)

    assert_active_nav [ "Shared decks" ], shared_decks_path
    assert_active_nav [ "Shared decks" ], deck_path(@deck)
  end

  test "a member's tournament pages light one trail each" do
    sign_in @user

    assert_active_nav [ "Tournaments", "All tournaments" ], tournaments_path
    assert_active_nav [ "Tournaments", "All tournaments" ], tournament_path(tournaments(:one))
    assert_active_nav [ "Tournaments", "My tournaments" ], mine_tournaments_path
    assert_active_nav [ "Tournaments", "Profiles" ], tournament_profiles_path
  end

  test "a member's own participation page lights My tournaments alone" do
    sign_in @user

    entry = tournament_entries(:one)
    assert_active_nav [ "Tournaments", "My tournaments" ], tournament_entry_path(entry.tournament, entry)
  end

  test "the ungrouped member entries still light on their own controller" do
    sign_in @user

    assert_active_nav [ "Cards" ], cards_path
    # Top level rather than inside Decks▾, so the trail is one deep and no group lights beside it.
    assert_active_nav [ "Collection" ], collections_path
  end

  # Dashboard has no entry of its own since the navbar was grouped: the brand is the only thing
  # pointing there, so the brand is what lights. Reading the brand's own text rather than
  # substituting a literal is what lets the same helper cover the admin panel, whose front page is
  # a different section under a different label — a literal "Dashboard" would have passed here
  # while /admin lit nothing at all, and no case in this file ever visited it.
  test "the brand lights on the page it points at, in all three navbars" do
    assert_active_nav [ "Cartodex" ], root_path

    sign_in @user
    assert_active_nav [ "Cartodex" ], dashboard_path

    @user.update!(admin: true)
    assert_active_nav [ "Cartodex Admin" ], admin_root_path
  end

  # ArchetypesController reports controller_name "archetypes", which Ui::NavLinks.section_for
  # resolves with no SECTION_OVERRIDES row of its own. This pins that, instead of the reasoning
  # that says it should — and, being an exactly-one assertion, it is also what would catch the
  # member navbar's entry lighting on a page that is not an archetype page.
  test "a member's archetype pages light the archetype entry alone" do
    sign_in @user

    assert_active_nav [ "Archetypes" ], archetypes_path
    assert_active_nav [ "Archetypes" ], archetype_path(archetypes(:ogerpon))
  end

  # The hole this closes: `Ui::NavLinks.section_for` resolves both archetype pages to
  # "archetypes", and Ui::PublicNavbar had no link declaring that section, so a visitor on either
  # page lit **zero** entries — outside every assertion this file made, because it named no
  # visitor archetype page. Adding the nav_link without adding this test leaves the same hole
  # for the next entry.
  test "a visitor's archetype pages light the archetype entry alone" do
    assert_active_nav [ "Archetypes" ], archetypes_path
    assert_active_nav [ "Archetypes" ], archetype_path(archetypes(:ogerpon))
  end

  test "a visitor's tournament pages light the catalog entry" do
    assert_active_nav [ "Tournaments" ], tournaments_path
    # One section, not two: unlike "Shared decks", this link has no second list to stand in
    # for — a visitor cannot reach /tournaments/mine at all.
    assert_active_nav [ "Tournaments" ], tournament_path(tournaments(:one))
  end

  # The admin navbar had no coverage here at all, so a new admin screen could light nothing — or
  # two entries — and no test would notice. It is the third navbar built on Ui::NavbarShell and
  # obeys the same rule: one trail lit, and the right one. Every one of the twelve screens is
  # named, because the group's own lit state cannot distinguish them.
  test "every admin screen lights its own trail" do
    @user.update!(admin: true)
    sign_in @user

    assert_active_nav [ "Catalog", "Card Sets" ], admin_card_sets_path
    assert_active_nav [ "Catalog", "Cards" ], admin_cards_path
    assert_active_nav [ "Catalog", "Card Labels" ], admin_card_labels_path
    assert_active_nav [ "Catalog", "Card Roles" ], admin_card_roles_path
    assert_active_nav [ "Content", "Users" ], admin_users_path
    assert_active_nav [ "Content", "Decks" ], admin_decks_path
    assert_active_nav [ "Content", "Archetypes" ], admin_archetypes_path
    assert_active_nav [ "Content", "Standard Pools" ], admin_standard_pools_path
    assert_active_nav [ "Imports", "Imports" ], admin_imports_path
    assert_active_nav [ "Imports", "Limitless import" ], new_admin_standings_import_path
  end

  # "Put the mark in the brand" is half of what this branch was asked for, and nothing rendered
  # asserted it: `Ui::LogoTest` only ever constructs the component directly, so deleting the
  # `render Ui::Logo.new` from Ui::NavbarShell left every suite green — measured. The brand's
  # accessible name is asserted beside it, because since grouping dropped "Dashboard" as an entry
  # the brand is the only thing that reaches it, and a link named "Cartodex" alone is a Dashboard
  # that voice control and a screen reader's link list cannot find.
  test "every navbar's brand carries the mark and says where it goes" do
    get root_path
    assert_response :success
    assert_select "a.navbar-brand svg.navbar-logo", 1
    assert_select %(a.navbar-brand[aria-label="Cartodex — Home"]), 1

    sign_in @user
    get dashboard_path
    assert_response :success
    assert_select "a.navbar-brand svg.navbar-logo", 1
    assert_select %(a.navbar-brand[aria-label="Cartodex — Dashboard"][aria-current="page"]), 1

    @user.update!(admin: true)
    get admin_root_path
    assert_response :success
    assert_select "a.navbar-brand svg.navbar-logo", 1
    assert_select %(a.navbar-brand[aria-label="Cartodex Admin — Dashboard"][aria-current="page"]), 1
  end

  # `aria-current` is the active class's counterpart for everyone not looking at the screen, and it
  # has to land on the leaf rather than on the group: a group is not a page.
  test "the lit leaf carries aria-current and nothing else does" do
    sign_in @user

    get shared_decks_path

    assert_response :success
    assert_select %(a.navbar-link[aria-current="page"]), 1
    assert_select %(a.navbar-link[aria-current="page"]), text: "Shared decks"
    assert_select %(.navbar-group-trigger[aria-current]), 0
  end

  # The email is the widest incompressible item the old row carried, and moving it is half the
  # reason the row now fits. `count: 1` on the bare selector is the half that matters: it says the
  # email is *only* in the panel, rather than also still sitting in the row.
  test "the member's email lives inside the account panel and nowhere else" do
    sign_in @user

    get dashboard_path

    assert_response :success
    assert_select ".navbar-account .navbar-group-panel .navbar-user", text: @user.email, count: 1
    assert_select ".navbar-user", count: 1
  end

  test "the admin's email lives inside the account panel and nowhere else" do
    @user.update!(admin: true)
    sign_in @user

    get admin_root_path

    assert_response :success
    assert_select ".navbar-account .navbar-group-panel .navbar-user", text: @user.email, count: 1
    assert_select ".navbar-user", count: 1
  end

  # Each group's panel has a DOM id that its trigger's aria-controls names, so two groups sharing
  # one id would point half the navbar's ARIA at the wrong panel. The styleguide's own page-wide
  # id check cannot see this: StyleguideController inherits ApplicationController, so that page
  # carries Ui::AppNavbar and never the admin one.
  test "no element in the admin layout shares an id with another" do
    @user.update!(admin: true)
    sign_in @user

    get admin_root_path

    assert_response :success
    ids = css_select("[id]").map { |element| element["id"] }
    assert_equal ids.uniq, ids, "duplicate ids in the admin layout: #{(ids - ids.uniq).inspect}"
  end

  # Admin::ArchetypesController and ArchetypesController report the *same* controller_name, and
  # both navbars carry an entry on that section. That is only harmless because the two navbars are
  # never rendered together — Layouts::AdminLayout renders one, Layouts::ApplicationLayout the
  # other. Asserting the trail as well as the label is what makes this a real check: were the
  # admin panel ever moved onto the member layout, /admin/archetypes would light two trails and
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
      "the member layout must not render the admin navbar's archetype entry"
  end

  private

  def assert_active_nav(trail, path)
    get path
    assert_response :success, "expected #{path} to render, got #{response.status}"

    assert_equal trail, active_nav_trail, "expected #{path} to light #{trail.inspect}"
  end

  # The lit trail, read out of the navbar's own tree: [group, leaf], [leaf], or [brand]. Reading it
  # this way rather than by concatenating two `css_select`s is what makes a misfiled leaf visible —
  # a leaf lit inside a group whose trigger is dark, or beside a group that is lit for another
  # reason, produces the same flat pair as a correct one.
  def active_nav_trail
    navbar = css_select("nav.navbar").first
    assert navbar, "no navbar was rendered at all"

    groups = navbar.css(".navbar-group")
    lit, dark = groups.partition { |group| group.at_css(".navbar-group-trigger.active") }

    assert_operator lit.size, :<=, 1,
      "#{lit.size} groups are lit at once: #{lit.map { |g| trigger_label(g) }.inspect}"
    dark.each do |group|
      assert_empty group.css("a.navbar-link.active").map { |leaf| leaf.text.strip },
        "an unlit group holds a lit leaf"
    end

    trail = navbar.css("a.navbar-brand.active").map { |brand| brand.text.strip }

    lit.each do |group|
      trail << trigger_label(group)
      leaves = group.css(".navbar-group-panel a.navbar-link.active").map { |leaf| leaf.text.strip }
      assert_equal 1, leaves.size, "the lit group holds #{leaves.size} lit leaves: #{leaves.inspect}"
      trail.concat(leaves)
    end

    # Ungrouped entries — "Cards", "Archetypes", and every link the visitor's navbar carries.
    trail + navbar.css(".navbar-links > a.navbar-link.active").map { |leaf| leaf.text.strip }
  end

  def trigger_label(group)
    group.at_css(".navbar-group-trigger").text.strip
  end
end
